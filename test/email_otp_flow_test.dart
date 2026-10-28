import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/email_otp_models.dart';
import 'package:homemind_mobile/features/auth/presentation/email_otp_page.dart';
import 'package:homemind_mobile/features/auth/presentation/forgot_password_page.dart';

Map<String, Object?> challengeJson({String purpose = 'REGISTER'}) => {
  'challengeId': '11111111-1111-4111-8111-111111111111',
  'challengeToken': 'synthetic-capability',
  'purpose': purpose,
  'maskedEmail': 'o•••@example.invalid',
  'state': 'ready',
  'serverTime': '2026-10-14T00:00:00Z',
  'expiresAt': '2026-10-14T00:01:00Z',
  'resendAvailableAt': '2026-10-14T00:01:00Z',
};

class OtpFake implements EmailOtpAuthService {
  int sends = 0, verifies = 0, statusReads = 0;
  String? code;
  EmailChallenge challenge = EmailChallenge.fromJson(challengeJson());
  @override
  Future<EmailChallenge> challengeStatus(EmailChallenge c) async {
    statusReads++;
    return challenge;
  }

  @override
  Future<EmailChallenge> resendChallenge(EmailChallenge c) async {
    sends++;
    return challenge;
  }

  @override
  Future<EmailVerification> verifyChallenge(
    EmailChallenge c,
    String value,
  ) async {
    verifies++;
    code = value;
    return const EmailVerification();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    EnvConfig.backendBaseUrl = 'http://127.0.0.1:3000/v1';
  });
  testWidgets(
    'six-digit paste retains leading zero, blocks double-submit, no automatic resend on countdown/remount',
    (tester) async {
      final auth = OtpFake();
      await tester.pumpWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: EmailOtpPage(auth: auth, challenge: auth.challenge),
        ),
      );
      await tester.pump();
      ElevatedButton button() =>
          tester.widget(find.byKey(const ValueKey('otp_verify')));
      expect(button().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('otp_code')), '000042');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('otp_code')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      auth.challenge = EmailChallenge.fromJson({
        ...challengeJson(),
        'state': 'expired',
        'serverTime': '2026-10-14T00:01:01Z',
      });
      await tester.pump(const Duration(seconds: 61));
      await tester.ensureVisible(find.text('Kiểm tra trạng thái gửi'));
      await tester.tap(find.text('Kiểm tra trạng thái gửi'));
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(auth.sends, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: EmailOtpPage(auth: auth, challenge: auth.challenge),
        ),
      );
      await tester.pump();
      expect(auth.sends, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'small screen, keyboard and 2x text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = OtpFake();
      await tester.pumpWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 250),
            ),
            child: child!,
          ),
          home: EmailOtpPage(auth: auth, challenge: auth.challenge),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('otp_resend')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('remote register returns pending proof and stores no session before verification; verify accepts only server session', () async {
    final routes = <String>[];
    final auth = RemoteAuthService(
      client: MockClient((request) async {
        routes.add(request.url.path);
        final path = request.url.path;
        if (path.endsWith('/register')) {
          return http.Response(
            jsonEncode(challengeJson()),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path.endsWith('/email/verify')) {
          final body = jsonDecode(request.body);
          expect(body['code'], '000042');
          return http.Response(
            jsonEncode({
              'accessToken': 'owned-access',
              'refreshToken': 'owned-refresh',
              'expiresIn': 900,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'userId': 'owned',
            'workspaceId': 'owned-ws',
            'email': 'owned@example.invalid',
            'displayName': 'Owned',
            'role': 'owner',
          }),
          200,
        );
      }),
    );
    final pending = await auth.register(
      acceptedTerms: true,
      acceptedPrivacy: true,
      displayName: 'Owned',
      email: 'owned@example.invalid',
      password: 'owned-test-password',
      workspaceType: 'household',
    );
    expect(await auth.getCurrentSession(), isNull);
    expect(routes, hasLength(1));
    final verified = await auth.verifyChallenge(pending, '000042');
    expect(verified.session, isNotNull);
    expect(await auth.getCurrentSession(), isNotNull);
  });
  testWidgets(
    'forgot password cannot open new-password fields until OTP yields one-use proof',
    (tester) async {
      final auth = RemoteAuthService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/password/forgot')) {
            return http.Response(
              jsonEncode(challengeJson(purpose: 'RESET')),
              202,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path.endsWith('/email/status')) {
            return http.Response(
              jsonEncode(challengeJson(purpose: 'RESET')),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path.endsWith('/email/verify')) {
            return http.Response(
              jsonEncode({
                'ticket': 'synthetic-ticket',
                'ticketExpiresAt': DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/reset-ticket')) {
            return http.Response(
              jsonEncode({'ok': true, 'reauthenticationRequired': true}),
              200,
            );
          }
          throw StateError('Unexpected API');
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordPage(auth: auth)),
      );
      expect(find.byKey(const ValueKey('reset_password')), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('forgot_identifier')),
          matching: find.byType(TextFormField),
        ),
        'owned@example.invalid',
      );
      await tester.tap(find.byKey(const ValueKey('forgot_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('otp_code')), findsOneWidget);
      expect(find.byKey(const ValueKey('reset_password')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('otp_code')), '000042');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('otp_verify')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reset_password')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
