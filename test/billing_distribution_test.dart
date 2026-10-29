import 'support/restored_plan_billing_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_distribution.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_service.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:homemind_mobile/features/home/presentation/paywall_sheet.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/auth/domain/auth_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/recording_plan_service.dart';
import 'support/mock_auth_service.dart';

const legacy = <String, Object?>{
  'id': '00000000-0000-4000-8000-000000000001',
  'orderCode': '2000000000999',
  'status': 'PENDING',
  'financialState': 'UNPAID',
  'fulfillment': 'NONE',
  'amountPaid': 0,
  'price': {
    'plan': 'personal',
    'amount': 29000,
    'checkoutUrl': 'https://pay.payos.vn/nested',
  },
  'createdAt': '2026-10-06T01:00:00Z',
  'expiresAt': '2026-10-06T01:30:00Z',
  'serverNow': '2026-10-06T01:01:00Z',
  'checkoutUrl': 'https://pay.payos.vn/owned',
  'qr': {
    'payload': 'OWNED_QR_PAYLOAD',
    'bin': '970999',
    'accountNumber': 'OWNED_ACCOUNT',
    'accountName': 'OWNED_RECEIVER',
    'description': 'OWNED_MEMO',
    'amount': 29000,
  },
  'futureProviderField': 'OWNED_INSTRUCTION',
};

class DistributionGateway implements BillingGateway {
  DistributionGateway(this.payment);
  Map<String, Object?>? payment;
  int creates = 0, checks = 0, cancels = 0;
  @override
  Future<Map<String, Object?>> plans() async => {
    'checkoutEnabled': true,
    'plans': [
      {
        'id': 'personal-month-v2',
        'plan': 'personal',
        'amount': 29000,
        'workspaceTypes': ['household'],
      },
    ],
  };
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => {
    'entitlement': {'plan': 'free', 'source': 'free'},
    'workspaceType': 'household',
    'eligibility': {'personal': null},
    'payments': [if (payment?['id'] != null) payment!],
  };
  @override
  Future<Map<String, Object?>?> pending() async => payment;
  @override
  Future<Map<String, Object?>> create(String priceId) async {
    creates++;
    return legacy;
  }

  @override
  Future<Map<String, Object?>> reconcile(String id) async {
    checks++;
    return legacy;
  }

  @override
  Future<Map<String, Object?>> cancel(String id) async {
    cancels++;
    return legacy;
  }

  @override
  Future<void> clearPending() async {}
}

void expectNoInstructions() {
  for (final key in [
    'billing_transfer_details',
    'billing_official_qr',
    'billing_countdown',
    'billing_buy_personal',
  ]) {
    expect(find.byKey(Key(key)), findsNothing, reason: key);
  }
  for (final text in [
    'OWNED_ACCOUNT',
    'OWNED_RECEIVER',
    'OWNED_MEMO',
    '970999',
    'OWNED_QR_PAYLOAD',
    'OWNED_INSTRUCTION',
    'pay.payos.vn',
    'Sao chép số tài khoản',
    'Sao chép nội dung chuyển khoản',
    'Sao chép đường dẫn thanh toán',
    'Thông tin chuyển khoản',
    'Khôi phục đơn đang chờ',
    'Mở lại trang thanh toán',
    'Hủy đơn chưa thanh toán',
    'để thanh toán',
  ]) {
    expect(find.textContaining(text), findsNothing, reason: text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppText.setLanguage('vi', persist: false);
  });
  test('actual Flutter HTTP client sends its compiled channel and store cannot submit legacy upgrade', () async {
    const profile = UserProfile(
      userId: 'owned-user',
      email: 'owned@example.com',
      displayName: 'Owned',
      workspaceId: 'owned-workspace',
      workspaceName: 'Owned',
      workspaceType: 'household',
      role: 'owner',
    );
    final auth = MockAuthService(
      initialSession: AuthSession(
        token: 'owned-test-token',
        profile: profile,
        loginTime: DateTime(2026),
      ),
      delay: Duration.zero,
    );
    EnvConfig.backendBaseUrl = 'https://homemind.test/v1';
    final requests = <http.Request>[];
    final service = BackendAssistantService(
      authService: auth,
      profile: profile,
      client: MockClient((request) async {
        requests.add(request);
        expect(
          request.headers['x-homemind-distribution'],
          EnvConfig.distribution,
        );
        expect(request.headers['authorization'], 'Bearer owned-test-token');
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/plans')
                ? {'plans': [], 'checkoutEnabled': true}
                : {
                    'payments': [legacy],
                  },
          ),
          200,
        );
      }),
    );
    expect(
      (await service.billing.plans())['checkoutEnabled'],
      EnvConfig.externalBillingAllowed,
    );
    final overview = await service.billing.overview();
    if (!EnvConfig.externalBillingAllowed) {
      expect(jsonEncode(overview), isNot(contains('OWNED_')));
      await expectLater(
        service.requestUpgrade(plan: 'personal', source: 'paywall'),
        throwsStateError,
      );
      expect(requests.every((request) => request.method == 'GET'), true);
    } else {
      expect((overview['payments'] as List).first, legacy);
      await service.requestUpgrade(plan: 'personal', source: 'paywall');
      expect(requests.last.method, 'POST');
    }
  });
  test(
    'payment-disabled policy rejects every channel in debug and release',
    () {
      for (final debug in [true, false]) {
        for (final channel in [
          'store',
          'direct',
          '',
          'unknown',
          'DIRECT',
          'direct,store',
        ]) {
          expect(
            EnvConfig.externalBillingAllowedFor(
              debug: debug,
              distribution: channel,
            ),
            false,
          );
        }
        expect(EnvConfig.externalBillingAllowedFor(debug: debug), false);
        expect(
          EnvConfig.externalBillingAllowedFor(
            debug: debug,
            distribution: 'direct',
          ),
          false,
        );
      }
    },
  );
  test('consumption projection strips stale and unknown provider instructions including nested snapshots', () {
    final projected = consumptionPayment(legacy);
    expect(projected['price'], {'plan': 'personal'});
    expect(projected['status'], 'PENDING');
    expect(projected.keys.toSet(), {
      'id',
      'status',
      'financialState',
      'fulfillment',
      'amountPaid',
      'createdAt',
      'price',
      'grant',
    });
    expect(jsonEncode(projected), isNot(contains('OWNED_')));
    expect(legacy['checkoutUrl'], 'https://pay.payos.vn/owned');
    final paid = consumptionPayment({
      ...legacy,
      'financialState': 'PAID',
      'amountPaid': 29000,
    });
    expect((paid['price'] as Map)['amount'], 29000);
    expect(paid['amountPaid'], 29000);
  });
  test('compile-time policy protects URL boundary and overrides permissive test gateway injection', () async {
    final requests = <String>[];
    final service = RemoteBillingService(
      userId: 'owned',
      workspaceId: 'owned',
      externalBillingAllowed: () => true,
      request: (method, path, {body, idempotencyKey}) async {
        requests.add('$method $path');
        return path == '/billing/plans'
            ? {'checkoutEnabled': true}
            : {
                'payments': [legacy],
              };
      },
    );
    expect(
      (await service.plans())['checkoutEnabled'],
      EnvConfig.externalBillingAllowed,
    );
    final overview = await service.overview();
    if (EnvConfig.externalBillingAllowed) {
      expect(
        billingCheckoutUri('https://pay.payos.vn/owned').host,
        'pay.payos.vn',
      );
      expect((overview['payments'] as List).first, legacy);
    } else {
      expect(
        () => billingCheckoutUri('https://pay.payos.vn/owned'),
        throwsStateError,
      );
      await expectLater(service.create('personal-month-v2'), throwsStateError);
      await expectLater(
        Future.sync(() => service.reconcile('owned')),
        throwsStateError,
      );
      await expectLater(
        Future.sync(() => service.cancel('owned')),
        throwsStateError,
      );
      expect(requests.every((r) => r.startsWith('GET ')), true);
      expect(jsonEncode(overview), isNot(contains('OWNED_')));
    }
  });
  test('stale saved pending order or unresolved create cannot be revived by a store session', () async {
    const storage = FlutterSecureStorage();
    const key = 'homemind.billing.pending.owned.owned';
    for (final includeId in [false, true]) {
      await storage.write(
        key: key,
        value: jsonEncode({
          'priceId': 'personal-month-v2',
          'key': '00000000-0000-4000-8000-000000000002',
          if (includeId) 'id': legacy['id'],
        }),
      );
      var requests = 0;
      final service = RemoteBillingService(
        userId: 'owned',
        workspaceId: 'owned',
        request: (method, path, {body, idempotencyKey}) async {
          requests++;
          expect(method, 'GET');
          return legacy;
        },
      );
      final pending = await service.pending();
      if (EnvConfig.externalBillingAllowed) {
        expect(
          pending,
          includeId
              ? legacy
              : {'unresolvedIntent': true, 'priceId': 'personal-month-v2'},
        );
        expect(requests, includeId ? 1 : 0);
      } else {
        expect(pending, isNull);
        expect(requests, 0);
        expect(await storage.read(key: key), isNull);
      }
    }
  });
  for (final scenario in ['none', 'pending', 'unresolved', 'direct-route']) {
    testWidgets(
      '$scenario state respects store restriction across route remount',
      (tester) async {
        final gateway = DistributionGateway(
          scenario == 'none'
              ? null
              : scenario == 'unresolved'
              ? {'unresolvedIntent': true, 'priceId': 'personal-month-v2'}
              : legacy,
        );
        var launches = 0, copies = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') copies++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        for (var mount = 0; mount < 2; mount++) {
          await tester.pumpRestoredPlanBillingWidget(
            MaterialApp(
              home: BillingPage(
                gateway: gateway,
                refreshEntitlements: () async {},
                initialPayment: scenario == 'direct-route'
                    ? () => Future.value(legacy)
                    : null,
                launchCheckout: (uri) async {
                  launches++;
                  return true;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!EnvConfig.externalBillingAllowed) {
            for (var scroll = 0; scroll < 9; scroll++) {
              expectNoInstructions();
              expect(tester.takeException(), isNull);
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -350),
              );
              await tester.pumpAndSettle();
            }
            expect(gateway.creates, 0);
            expect(gateway.checks, 0);
            expect(gateway.cancels, 0);
            expect(launches, 0);
            expect(copies, 0);
          } else if (scenario == 'pending' || scenario == 'direct-route') {
            await tester.scrollUntilVisible(
              find.byKey(const Key('billing_official_qr')),
              200,
              maxScrolls: 30,
            );
            expect(
              find.byKey(const Key('billing_official_qr')),
              findsOneWidget,
            );
          }
          await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
  testWidgets(
    'standalone payment card and legacy sheet cannot bypass the build gate',
    (tester) async {
      var actions = 0;
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BillingPaymentCard(
                payment: legacy,
                stateText: 'Owned order status',
                pending: true,
                checkoutEnabled: true,
                busy: false,
                onCheck: () => actions++,
                onOpen: () => actions++,
                onCancel: () => actions++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!EnvConfig.externalBillingAllowed) {
        expectNoInstructions();
        expect(find.byType(ButtonStyleButton), findsNothing);
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        expectNoInstructions();
        expect(find.textContaining('null'), findsNothing);
        expect(find.textContaining('Hiệu lực:'), findsNothing);
        expect(actions, 0);
      } else {
        expect(find.byKey(const Key('billing_official_qr')), findsOneWidget);
      }
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: PaywallSheet(
              service: RecordingPlanService(plan: 'free'),
              source: 'paywall',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!EnvConfig.externalBillingAllowed) {
        expect(find.byType(ButtonStyleButton), findsNothing);
        expect(find.textContaining('liên hệ'), findsNothing);
        expect(find.textContaining('Đăng ký'), findsNothing);
        expect(
          find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
          findsOneWidget,
        );
      }
      await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
    },
  );
}
