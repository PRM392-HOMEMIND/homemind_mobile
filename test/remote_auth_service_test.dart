import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const mine = 'homemind.billing.pending.account-a.workspace-a';
  const sameUserOtherWorkspace =
      'homemind.billing.pending.account-a.workspace-b';
  const other = 'homemind.billing.pending.account-b.workspace-b';
  const intent =
      '{"priceId":"personal-month-v1","key":"11111111-1111-4111-8111-111111111111"}';
  setUp(() {
    EnvConfig.backendBaseUrl = 'https://fixture.invalid/v1';
    FlutterSecureStorage.setMockInitialValues({
      mine: intent,
      sameUserOtherWorkspace: intent,
      other: intent,
    });
  });
  RemoteAuthService service({
    bool failedProfile = false,
    bool failedRefresh = false,
  }) => RemoteAuthService(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/me')) {
        return http.Response(
          jsonEncode(
            failedProfile
                ? {
                    'error': {'message': 'Synthetic unavailable'},
                  }
                : {
                    'userId': 'account-a',
                    'workspaceId': 'workspace-a',
                    'email': 'fixture@example.invalid',
                    'displayName': 'Owned fixture',
                    'workspaceName': 'Owned',
                    'workspaceType': 'household',
                    'role': 'owner',
                  },
          ),
          failedProfile ? 503 : 200,
        );
      }
      if (request.url.path.endsWith('/refresh') && failedRefresh) {
        return http.Response('{"error":{"message":"Synthetic expired"}}', 401);
      }
      return http.Response(
        '{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresIn":900}',
        200,
      );
    }),
  );
  for (final all in [false, true]) {
    test(
      'logout${all ? ' all' : ''} clears only the verified current billing intent',
      () async {
        final auth = service();
        await auth.login(
          identifier: 'fixture@example.invalid',
          password: 'synthetic-fixture-only',
        );
        if (all) {
          await auth.logoutAll();
        } else {
          await auth.logout();
        }
        expect(await storage.read(key: mine), isNull);
        expect(await storage.read(key: sameUserOtherWorkspace), intent);
        expect(await storage.read(key: other), intent);
        expect(await storage.read(key: 'homemind.session.v2'), isNull);
      },
    );
  }
  test(
    'failed restored profile has no authority over any saved intent',
    () async {
      await storage.write(
        key: 'homemind.session.v2',
        value: jsonEncode({
          'accessToken': 'synthetic-access',
          'refreshToken': 'synthetic-refresh',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );
      expect(await service(failedProfile: true).getCurrentSession(), isNull);
      for (final key in [mine, sameUserOtherWorkspace, other]) {
        expect(await storage.read(key: key), intent);
      }
    },
  );
  test('failed restore refresh preserves all identities while clearing credentials', () async {
    await storage.write(
      key: 'homemind.session.v2',
      value: jsonEncode({
        'accessToken': 'synthetic-access',
        'refreshToken': 'synthetic-refresh',
        'expiresAt': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      }),
    );
    expect(await service(failedRefresh: true).getCurrentSession(), isNull);
    expect(await storage.read(key: other), intent);
    expect(await storage.read(key: mine), intent);
    expect(await storage.read(key: 'homemind.session.v2'), isNull);
  });
}
