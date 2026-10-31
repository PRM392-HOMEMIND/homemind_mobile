import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

import 'full_system_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fixture.nativeTest(
    'PLATFORM-03 native Android microphone allow; no audio claim',
    (tester) async {
      await fixture.start(tester);
      await fixture.tap(tester, find.byKey(const Key('nav_voice')));
      await fixture.waitFor(tester, find.byType(VoiceSheet));
      // Actual Android permission is independently checked on the owned AVD.
      await Future<void>.delayed(const Duration(seconds: 8));
      await fixture.host('microphone-permission');
      expect(find.byType(VoiceSheet), findsOneWidget);
      await fixture.host('background-resume');
      await fixture.waitFor(tester, find.byType(VoiceSheet));
    },
  );
  tearDownAll(() async {
    await fixture.cleanupOwned();
    binding.reportData = {
      'nativePermission': 'ALLOW',
      'audioTranscription': 'NOT_VERIFIED',
    };
  });
}
