import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_assistant_service.dart';
import 'support/mock_auth_service.dart';

import 'package:homemind_mobile/features/auth/domain/auth_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/auth/presentation/login_page.dart';
import 'package:homemind_mobile/features/auth/presentation/onboarding_page.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';
import 'package:homemind_mobile/main.dart';

// Load the file-backed profile before entering the widget test's fake clock.
// The logout scenario still exercises the normal cached profile and auth path.
class _LoadedProfileService extends FakeAssistantService {
  _LoadedProfileService(this.profile) : super(delay: Duration.zero);
  final UserProfile profile;

  @override
  Future<UserProfile> getMe() => SynchronousFuture(profile);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceSheet.enableInfiniteAnimation = false;
  });

  Widget buildTestApp({
    required MockAuthService authService,
    AuthSession? initialSession,
    bool? initialOnboardingCompleted,
    FakeAssistantService? assistantService,
  }) {
    return HomeMindApp(
      authService: authService,
      initialSession: initialSession,
      initialOnboardingCompleted: initialOnboardingCompleted,
      assistantService:
          assistantService ?? FakeAssistantService(delay: Duration.zero),
      speechService: const UnavailableSpeechRecognitionService(),
    );
  }

  group('Auth & Onboarding Flow Tests', () {
    test('Demo accounts use the expected easy login credentials', () {
      expect(MockAccount.sampleAccounts.first.email, 'person@homemind.vn');
      expect(
        MockAccount.sampleAccounts.first.password,
        'mock-fixture-password',
      );
      expect(MockAccount.sampleAccounts.last.email, 'store@homemind.vn');
      expect(MockAccount.sampleAccounts.last.password, 'mock-fixture-password');
    });

    testWidgets('App opens OnboardingPage when first installed', (
      tester,
    ) async {
      final authService = MockAuthService(
        initialOnboardingCompleted: false,
        delay: Duration.zero,
      );

      await tester.pumpWidget(buildTestApp(authService: authService));
      await tester.pumpAndSettle();

      // Should show Onboarding
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Nói để thêm đồ'), findsOneWidget);
      expect(find.text('Bỏ qua'), findsOneWidget);
      expect(find.text('Tiếp theo'), findsOneWidget);

      // Tapping "Bỏ qua" navigates to LoginPage
      await tester.tap(find.text('Bỏ qua'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Chào mừng bạn đến với HomeMind'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('LoginPage logs in as Consumer with email and password', (
      tester,
    ) async {
      final authService = MockAuthService(
        initialOnboardingCompleted: true,
        delay: Duration.zero,
      );

      await tester.pumpWidget(
        buildTestApp(
          authService: authService,
          initialOnboardingCompleted: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        MockAccount.sampleAccounts.first.email,
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        MockAccount.sampleAccounts.first.password,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Đăng nhập'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Cá nhân'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('LoginPage logs in as Merchant and opens grocery store view', (
      tester,
    ) async {
      final authService = MockAuthService(
        initialOnboardingCompleted: true,
        delay: Duration.zero,
      );

      await tester.pumpWidget(
        buildTestApp(
          authService: authService,
          initialOnboardingCompleted: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));

      final merchant = MockAccount.sampleAccounts.last;
      await tester.enterText(find.byType(TextFormField).at(0), merchant.email);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        merchant.password,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Đăng nhập'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      await tester.pumpAndSettle();
      expect(find.text('Kho hàng'), findsOneWidget);
      expect(find.text('Cần nhập'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Logout confirms and navigates back to LoginPage', (
      tester,
    ) async {
      final profile = await tester.runAsync(
        FakeAssistantService(delay: Duration.zero).getMe,
      );
      expect(profile, isNotNull);
      final authService = MockAuthService(
        initialOnboardingCompleted: true,
        delay: Duration.zero,
      );

      await tester.pumpWidget(
        buildTestApp(
          authService: authService,
          initialOnboardingCompleted: true,
          assistantService: _LoadedProfileService(profile!),
        ),
      );
      await tester.pumpAndSettle();

      final consumer = MockAccount.sampleAccounts.first;
      await tester.enterText(find.byType(TextFormField).at(0), consumer.email);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        consumer.password,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Đăng nhập'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Navigate to Settings/Profile tab
      await tester.tap(find.text('Cá nhân'));
      await tester.pumpAndSettle();

      // Find "Đăng xuất" button by scrolling
      final logoutBtn = find.byKey(const Key('profile_logout'));
      await tester.scrollUntilVisible(
        logoutBtn,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(logoutBtn);
      await tester.pump();
      expect(logoutBtn, findsOneWidget);

      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Đăng xuất tài khoản'), findsOneWidget);
      expect(
        find.text(
          'Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng HomeMind không?',
        ),
        findsOneWidget,
      );

      // Confirm logout
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Đăng xuất');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Should now be back on LoginPage
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Chào mừng bạn đến với HomeMind'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
