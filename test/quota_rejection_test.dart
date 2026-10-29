import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/auth/domain/account_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_models.dart';

import 'support/mock_auth_service.dart';
import 'support/recording_profile_service.dart';

const _profile = UserProfile(
  userId: '11111111-1111-4111-8111-111111111111',
  email: '',
  displayName: 'Owned',
  workspaceId: '22222222-2222-4222-8222-222222222222',
  workspaceName: 'Owned',
  workspaceType: 'household',
  role: 'owner',
);
Map<String, Object?> _quota(int used) => {
  'periodId': 'owned-new-period',
  'plan': 'free',
  'used': used,
  'total': 15,
  'remaining': 15 - used,
  'startsAt': '2026-10-04T07:25:30Z',
  'expiresAt': '2026-11-03T07:25:30Z',
  'serverNow': '2026-10-05T07:25:30Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('authenticated exhausted response publishes server quota without a second POST', () async {
    EnvConfig.backendBaseUrl = 'http://homemind.test/v1';
    final auth = _PublishingAuth();
    var posts = 0;
    final service = BackendAssistantService(
      authService: auth,
      profile: _profile,
      client: MockClient((r) async {
        posts++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'VOICE_QUOTA_EXHAUSTED', 'details': _quota(15)},
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await expectLater(
      service.turn(text: 'Owned read'),
      throwsA(
        isA<HomeMindApiException>().having(
          (e) => e.code,
          'code',
          'VOICE_QUOTA_EXHAUSTED',
        ),
      ),
    );
    expect(posts, 1);
    expect(auth.published?.voiceQuota?.remaining, 0);
    expect(auth.published?.voiceQuota?.periodId, 'owned-new-period');
  });
  test('cache publishes exhaustion immediately to counter listeners, preserving rejection', () async {
    final inner = _RejectQuota(
      _profile.copyWith(voiceQuota: VoiceQuota.fromJson(_quota(14))),
    );
    final cache = CachedAssistantService(inner);
    addTearDown(cache.dispose);
    await cache.getMe();
    var changes = 0;
    cache.dataChanges.addListener(() => changes++);
    await expectLater(
      cache.turn(text: 'Owned last-slot race'),
      throwsA(same(inner.failure)),
    );
    expect((await cache.getMe()).voiceQuota?.remaining, 0);
    expect(changes, 1);
  });
  test('malformed quota and unrelated throttling cannot fabricate a usable counter', () {
    for (final value in [
      <String, Object?>{},
      {..._quota(15), 'remaining': 100},
      {..._quota(15), 'expiresAt': 'invalid'},
    ]) {
      expect(
        HomeMindApiException(
          'Owned',
          statusCode: 429,
          code: 'VOICE_QUOTA_EXHAUSTED',
          details: value,
        ).voiceQuota,
        isNull,
      );
    }
    expect(
      HomeMindApiException(
        'Owned',
        statusCode: 429,
        code: 'RATE_LIMIT',
        details: _quota(15),
      ).voiceQuota,
      isNull,
    );
  });
  test('disposed cache never publishes a late quota rejection', () async {
    final inner = _RejectQuota(
      _profile.copyWith(voiceQuota: VoiceQuota.fromJson(_quota(14))),
    );
    final cache = CachedAssistantService(inner);
    await cache.getMe();
    var changes = 0;
    cache.dataChanges.addListener(() => changes++);
    final pending = cache.turn(text: 'Owned');
    cache.dispose();
    await expectLater(pending, throwsA(same(inner.failure)));
    expect(changes, 0);
  });
}

class _PublishingAuth extends MockAuthService implements SessionProfileService {
  _PublishingAuth()
    : super(
        delay: Duration.zero,
        initialOnboardingCompleted: true,
        initialSession: AuthSession(
          token: 'test-access-token',
          profile: _profile,
          loginTime: DateTime(2026),
        ),
      );
  UserProfile? published;
  @override
  bool publishProfile(UserProfile profile) {
    published = profile;
    return true;
  }
}

class _RejectQuota extends RecordingProfileService {
  _RejectQuota(super.profile);
  final failure = HomeMindApiException(
    'Owned rejection',
    statusCode: 429,
    code: 'VOICE_QUOTA_EXHAUSTED',
    details: _quota(15),
  );
  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async => throw failure;
}
