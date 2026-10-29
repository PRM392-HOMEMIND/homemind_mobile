import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:homemind_mobile/features/auth/domain/account_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';

import 'support/mock_auth_service.dart';

import 'package:homemind_mobile/features/auth/domain/auth_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const profile = UserProfile(
    userId: '11111111-1111-4111-8111-111111111111',
    email: 'demo@homemind.local',
    displayName: 'Minh Anh',
    workspaceId: '22222222-2222-4222-8222-222222222222',
    workspaceName: 'Nhà Minh Anh',
    workspaceType: 'household',
    role: 'owner',
  );

  late BackendAssistantService service;
  late List<http.Request> requests;
  late MockAuthService auth;

  setUp(() {
    EnvConfig.backendBaseUrl = 'http://homemind.test/v1';
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer access-token');
      final path = request.url.path;
      final status = request.url.queryParameters['status'];

      if (path.endsWith('/me')) return _json(profileJson);
      if (path.endsWith('/home')) return _json(homeJson);
      if (path.endsWith('/inventory')) return _json(inventoryJson);
      if (path.endsWith('/notifications') && request.method == 'GET') {
        return _json(notificationListJson);
      }
      if (path.endsWith('/read') || path.endsWith('/read-all')) {
        return _json({'ok': true});
      }
      if (path.endsWith('/shopping-items')) {
        return _json({
          'items': status == 'needed'
              ? [shoppingJson]
              : <Map<String, Object?>>[],
          'suggestions': status == 'needed'
              ? [
                  {
                    'name': 'Trứng',
                    'reason': 'out',
                    'productId': '33333333-3333-4333-8333-333333333333',
                  },
                ]
              : <Map<String, Object?>>[],
          'total': status == 'needed' ? 1 : 0,
        });
      }
      return _json({
        'error': {'message': 'not found'},
      }, statusCode: 404);
    });
    auth = MockAuthService(
      initialOnboardingCompleted: true,
      initialSession: AuthSession(
        token: 'access-token',
        profile: profile,
        loginTime: DateTime(2026),
      ),
      delay: Duration.zero,
    );
    service = BackendAssistantService(
      authService: auth,
      profile: profile,
      client: client,
    );
  });

  void transport(Future<http.Response> Function(http.Request) handler) {
    service = BackendAssistantService(
      authService: auth,
      profile: profile,
      client: MockClient((request) async {
        requests.add(request);
        expect(request.headers['authorization'], 'Bearer access-token');
        return handler(request);
      }),
    );
  }

  test(
    'workspace revocation cannot retain a session when context refresh fails',
    () async {
      transport((request) async {
        if (request.url.path.endsWith('/me')) {
          throw http.ClientException('controlled local network loss');
        }
        return _json({
          'error': {'code': 'FORBIDDEN', 'message': 'Scope revoked'},
        }, statusCode: 403);
      });
      await expectLater(
        service.getInventory(),
        throwsA(isA<HomeMindApiException>()),
      );
      expect(await auth.getCurrentSession(), isNull);
    },
  );

  test('recovers one closed-header read with the same authorization', () async {
    transport((request) async {
      if (requests.length == 1) {
        throw http.ClientException(
          'Connection closed before full header was received',
        );
      }
      return _json({'plans': <Object>[]});
    });
    expect(await service.billing.plans(), {
      'plans': <Object>[],
      'checkoutEnabled': false,
    });
    expect(requests.length, 2);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(requests[0].url, requests[1].url);
  });

  test('stops after the second closed-header read failure', () async {
    transport((request) async {
      throw http.ClientException(
        'Connection closed before full header was received',
      );
    });
    await expectLater(
      service.billing.plans(),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 2);
  });

  test('independent AI requests complete immediately in their own order; duplicate input coalesces', () async {
    final gates = <String, Completer<http.Response>>{};
    final started = Completer<void>();
    transport((request) {
      final body = jsonDecode(request.body) as Map;
      final input = (body['input'] as Map)['text'] as String;
      gates[input] = Completer<http.Response>();
      if (gates.length == 3) started.complete();
      return gates[input]!.future;
    });
    final order = <String>[];
    final a = service.turn(text: 'slow').then((value) {
      order.add('slow');
      return value;
    });
    final b = service.turn(text: 'fast').then((value) {
      order.add('fast');
      return value;
    });
    final duplicate = service.turn(text: 'fast');
    final c = service.turn(text: 'medium').then((value) {
      order.add('medium');
      return value;
    });
    await started.future;
    expect(requests, hasLength(3));
    http.Response result(String name) => _json({
      'schemaVersion': '1.0',
      'turnId': name,
      'kind': 'unknown',
      'dictionaryVersion': '1.1.0',
      'message': 'Kết quả thử nghiệm',
    });
    gates['fast']!.complete(result('fast'));
    await b;
    await duplicate;
    expect(order, ['fast']);
    gates['medium']!.complete(result('medium'));
    await c;
    expect(order, ['fast', 'medium']);
    gates['slow']!.complete(result('slow'));
    await a;
    expect(order, ['fast', 'medium', 'slow']);
    expect(
      requests.map((r) => (jsonDecode(r.body) as Map)['requestId']).toSet(),
      hasLength(3),
    );
  });

  test(
    'four durable ambiguous intents cannot be overwritten by a fifth request',
    () async {
      transport(
        (_) async => throw http.ClientException('synthetic lost response'),
      );
      for (var i = 0; i < 4; i++) {
        await expectLater(
          service.turn(text: 'pending-$i'),
          throwsA(isA<HomeMindApiException>()),
        );
      }
      final original = requests.first.body;
      await expectLater(
        service.turn(text: 'fifth'),
        throwsA(
          isA<HomeMindApiException>().having(
            (e) => e.code,
            'bounded intents',
            'ASSISTANT_PENDING_INTENTS',
          ),
        ),
      );
      expect(requests, hasLength(4));
      await expectLater(
        service.turn(text: 'pending-0'),
        throwsA(isA<HomeMindApiException>()),
      );
      expect(requests.last.body, original);
    },
  );

  test('lost turn response and service recreation preserve logical requestId and payload', () async {
    transport((request) async {
      throw http.ClientException('Connection refused');
    });
    await expectLater(
      service.turn(text: 'owned retry'),
      throwsA(isA<HomeMindApiException>()),
    );
    final first = jsonDecode(requests.single.body) as Map;
    expect(first['requestId'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    transport(
      (request) async => _json({
        'schemaVersion': '1.0',
        'turnId': 'owned',
        'kind': 'unknown',
        'dictionaryVersion': '1.1.0',
        'message': 'Owned replay',
        'toolsUsed': [],
        'warnings': [],
      }),
    );
    final result = await service.turn(text: 'owned retry');
    expect(result.kind, AssistantTurnKind.unknown);
    expect(jsonDecode(requests.last.body), first);
  });

  test('never replays an assistant POST after closed headers', () async {
    transport((request) async {
      throw http.ClientException(
        'Connection closed before full header was received',
      );
    });
    await expectLater(
      service.turn(text: 'test'),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 1);
    expect(requests.single.method, 'POST');
  });

  for (final rejection in [
    (400, 'VALIDATION_ERROR'),
    (422, 'VALIDATION_ERROR'),
    (429, 'VOICE_QUOTA_EXHAUSTED'),
    (409, 'ASSISTANT_REQUEST_EXPIRED'),
  ]) {
    test(
      'definite ${rejection.$2} ends intent without an automatic retry',
      () async {
        transport(
          (request) async => _json({
            'error': {'code': rejection.$2},
          }, statusCode: rejection.$1),
        );
        await expectLater(
          service.turn(text: 'owned retry'),
          throwsA(isA<HomeMindApiException>()),
        );
        expect(requests.length, 1);
        final first = jsonDecode(requests.single.body) as Map;
        transport(
          (request) async => _json({
            'schemaVersion': '1.0',
            'turnId': 'owned',
            'kind': 'unknown',
            'dictionaryVersion': '1.1.0',
            'message': 'Owned',
            'toolsUsed': [],
            'warnings': [],
          }),
        );
        await service.turn(text: 'owned retry');
        expect(
          (jsonDecode(requests.last.body) as Map)['requestId'],
          isNot(first['requestId']),
        );
      },
    );
  }
  for (final pending in [
    (503, 'AI_UNAVAILABLE'),
    (409, 'ASSISTANT_REQUEST_IN_PROGRESS'),
  ]) {
    test(
      '${pending.$2} retains the same durable payload for explicit retry',
      () async {
        transport(
          (request) async => _json({
            'error': {'code': pending.$2},
          }, statusCode: pending.$1),
        );
        await expectLater(
          service.turn(text: 'owned retry'),
          throwsA(isA<HomeMindApiException>()),
        );
        final first = jsonDecode(requests.single.body);
        await expectLater(
          service.turn(text: 'owned retry'),
          throwsA(isA<HomeMindApiException>()),
        );
        expect(jsonDecode(requests.last.body), first);
        expect(requests.length, 2);
      },
    );
  }

  test('does not retry other transport errors', () async {
    transport((request) async {
      throw http.ClientException('Connection refused');
    });
    await expectLater(
      service.billing.plans(),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 1);
  });

  test('does not replay a billing read after identity changes', () async {
    transport((request) async {
      await auth.logout();
      throw http.ClientException(
        'Connection closed before full header was received',
      );
    });
    await expectLater(
      service.billing.plans(),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 1);
  });

  test('read recovery shares the original 25 second budget', () {
    fakeAsync((time) {
      transport((request) async {
        if (requests.length == 1) {
          await Future<void>.delayed(const Duration(seconds: 24));
          throw http.ClientException(
            'Connection closed before full header was received',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        return _json({'plans': <Object>[]});
      });
      Object? failure;
      service.billing.plans().then<void>(
        (_) => fail('Unexpected success'),
        onError: (Object e) {
          failure = e;
        },
      );
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 25));
      time.flushMicrotasks();
      expect(failure, isA<HomeMindApiException>());
      expect(requests.length, 2);
    });
  });

  void refreshing(
    Future<http.Response> Function(int) send,
    Future<String> Function() refresh,
  ) {
    final session = AuthSession(
      token: 'access-token',
      profile: profile,
      loginTime: DateTime(2026),
    );
    service = BackendAssistantService(
      authService: _RefreshingAuth(session, refresh),
      profile: profile,
      client: MockClient((request) {
        requests.add(request);
        return send(requests.length);
      }),
    );
  }

  test('closed-header allowance is shared across the auth refresh', () async {
    int refreshes = 0;
    refreshing(
      (n) async {
        if (n == 2) return _json({}, statusCode: 401);
        throw http.ClientException(
          'Connection closed before full header was received',
        );
      },
      () async {
        refreshes++;
        return 'refreshed-test-token';
      },
    );
    await expectLater(
      service.billing.plans(),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 3);
    expect(refreshes, 1);
  });
  test(
    'one read replay remains available if the first failure is after refresh',
    () async {
      refreshing((n) async {
        if (n == 1) return _json({}, statusCode: 401);
        if (n == 2) {
          throw http.ClientException(
            'Connection closed before full header was received',
          );
        }
        return _json({'plans': <Object>[]});
      }, () async => 'refreshed-test-token');
      expect(await service.billing.plans(), {
        'plans': <Object>[],
        'checkoutEnabled': false,
      });
      expect(requests.length, 3);
    },
  );
  for (final refreshDelay in [
    const Duration(seconds: 30),
    const Duration(seconds: 4),
  ]) {
    test(
      'original deadline bounds auth refresh and its retry: $refreshDelay',
      () {
        fakeAsync((time) {
          refreshing(
            (n) async {
              await Future<void>.delayed(Duration(seconds: n == 1 ? 20 : 2));
              return n == 1
                  ? _json({}, statusCode: 401)
                  : _json({'plans': <Object>[]});
            },
            () async {
              await Future<void>.delayed(refreshDelay);
              return 'refreshed-test-token';
            },
          );
          Object? failure;
          service.billing.plans().then<void>(
            (_) => fail('Deadline was reset'),
            onError: (Object e) {
              failure = e;
            },
          );
          time.flushMicrotasks();
          time.elapse(const Duration(seconds: 24));
          time.flushMicrotasks();
          expect(failure, isNull);
          time.elapse(const Duration(seconds: 1));
          time.flushMicrotasks();
          expect(failure, isA<HomeMindApiException>());
          expect(requests.length, refreshDelay.inSeconds == 30 ? 1 : 2);
        });
      },
    );
  }
  test('auth refresh cannot replay a closed-header mutation', () async {
    refreshing((n) async {
      if (n == 1) return _json({}, statusCode: 401);
      throw http.ClientException(
        'Connection closed before full header was received',
      );
    }, () async => 'refreshed-test-token');
    await expectLater(
      service.turn(text: 'test'),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(requests.length, 2);
    expect(requests.every((r) => r.method == 'POST'), isTrue);
  });

  test(
    'profile PATCH refreshes once and retries the same pending fields',
    () async {
      var refreshes = 0;
      refreshing(
        (n) async => n == 1
            ? _json({}, statusCode: 401)
            : _json({...profileJson, 'displayName': 'Committed after refresh'}),
        () async {
          refreshes++;
          return 'refreshed-test-token';
        },
      );
      final saved = await service.updateProfile(
        displayName: 'Committed after refresh',
      );
      expect(saved.displayName, 'Committed after refresh');
      expect(refreshes, 1);
      expect(requests, hasLength(2));
      expect(
        requests.every((r) => r.method == 'PATCH' && r.url.path == '/v1/me'),
        isTrue,
      );
      expect(jsonDecode(requests.first.body), {
        'displayName': 'Committed after refresh',
      });
      expect(requests.last.body, requests.first.body);
    },
  );

  test('profile PATCH failed refresh never sends another mutation', () async {
    var refreshes = 0;
    refreshing((_) async => _json({}, statusCode: 401), () async {
      refreshes++;
      throw const AuthException('Synthetic refresh rejected');
    });
    await expectLater(
      service.updateProfile(displayName: 'Not committed'),
      throwsA(isA<HomeMindApiException>()),
    );
    expect(refreshes, 1);
    expect(requests, hasLength(1));
  });

  test('profile PATCH second401 stops refresh retry and closes the rejected session', () async {
    var refreshes = 0;
    refreshing(
      (_) async => _json({
        'error': {'message': 'Synthetic session rejected'},
      }, statusCode: 401),
      () async {
        refreshes++;
        return 'refreshed-test-token';
      },
    );
    await expectLater(
      service.updateProfile(displayName: 'Not committed'),
      throwsA(
        isA<HomeMindApiException>().having(
          (e) => e.message,
          'closed-session error',
          'Tài khoản đã thay đổi.',
        ),
      ),
    );
    expect(refreshes, 1);
    expect(requests, hasLength(2));
    expect(await service.authService.getCurrentSession(), isNull);
  });

  test(
    'profile PATCH identity loss during refresh refuses cross-session retry',
    () async {
      refreshing((_) async => _json({}, statusCode: 401), () async {
        await service.authService.logout();
        return 'refreshed-test-token';
      });
      await expectLater(
        service.updateProfile(displayName: 'Not committed'),
        throwsA(isA<HomeMindApiException>()),
      );
      expect(requests, hasLength(1));
    },
  );

  for (final delay in [
    const Duration(seconds: 30),
    const Duration(seconds: 4),
  ]) {
    test(
      'profile PATCH original deadline bounds refresh and retry: $delay',
      () {
        fakeAsync((time) {
          refreshing(
            (n) async {
              await Future<void>.delayed(Duration(seconds: n == 1 ? 20 : 2));
              return n == 1 ? _json({}, statusCode: 401) : _json(profileJson);
            },
            () async {
              await Future<void>.delayed(delay);
              return 'refreshed-test-token';
            },
          );
          Object? failure;
          service
              .updateProfile(displayName: 'Not committed')
              .then<void>(
                (_) => fail('Profile deadline was reset'),
                onError: (Object e) {
                  failure = e;
                },
              );
          time.flushMicrotasks();
          time.elapse(const Duration(seconds: 24));
          time.flushMicrotasks();
          expect(failure, isNull);
          time.elapse(const Duration(seconds: 1));
          time.flushMicrotasks();
          expect(failure, isA<HomeMindApiException>());
          expect(requests.length, delay.inSeconds == 30 ? 1 : 2);
          expect(requests.every((r) => r.method == 'PATCH'), isTrue);
        });
      },
    );
  }

  test(
    'maps backend profile, home, inventory and all shopping statuses',
    () async {
      final me = await service.getMe();
      final home = await service.getHomeSummary();
      final inventory = await service.getInventory();
      final shopping = await service.getShoppingList();
      final notifications = await service.getNotifications();
      await service.markNotificationRead(notifications.items.single.id);
      await service.markAllNotificationsRead();

      expect(me.displayName, 'Minh Anh');
      expect(home.totalProducts, 2);
      expect(inventory.single.name, 'Sữa chua Vinamilk');
      expect(shopping.items.single.name, 'Trứng');
      expect(shopping.suggestions.single['reason'], 'out');
      expect(notifications.unreadCount, 1);
      expect(notifications.items.single.read, isFalse);
      expect(
        requests.any(
          (request) =>
              request.method == 'PATCH' && request.url.path.endsWith('/read'),
        ),
        isTrue,
      );
      expect(
        requests.any(
          (request) =>
              request.method == 'POST' &&
              request.url.path.endsWith('/read-all'),
        ),
        isTrue,
      );
      expect(
        requests
            .where((request) => request.url.path.endsWith('/shopping-items'))
            .length,
        3,
      );
    },
  );
}

class _RefreshingAuth extends MockAuthService implements SessionRefreshService {
  _RefreshingAuth(AuthSession session, this.refresh)
    : super(initialSession: session, delay: Duration.zero);
  final Future<String> Function() refresh;
  @override
  Future<String> refreshAccessToken(String rejectedToken) => refresh();
  @override
  Stream<AuthSession?> get sessionChanges => const Stream.empty();
}

http.Response _json(Object value, {int statusCode = 200}) => http.Response(
  jsonEncode(value),
  statusCode,
  headers: {'content-type': 'application/json'},
);

const profileJson = <String, Object?>{
  'userId': '11111111-1111-4111-8111-111111111111',
  'email': 'demo@homemind.local',
  'displayName': 'Minh Anh',
  'workspaceId': '22222222-2222-4222-8222-222222222222',
  'workspaceName': 'Nhà Minh Anh',
  'workspaceType': 'household',
  'role': 'owner',
};

const homeJson = <String, Object?>{
  'totalProducts': 2,
  'inStockCount': 1,
  'outCount': 1,
  'expiredCount': 0,
  'expiringSoonCount': 1,
  'shoppingNeededCount': 1,
  'freePlanLimit': 30,
  'plan': 'free',
  'productCountTowardLimit': 2,
  'expiringSoon': <Object?>[],
  'expired': <Object?>[],
  'alerts': <Object?>[],
};

const notificationListJson = <String, Object?>{
  'unreadCount': 1,
  'items': [
    {
      'id': 'expiry.33333333-3333-4333-8333-333333333333.2026-10-03',
      'title': 'Sữa chua Vinamilk',
      'body': 'Hết hạn 2026-10-03',
      'context': 'Dữ liệu tồn kho hiện tại',
      'type': 'expiry',
      'read': false,
    },
  ],
};

const inventoryJson = <String, Object?>{
  'total': 1,
  'items': [
    {
      'productId': '33333333-3333-4333-8333-333333333333',
      'name': 'Sữa chua Vinamilk',
      'category': 'Thực phẩm',
      'quantity': 2,
      'unit': 'hộp',
      'expiryDate': '2026-10-03',
      'expiryLevel': 'urgent',
      'status': 'in_stock',
    },
  ],
};

const shoppingJson = <String, Object?>{
  'id': '44444444-4444-4444-8444-444444444444',
  'name': 'Trứng',
  'quantity': 10,
  'unit': 'quả',
  'status': 'needed',
  'source': 'repurchase',
};
