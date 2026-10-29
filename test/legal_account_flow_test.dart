import 'dart:convert';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/auth/data/remote_auth_service.dart';
import 'package:homemind_mobile/features/auth/presentation/register_page.dart';
import 'package:homemind_mobile/features/auth/presentation/account_settings_page.dart';
import 'package:homemind_mobile/features/auth/presentation/legal_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppText.setLanguage('vi', persist: false);
    EnvConfig.backendBaseUrl = 'https://owned.invalid/v1';
  });
  final requests = <http.Request>[];
  RemoteAuthService client({bool failRegistration = false}) {
    requests.clear();
    return RemoteAuthService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/me')) {
          return http.Response(
            jsonEncode({
              'userId': 'owned',
              'workspaceId': 'owned-ws',
              'email': 'owned@example.invalid',
              'displayName': 'Owned',
              'workspaceName': 'Owned',
              'workspaceType': 'household',
              'role': 'owner',
            }),
            200,
          );
        }
        if (failRegistration && request.url.path.endsWith('/register')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'Vui lòng đồng ý Điều khoản sử dụng và Chính sách bảo mật.',
              },
            }),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/register') ||
            request.url.path.endsWith('/email/status')) {
          return http.Response(
            jsonEncode({
              'challengeId': 'owned-challenge',
              'challengeToken': 'synthetic-proof',
              'purpose': 'REGISTER',
              'maskedEmail': 'o???@example.invalid',
              'state': 'ready',
              'serverTime': '2026-10-14T00:00:00Z',
              'expiresAt': '2026-10-14T00:01:00Z',
              'resendAvailableAt': '2026-10-14T00:01:00Z',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'accessToken': 'owned-access',
            'refreshToken': 'owned-refresh',
            'expiresIn': 3600,
          }),
          200,
        );
      }),
    );
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    for (final entry in {
      'register_name': 'Owned test',
      'register_email': 'owned@example.invalid',
      'register_password': 'owned-test-password',
      'register_confirm': 'owned-test-password',
    }.entries) {
      final field = find.descendant(
        of: find.byKey(ValueKey(entry.key)),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('register_legal_acceptance')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    RemoteAuthService auth, {
    double scale = 1,
    Future<bool> Function(Uri)? launch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegisterPage(
                    auth: auth,
                    onSuccess: (_) {},
                    openLegalUrl: launch,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unchecked and disabled; exact independent links never toggle or register; acceptance plus valid fields required',
    (tester) async {
      final auth = client(), urls = <Uri>[];
      await mount(
        tester,
        auth,
        launch: (uri) async {
          urls.add(uri);
          return true;
        },
      );
      ElevatedButton button() =>
          tester.widget(find.byKey(const Key('register_submit')));
      Checkbox box() =>
          tester.widget(find.byKey(const Key('register_legal_acceptance')));
      expect(box().value, false);
      expect(button().onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      expect(button().onPressed, isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      for (final key in ['register_terms_link', 'register_privacy_link']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tapVisible(tester, find.byKey(Key(key)));
        await tester.pump();
        expect(box().value, false);
      }
      expect(urls, [LegalConsent.terms, LegalConsent.privacy]);
      expect(requests, isEmpty);
      await fill(tester);
      expect(button().onPressed, isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      expect(button().onPressed, isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('register_submit')));
      await tapVisible(tester, find.byKey(const Key('register_submit')));
      await tester.pumpAndSettle();
      final created = requests
          .where((r) => r.url.path.endsWith('/register'))
          .single;
      final body = jsonDecode(created.body) as Map;
      expect(body['acceptedTerms'], true);
      expect(body['acceptedPrivacy'], true);
      expect(body, isNot(contains('termsAcceptedAt')));
      expect(await auth.getCurrentSession(), isNull);
      expect(find.byKey(const ValueKey('otp_code')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('otp_code')), '000042');
      await tapVisible(tester, find.byKey(const ValueKey('otp_verify')));
      expect(await auth.getCurrentSession(), isNotNull);
    },
  );
  testWidgets(
    'server refusal and failed link are shown honestly; no success session',
    (tester) async {
      final auth = client(failRegistration: true);
      await mount(tester, auth, launch: (_) async => false);
      await tester.ensureVisible(
        find.byKey(const Key('register_privacy_link')),
      );
      await tapVisible(tester, find.byKey(const Key('register_privacy_link')));
      await tester.pump();
      expect(
        find.text('Không thể mở trang pháp lý. Vui lòng thử lại.'),
        findsOneWidget,
      );
      await fill(tester);
      await tapVisible(
        tester,
        find.byKey(const Key('register_legal_acceptance')),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('register_submit')));
      await tapVisible(tester, find.byKey(const Key('register_submit')));
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r.url.path.endsWith('/register')),
        hasLength(1),
      );
      expect(
        find.text('Vui lòng đồng ý Điều khoản sử dụng và Chính sách bảo mật.'),
        findsOneWidget,
      );
      expect(await auth.getCurrentSession(), isNull);
    },
  );
  for (final scale in [1.0, 1.5, 2.0]) {
    for (final keyboard in [0.0, 280.0]) {
      testWidgets(
        '320dp text $scale keyboard $keyboard remains accessible and scrollable',
        (tester) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(() => tester.view.reset());
          final auth = client();
          await mount(tester, auth, scale: scale);
          final semantics = tester.ensureSemantics();
          try {
            await tester.ensureVisible(
              find.byKey(const Key('register_legal_acceptance')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester
                  .getSemantics(
                    find.byKey(const Key('register_legal_acceptance')),
                  )
                  .getSemanticsData()
                  .flagsCollection
                  .isChecked,
              CheckedState.isFalse,
            );
            expect(
              tester
                  .getSemantics(find.byKey(const Key('register_submit')))
                  .getSemanticsData()
                  .flagsCollection
                  .isEnabled,
              Tristate.isFalse,
            );
            await tester.ensureVisible(
              find.byKey(const Key('register_privacy_link')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester
                  .getRect(find.byKey(const Key('register_privacy_link')))
                  .bottom,
              lessThanOrEqualTo(720 - keyboard),
            );
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
  testWidgets(
    'delete cancel does nothing; confirm calls DELETE once, clears session and returns to root',
    (tester) async {
      final auth = client();
      await auth.login(
        identifier: 'owned@example.invalid',
        password: 'owned-test-password',
      );
      requests.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSettingsPage(
            auth: auth,
            profile: (await auth.getCurrentSession())!.profile,
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('account_delete')));
      await tester.tap(find.byKey(const Key('account_delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('close_password')),
          matching: find.byType(TextFormField),
        ),
        'owned-test-password',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('close_submit')));
      await tester.tap(find.byKey(const Key('close_submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('mọi phiên sẽ bị thu hồi'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(await auth.getCurrentSession(), isNotNull);
      await tester.tap(find.byKey(const Key('close_submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) => r.method == 'DELETE' && r.url.path.endsWith('/auth/account'),
        ),
        hasLength(1),
      );
      expect(await auth.getCurrentSession(), isNull);
      expect(find.byKey(const Key('close_submit')), findsNothing);
    },
  );
}
