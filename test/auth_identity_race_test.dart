import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/email_otp_models.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object> tokens(String id) => {
  'accessToken': 'synthetic-access-$id',
  'refreshToken': 'synthetic-refresh-$id',
  'expiresIn': 900,
};

class DelayedStorage extends FlutterSecureStorage {
  DelayedStorage(this.saved);
  final Completer<String?> saved;
  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => key == 'homemind.session.v2' ? saved.future : super.read(key: key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    EnvConfig.backendBaseUrl = 'https://fixture.invalid/v1';
  });
  RemoteAuthService service({
    Completer<http.Response>? verify,
    Completer<http.Response>? logout,
    Completer<http.Response>? oldProfile,
    Completer<http.Response>? password,
    List<String>? passwordActors,
    FlutterSecureStorage? storage,
  }) => RemoteAuthService(
    storage: storage,
    client: MockClient((r) async {
      if (r.url.path.endsWith('/email/verify')) return verify!.future;
      if (r.url.path.endsWith('/password/change')) {
        passwordActors!.add(r.headers['Authorization'] ?? '');
        if (passwordActors.length == 1) return password!.future;
        return reply({'ok': true, 'reauthenticationRequired': true});
      }
      if (r.url.path.endsWith('/logout') && logout != null) {
        return logout.future;
      }
      if (r.url.path.endsWith('/me')) {
        final id = r.headers['Authorization']?.endsWith('-old') == true
            ? 'old'
            : 'new';
        if (id == 'old' && oldProfile != null) return oldProfile.future;
        return reply({
          'userId': id,
          'workspaceId': 'workspace-$id',
          'email': '$id@example.invalid',
          'displayName': id,
          'workspaceName': id,
          'workspaceType': 'household',
          'role': 'owner',
        });
      }
      if (r.url.path.endsWith('/login')) {
        return reply(
          tokens(
            (jsonDecode(r.body)['identifier'] as String).startsWith('old')
                ? 'old'
                : 'new',
          ),
        );
      }
      return reply({'ok': true});
    }),
  );
  final challenge = EmailChallenge.fromJson({
    'challengeId': '11111111-1111-4111-8111-111111111111',
    'challengeToken': 'synthetic-only',
    'purpose': 'REGISTER',
    'state': 'ready',
    'maskedEmail': 'x@example.invalid',
    'serverTime': '2026-10-15T00:00:00Z',
    'resendAvailableAt': '2026-10-15T00:01:00Z',
  });
  test(
    'public OTP completion after logout/login cannot replace the new identity',
    () async {
      final response = Completer<http.Response>(),
          auth = service(verify: response);
      final operation = auth.verifyChallenge(challenge, '000042');
      final assertion = expectLater(operation, throwsA(isA<AuthException>()));
      await auth.logout();
      await auth.login(
        identifier: 'new@example.invalid',
        password: 'synthetic-fixture-only',
      );
      response.complete(reply(tokens('old')));
      await assertion;
      expect((await auth.getCurrentSession())?.profile.userId, 'new');
    },
  );
  test('late logout response cannot clear a newer login', () async {
    final response = Completer<http.Response>(),
        auth = service(logout: response);
    await auth.login(
      identifier: 'old@example.invalid',
      password: 'synthetic-fixture-only',
    );
    final operation = auth.logout();
    await Future<void>.delayed(Duration.zero);
    await auth.login(
      identifier: 'new@example.invalid',
      password: 'synthetic-fixture-only',
    );
    response.complete(reply({'ok': true}));
    await operation;
    expect((await auth.getCurrentSession())?.profile.userId, 'new');
  });
  test('old profile error cannot clear the newer accepted session', () async {
    final response = Completer<http.Response>(),
        auth = service(oldProfile: response);
    final operation = auth.login(
      identifier: 'old@example.invalid',
      password: 'synthetic-fixture-only',
    );
    final assertion = expectLater(operation, throwsA(isA<AuthException>()));
    await Future<void>.delayed(Duration.zero);
    await auth.login(
      identifier: 'new@example.invalid',
      password: 'synthetic-fixture-only',
    );
    response.complete(
      reply({
        'error': {'message': 'Synthetic unavailable'},
      }, 503),
    );
    await assertion;
    expect((await auth.getCurrentSession())?.profile.userId, 'new');
  });
  test(
    'delayed secure-storage restore cannot overwrite a new explicit login',
    () async {
      final saved = Completer<String?>(),
          auth = service(storage: DelayedStorage(saved));
      final restoring = auth.getCurrentSession();
      await auth.login(
        identifier: 'new@example.invalid',
        password: 'synthetic-fixture-only',
      );
      saved.complete(
        jsonEncode({
          ...tokens('old'),
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );
      await restoring;
      expect((await auth.getCurrentSession())?.profile.userId, 'new');
    },
  );
  test(
    'stale 401 cannot replay a sensitive operation with the new identity token',
    () async {
      final pending = Completer<http.Response>(), actors = <String>[];
      final auth = service(password: pending, passwordActors: actors);
      await auth.login(
        identifier: 'old@example.invalid',
        password: 'synthetic-fixture-only',
      );
      final operation = auth.changePassword(
        'synthetic-fixture-only',
        'synthetic-next-password',
      );
      final assertion = expectLater(operation, throwsA(isA<AuthException>()));
      await Future<void>.delayed(Duration.zero);
      await auth.logout();
      await auth.login(
        identifier: 'new@example.invalid',
        password: 'synthetic-fixture-only',
      );
      pending.complete(
        reply({
          'error': {'code': 'SESSION_INVALID', 'message': 'Synthetic expired'},
        }, 401),
      );
      await assertion;
      expect(actors, ['Bearer synthetic-access-old']);
      expect((await auth.getCurrentSession())?.profile.userId, 'new');
    },
  );
}
