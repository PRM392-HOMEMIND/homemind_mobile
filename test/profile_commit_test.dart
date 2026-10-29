import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/auth/domain/account_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_models.dart';

import 'support/mock_auth_service.dart';
import 'support/recording_profile_service.dart';

const old = UserProfile(userId: 'owned', email: 'fixture@example.invalid',
  displayName: 'Original', workspaceId: 'owned-ws', workspaceName: 'Fixture',
  workspaceType: 'household', role: 'owner');

class ProfileTransport implements AssistantService {
  UserProfile server = old;
  final writes = <Completer<UserProfile>>[];
  bool readFails = false;
  int reads = 0;
  @override
  Future<UserProfile> getMe() async {
    reads++;
    if (readFails) throw TimeoutException('fixture read');
    return server;
  }
  @override
  Future<UserProfile> updateProfile({String? displayName, String? phone,
      String? address, String? language}) {
    final gate = Completer<UserProfile>();
    writes.add(gate);
    return gate.future.then((p) => server = p);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileTransport inner;
  late CachedAssistantService cache;
  setUp(() {
    inner = ProfileTransport();
    cache = CachedAssistantService(inner, initialProfile: old);
  });
  tearDown(() => cache.dispose());
  Future<void> begin() => Future<void>.delayed(Duration.zero);

  test('validation rejection keeps committed profile and propagates to form', () async {
    final errors = <String>[];
    final sub = cache.backgroundErrors.listen(errors.add);
    final save = cache.updateProfile(phone: 'rejected');
    final assertion = expectLater(save, throwsA(isA<HomeMindApiException>()));
    await begin();
    inner.writes.single.completeError(const HomeMindApiException('invalid', statusCode: 400));
    await assertion;
    expect((await cache.getMe()).displayName, 'Original');
    expect(inner.reads, 0);
    expect(errors, isEmpty);
    await sub.cancel();
  });

  test('rapid saves are serialized; a failed first save cannot roll back second', () async {
    final first = cache.updateProfile(displayName: 'Rejected');
    final failure = expectLater(first, throwsA(isA<HomeMindApiException>()));
    final second = cache.updateProfile(displayName: 'Committed');
    await begin();
    expect(inner.writes, hasLength(1));
    inner.writes[0].completeError(const HomeMindApiException('invalid', statusCode: 400));
    await failure;
    await begin();
    expect(inner.writes, hasLength(2));
    inner.writes[1].complete(old.copyWith(displayName: 'Committed'));
    await second;
    expect((await cache.getMe()).displayName, 'Committed');
  });

  test('lost successful response reconciles server state without replay PATCH', () async {
    final pending = cache.updateProfile(displayName: 'Committed');
    await begin();
    inner.server = old.copyWith(displayName: 'Committed');
    inner.writes.single.completeError(TimeoutException('fixture lost response'));
    expect((await pending).displayName, 'Committed');
    expect(inner.writes, hasLength(1));
    expect(inner.reads, 1);
  });

  test('uncertain save with unchanged server is reported honestly', () async {
    final pending = cache.updateProfile(displayName: 'Not committed');
    final failure = expectLater(pending, throwsA(isA<ProfileSaveUncertain>()
      .having((e) => e.reconciled, 'reconciled', true)));
    await begin();
    inner.writes.single.completeError(TimeoutException('fixture'));
    await failure;
    expect((await cache.getMe()).displayName, 'Original');
  });

  test('uncertain outcome blocks another PATCH until authoritative GET succeeds', () async {
    inner.readFails = true;
    final first = cache.updateProfile(displayName: 'Unknown');
    final failure = expectLater(first, throwsA(isA<ProfileSaveUncertain>()));
    await begin();
    inner.writes.single.completeError(TimeoutException('fixture'));
    await failure;
    await expectLater(cache.updateProfile(displayName: 'Second'),
      throwsA(isA<ProfileSaveUncertain>()));
    expect(inner.writes, hasLength(1));
    inner.readFails = false;
    final next = cache.updateProfile(displayName: 'Second');
    await begin();
    inner.writes[1].complete(old.copyWith(displayName: 'Second'));
    await next;
    expect((await cache.getMe()).displayName, 'Second');
  });

  test('disposed identity never publishes a pending response', () async {
    final pending = cache.updateProfile(displayName: 'Late');
    final failure = expectLater(pending, throwsStateError);
    await begin();
    cache.dispose();
    inner.writes.single.complete(old.copyWith(displayName: 'Late'));
    await failure;
    // A fresh cache belongs to the replacement identity and has no late value.
    cache = CachedAssistantService(ProfileTransport(), initialProfile: old);
    expect((await cache.getMe()).displayName, 'Original');
  });

  test('an independent legacy background failure cannot reject a pending profile save', () async {
    cache.dispose();
    final operations = RecordingProfileService(old)
      ..saveGate = Completer<void>()
      ..upgradeError = const HomeMindApiException('Owned legacy rejection', statusCode: 503);
    cache = CachedAssistantService(operations, initialProfile: old);
    final background = Completer<String>();
    final subscription = cache.backgroundErrors.listen((message) {
      if (!background.isCompleted) background.complete(message);
    });
    addTearDown(subscription.cancel);
    final save = cache.updateProfile(displayName: 'Committed independently');
    await begin();
    await cache.requestUpgrade(plan: 'personal', source: 'owned-legacy-diagnostic');
    await background.future.timeout(const Duration(seconds: 2));
    expect((await cache.getMe()).displayName, 'Original');
    expect(operations.calls, hasLength(1));
    operations.saveGate!.complete();
    expect((await save).displayName, 'Committed independently');
    expect((await cache.getMe()).displayName, 'Committed independently');
    expect(operations.shouldFail, isFalse);
  });

  test('committed PATCH and billing refresh publish the same profile to auth and cache listeners', () async {
    FlutterSecureStorage.setMockInitialValues({});
    EnvConfig.backendBaseUrl = 'http://homemind.test/v1';
    final auth = _PublishedProfileAuth();
    var name = 'Original';
    var paid = false;
    var patchCount = 0;
    Map<String, Object?> profile() => {
      'userId': old.userId, 'workspaceId': old.workspaceId,
      'workspaceName': old.workspaceName, 'workspaceType': 'household',
      'role': 'owner', 'displayName': name, 'email': '',
      'voiceQuota': {
        'periodId': paid ? 'paid-period' : 'free-period',
        'plan': paid ? 'family' : 'free', 'used': 0,
        'total': paid ? 100 : 15, 'remaining': paid ? 100 : 15,
        'startsAt': '2026-10-05T00:00:00Z',
        'expiresAt': '2026-11-04T00:00:00Z',
        'serverNow': '2026-10-05T01:00:00Z',
      },
    };
    final transport = MockClient((request) async {
      if (request.method == 'PATCH' && request.url.path.endsWith('/me')) {
        patchCount++;
        name = (jsonDecode(request.body) as Map)['displayName'] as String;
        return http.Response(jsonEncode(profile()), 200);
      }
      if (request.url.path.endsWith('/me')) {
        return http.Response(jsonEncode(profile()), 200);
      }
      if (request.url.path.endsWith('/bootstrap')) {
        return http.Response(jsonEncode({'home': {'plan': paid ? 'family' : 'free'}}), 200);
      }
      return http.Response('{}', 404);
    });
    final backend = BackendAssistantService(authService: auth, profile: old, client: transport);
    cache.dispose();
    cache = CachedAssistantService(backend, initialProfile: old);
    final publishedNames = <String>[];
    cache.dataChanges.addListener(() {
      publishedNames.add(auth.published?.displayName ?? 'Original');
    });
    await cache.updateProfile(displayName: 'Committed via PATCH');
    expect(patchCount, 1);
    expect(auth.published?.displayName, 'Committed via PATCH');
    expect((await cache.getMe()).displayName, 'Committed via PATCH');
    paid = true;
    await cache.refreshBillingEntitlements();
    final committed = await cache.getMe();
    expect(committed.displayName, 'Committed via PATCH');
    expect(committed.voiceQuota?.total, 100);
    expect(auth.published?.voiceQuota?.periodId, committed.voiceQuota?.periodId);
    expect(publishedNames, everyElement('Committed via PATCH'));
    expect(patchCount, 1);
  });
}

class _PublishedProfileAuth extends MockAuthService implements SessionProfileService {
  _PublishedProfileAuth() : super(delay: Duration.zero,
    initialSession: AuthSession(token: 'test-access-token', profile: old, loginTime: DateTime(2026)));
  UserProfile? published;
  @override
  bool publishProfile(UserProfile profile) {
    if (profile.userId != old.userId) return false;
    published = profile;
    return true;
  }
}
