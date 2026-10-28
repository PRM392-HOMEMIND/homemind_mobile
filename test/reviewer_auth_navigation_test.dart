import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_service.dart';
import 'package:homemind_mobile/features/auth/presentation/login_page.dart';
import 'package:homemind_mobile/features/auth/presentation/forgot_password_page.dart';
import 'package:homemind_mobile/features/auth/presentation/account_settings_page.dart';
import 'package:homemind_mobile/features/auth/presentation/email_otp_page.dart';

http.Response jsonResponse(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    EnvConfig.backendBaseUrl = 'https://fixture.invalid/v1';
  });
  Map<String, Object?> challenge() => {
    'challengeId': '11111111-1111-4111-8111-111111111111',
    'challengeToken': 'synthetic-capability',
    'purpose': 'CHANGE_PASSWORD',
    'state': 'ready',
    'maskedEmail': 'n•••@example.invalid',
    'serverTime': DateTime.now().toUtc().toIso8601String(),
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
    'resendAvailableAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
  };
  Finder field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );
  void noOtp() {
    expect(find.byType(EmailOtpPage), findsNothing);
    expect(find.byKey(const ValueKey('otp_code')), findsNothing);
    expect(find.textContaining('bypass'), findsNothing);
    expect(find.textContaining('test mode'), findsNothing);
  }

  RemoteAuthService service({
    required List<String> calls,
    bool wrong = false,
    bool normal = false,
    Completer<http.Response>? pending,
  }) => RemoteAuthService(
    client: MockClient((r) async {
      calls.add(r.url.path);
      if (r.url.path.endsWith('/me')) {
        return jsonResponse(
          jsonEncode({
            'userId': 'account-a',
            'workspaceId': 'workspace-a',
            'email': 'fixture@example.invalid',
            'displayName': 'Fixture',
            'workspaceName': 'Nhà',
            'workspaceType': 'household',
            'role': 'owner',
          }),
          200,
        );
      }
      if (r.url.path.endsWith('/password/forgot') ||
          r.url.path.endsWith('/email/change')) {
        return jsonResponse(
          jsonEncode({
            'error': {
              'code': 'ACCOUNT_OPERATION_UNAVAILABLE',
              'message':
                  'Không thể thực hiện thao tác này. Vui lòng liên hệ hỗ trợ.',
            },
          }),
          403,
        );
      }
      if (r.url.path.endsWith('/password/change')) {
        expect(
          r.headers['X-HomeMind-Auth-Contract'] ??
              r.headers['x-homemind-auth-contract'],
          '2',
        );
        if (pending != null) return pending.future;
        return jsonResponse(
          jsonEncode(
            normal
                ? challenge()
                : {'ok': true, 'reauthenticationRequired': true},
          ),
          200,
        );
      }
      if (r.url.path.endsWith('/email/status')) {
        return jsonResponse(jsonEncode(challenge()), 200);
      }
      if (wrong) {
        return jsonResponse('{"error":{"message":"Mật khẩu chưa đúng."}}', 401);
      }
      return jsonResponse(
        '{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresIn":900}',
        200,
      );
    }),
  );
  for (final wrong in [false, true]) {
    testWidgets(
      'password login ${wrong ? 'rejected' : 'completed'} never mounts OTP without server challenge',
      (tester) async {
        final calls = <String>[];
        var logins = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(
              authService: service(calls: calls, wrong: wrong),
              onLoginSuccess: (_) => logins++,
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('login_identifier')),
          'homemind.test@gmail.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey('login_password')),
          'synthetic-fixture-only',
        );
        await tester.tap(find.byKey(const ValueKey('login_submit')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          noOtp();
        }
        expect(logins, wrong ? 0 : 1);
        expect(calls.any((p) => p.contains('/email/')), isFalse);
      },
    );
  }
  testWidgets(
    'server-denied email-only recovery stays on form, no sent toast or reset success',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordPage(auth: service(calls: calls)),
        ),
      );
      await tester.enterText(
        field('forgot_identifier'),
        'homemind.test@gmail.com',
      );
      await tester.tap(find.byKey(const ValueKey('forgot_submit')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        noOtp();
      }
      expect(
        find.textContaining('Vui lòng liên hệ hỗ trợ'),
        findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join('|'),
      );
      expect(find.byKey(const ValueKey('reset_password')), findsNothing);
      expect(
        find.textContaining('hướng dẫn đặt lại mật khẩu sẽ được gửi'),
        findsNothing,
      );
    },
  );
  for (final normal in [false, true]) {
    testWidgets(
      'server chooses ${normal ? 'normal OTP' : 'direct completion'} for password change, no email comparison',
      (tester) async {
        final calls = <String>[], auth = service(calls: calls, normal: normal);
        final session = await auth.login(
          identifier: 'ordinary@example.invalid',
          password: 'synthetic-fixture-only',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountSettingsPage(
                        auth: auth,
                        profile: session.profile,
                      ),
                    ),
                  ),
                  child: const Text('Open account'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open account'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('account_password')));
        await tester.pumpAndSettle();
        await tester.enterText(
          field('account_current_password'),
          'synthetic-fixture-only',
        );
        await tester.enterText(
          field('account_new_password'),
          'synthetic-new-password',
        );
        await tester.enterText(
          field('account_confirm_password'),
          'synthetic-new-password',
        );
        await tester.ensureVisible(find.byKey(const ValueKey('account_save')));
        await tester.tap(find.byKey(const ValueKey('account_save')));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (!normal) noOtp();
        }
        expect(
          calls.where((p) => p.endsWith('/password/change')),
          hasLength(1),
        );
        if (normal) {
          expect(
            find.byType(EmailOtpPage),
            findsOneWidget,
            reason: find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data)
                .join('|'),
          );
          await tester.tap(find.byTooltip('Quay lại').hitTestable());
          await tester.pumpAndSettle();
        } else {
          expect(find.text('Open account'), findsOneWidget);
          expect(await auth.getCurrentSession(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  test('late authenticated completion cannot clear a different session after logout/login', () async {
    final calls = <String>[],
        pending = Completer<http.Response>(),
        auth = service(calls: calls, pending: pending);
    await auth.login(
      identifier: 'first@example.invalid',
      password: 'synthetic-fixture-only',
    );
    final operation = auth.changePassword(
      'synthetic-fixture-only',
      'synthetic-new-password',
    );
    final assertion = expectLater(operation, throwsA(isA<AuthException>()));
    await Future<void>.delayed(Duration.zero);
    await auth.logout();
    await auth.login(
      identifier: 'second@example.invalid',
      password: 'synthetic-fixture-only',
    );
    pending.complete(
      jsonResponse('{"ok":true,"reauthenticationRequired":true}', 200),
    );
    await assertion;
    expect(await auth.getCurrentSession(), isNotNull);
  });
}
