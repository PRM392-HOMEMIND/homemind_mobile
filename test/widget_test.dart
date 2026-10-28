import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';

import 'support/fake_assistant_service.dart';

import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

/// Fake service đọc file thật nên cần để IO chạy ngoài fake-async.
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

  setUp(() => VoiceSheet.enableInfiniteAnimation = false);

  testWidgets('HomeMind shell shows backend-shaped home data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          assistantService: FakeAssistantService(delay: Duration.zero),
          speechService: const UnavailableSpeechRecognitionService(),
        ),
      ),
    );
    await settleIo(tester);

    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Cá nhân'), findsOneWidget);
    expect(find.text('Tủ đồ'), findsOneWidget);
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('Nói'), findsOneWidget);
    expect(find.text('Danh sách cần mua'), findsOneWidget);
  });
}
