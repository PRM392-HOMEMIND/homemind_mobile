import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final newerLogin in [true, false]) {
    test(
      newerLogin
          ? 'late retry 401 preserves the newer identity'
          : 'current retry 401 still invalidates its rejected session',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        EnvConfig.backendBaseUrl = 'https://fixture.invalid/v1';
        final retried = Completer<void>();
        final response = Completer<http.Response>();
        final actors = <String>[];
        http.Response reply(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        Map<String, Object> tokens(String id) => {
          'accessToken': 'synthetic-access-$id',
          'refreshToken': 'synthetic-refresh-$id',
          'expiresIn': 900,
        };
        final auth = RemoteAuthService(
          client: MockClient((r) async {
            if (r.url.path.endsWith('/login')) {
              final id = (jsonDecode(r.body)['identifier'] as String)
                  .split('@')
                  .first;
              return reply(tokens(id));
            }
            if (r.url.path.endsWith('/refresh')) {
              return reply(tokens('rotated'));
            }
            if (r.url.path.endsWith('/me')) {
              final id = r.headers['Authorization']!.split('-').last;
              return reply({
                'userId': id,
                'workspaceId': 'ws-$id',
                'email': '$id@example.invalid',
                'displayName': id,
                'workspaceName': id,
                'workspaceType': 'household',
                'role': 'owner',
              });
            }
            if (r.url.path.endsWith('/password/change')) {
              actors.add(r.headers['Authorization']!);
              if (actors.length == 1) {
                return reply({
                  'error': {'code': 'SESSION_INVALID'},
                }, 401);
              }
              retried.complete();
              return response.future;
            }
            return reply({'ok': true});
          }),
        );
        await auth.login(
          identifier: 'old@example.invalid',
          password: 'synthetic-only',
        );
        final operation = auth.changePassword(
          'synthetic-only',
          'synthetic-next',
        );
        final assertion = expectLater(operation, throwsA(isA<AuthException>()));
        await retried.future;
        if (newerLogin) {
          await auth.login(
            identifier: 'new@example.invalid',
            password: 'synthetic-only',
          );
        }
        response.complete(
          reply({
            'error': {'code': 'SESSION_INVALID'},
          }, 401),
        );
        await assertion;
        expect(actors, [
          'Bearer synthetic-access-old',
          'Bearer synthetic-access-rotated',
        ]);
        expect(
          (await auth.getCurrentSession())?.profile.userId,
          newerLogin ? 'new' : null,
        );
        final saved = await const FlutterSecureStorage().read(
          key: 'homemind.session.v2',
        );
        if (newerLogin) {
          expect(jsonDecode(saved!)['accessToken'], 'synthetic-access-new');
        } else {
          expect(saved, isNull);
        }
      },
    );
  }
}
