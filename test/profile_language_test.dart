import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

import 'support/recording_profile_service.dart';

const _profile = UserProfile(
  userId: 'u1',
  email: 'person@homemind.vn',
  displayName: 'Minh Anh',
  workspaceId: 'ws1',
  workspaceName: 'Tủ đồ Gia đình',
  workspaceType: 'household',
  role: 'owner',
  phone: '0912 345 678',
  address: 'Căn hộ 802, Q.7',
);

/// Fake service đọc file mock nên cần để IO chạy ngoài fake-async.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceSheet.enableInfiniteAnimation = false;
    AppText.setLanguage('vi', persist: false);
  });
  tearDown(() => AppText.setLanguage('vi', persist: false));

  Future<void> pumpProfile(
    WidgetTester tester,
    RecordingProfileService service, {
    ValueChanged<UserProfile>? onChanged,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: ProfilePage(
          service: service,
          user: _profile,
          onProfileChanged: onChanged,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> editField(
    WidgetTester tester,
    String rowKey,
    String value,
  ) async {
    await tester.tap(find.byKey(Key(rowKey)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_edit_field')), value);
    await tester.tap(find.byKey(const Key('profile_save_button')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'editing phone and address calls updateProfile and shows values',
    (tester) async {
      final service = RecordingProfileService(_profile);
      UserProfile? notified;
      await pumpProfile(tester, service, onChanged: (p) => notified = p);

      expect(find.text('0912 345 678'), findsOneWidget);

      await editField(tester, 'profile_row_phone', '0988 111 222');
      expect(service.calls.single['phone'], '0988 111 222');
      expect(find.byKey(const Key('profile_edit_field')), findsNothing);
      expect(find.text('0988 111 222'), findsOneWidget);
      expect(find.text('Đã lưu'), findsOneWidget);
      expect(notified?.phone, '0988 111 222');

      await editField(
        tester,
        'profile_row_address',
        '12 Nguyễn Huệ, Quận 1, TP.HCM',
      );
      expect(service.calls.last['address'], '12 Nguyễn Huệ, Quận 1, TP.HCM');
      expect(find.text('12 Nguyễn Huệ, Quận 1, TP.HCM'), findsOneWidget);
      expect(notified?.address, '12 Nguyễn Huệ, Quận 1, TP.HCM');
      expect(service.calls, hasLength(2));
    },
  );

  testWidgets('invalid phone shows an error and does not call the service', (
    tester,
  ) async {
    final service = RecordingProfileService(_profile);
    await pumpProfile(tester, service);

    await editField(tester, 'profile_row_phone', 'abc');

    expect(service.calls, isEmpty);
    expect(find.textContaining('Số điện thoại cần 8-20 ký tự'), findsOneWidget);
    expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
    expect(find.text('0912 345 678'), findsOneWidget);
  });

  for (final invalid in ['123+45678', '+${'1' * 20}']) {
    testWidgets('contact validation rejects internal plus or overlong canonical input', (tester) async {
      final service = RecordingProfileService(_profile);
      await pumpProfile(tester, service);
      await editField(tester, 'profile_row_phone', invalid);
      expect(service.calls, isEmpty);
      expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
      expect(find.text('0912 345 678'), findsOneWidget);
    });
  }

  testWidgets('save remains pending with committed card until acknowledgment', (tester) async {
    final gate = Completer<void>();
    final service = RecordingProfileService(_profile)..saveGate = gate;
    await pumpProfile(tester, service);
    await tester.tap(find.byKey(const Key('profile_row_phone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_edit_field')), '0988 111 222');
    await tester.tap(find.byKey(const Key('profile_save_button')));
    await tester.pump();
    expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
    expect(find.text('Đã lưu'), findsNothing);
    expect(find.text('0912 345 678'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_edit_field')), findsNothing);
    expect(find.text('0988 111 222'), findsOneWidget);
    expect(find.text('Đã lưu'), findsOneWidget);
  });

  testWidgets(
    'save failure shows a friendly message and keeps the sheet open',
    (tester) async {
      final service = RecordingProfileService(_profile)..shouldFail = true;
      await pumpProfile(tester, service);

      await editField(tester, 'profile_row_phone', '0988 111 222');

      expect(service.calls, hasLength(1));
      expect(
        find.text('Chưa lưu được. Bạn kiểm tra mạng rồi thử lại nhé.'),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
      expect(find.text('0912 345 678'), findsOneWidget);

      // Có thể thử lại sau khi mạng ổn.
      service.shouldFail = false;
      await tester.tap(find.byKey(const Key('profile_save_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_edit_field')), findsNothing);
      expect(find.text('0988 111 222'), findsOneWidget);
    },
  );

  testWidgets('discard after a rejected save preserves the committed card and sends no second save', (tester) async {
    final service = RecordingProfileService(_profile)..shouldFail = true;
    UserProfile? notified;
    await pumpProfile(tester, service, onChanged: (p) => notified = p);
    await editField(tester, 'profile_row_phone', '0988 111 222');
    expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
    expect(service.calls, hasLength(1));
    await tester.tap(find.byKey(const Key('profile_cancel_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_edit_field')), findsNothing);
    expect(find.text('0912 345 678'), findsOneWidget);
    expect(find.text('Đã lưu'), findsNothing);
    expect(service.calls, hasLength(1));
    expect(notified, isNull);
  });

  testWidgets('switching language updates nav and profile labels live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = RecordingProfileService(_profile);
    await tester.pumpWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: AppShell(
          assistantService: service,
          speechService: const UnavailableSpeechRecognitionService(),
          profile: _profile,
        ),
      ),
    );
    await settleIo(tester);

    expect(find.text('Trang chủ'), findsOneWidget);
    await tester.tap(find.text('Cá nhân'));
    await settleIo(tester);
    expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);

    // Sang tiếng Anh.
    await tester.tap(find.byKey(const Key('profile_row_language')));
    await tester.pumpAndSettle();
    expect(find.text('Trợ lý giọng nói vẫn nghe tiếng Việt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language_option_en')));
    await settleIo(tester);

    expect(service.calls.last['language'], 'en');
    expect(AppText.language.value, 'en');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Fridge & pantry'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Speak'), findsOneWidget);
    expect(find.text('Profile & Account'), findsOneWidget);
    expect(find.text('Contact phone number'), findsOneWidget);
    expect(find.text('Trang chủ'), findsNothing);

    // Quay lại tiếng Việt.
    await tester.tap(find.byKey(const Key('profile_row_language')));
    await tester.pumpAndSettle();
    expect(
      find.text('The voice assistant still listens in Vietnamese'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('language_option_vi')));
    await settleIo(tester);

    expect(service.calls.last['language'], 'vi');
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Tủ đồ'), findsOneWidget);
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('Cá nhân'), findsOneWidget);
    expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}
