import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'full_system_test.dart' as fixture;

// A separate trusted gate, using real provider transport through Nest only.
// One dependent scenario, three calls maximum. Failure stops paid calls.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fixture.nativeTest('AI-03.PREREQUISITE ownership control and normal auth', (
    tester,
  ) async {
    await fixture.start(tester);
    await fixture.cleanupOwned();
    binding.reportData = {'realGeminiCallsAttempted': 0};
  });
  fixture.nativeTest(
    'AI-03 real Gemini native read, cancel and exactly-once confirm',
    (tester) async {
      final actor = await fixture.start(tester);
      final seed = await fixture.request(
        '/workspaces/${actor['ws']}/inventory',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      final initial = (seed['items'] as List).single as Map;
      final productId = initial['productId'];
      expect(initial['name'], 'Sữa native E2E');
      expect(initial['quantity'], 2);
      int calls = 0;
      num? cancelQuantity, confirmedQuantity;
      Future<void> say(String text) async {
        expect(calls, lessThan(3));
        calls++;
        await fixture.say(tester, text);
      }

      try {
        await say('Trong kho còn những gì?');
        await fixture.waitFor(tester, find.text('HomeMind trả lời:'));
        expect(find.textContaining('Trong kho có 1 món'), findsOneWidget);
        expect(find.textContaining('Sữa native E2E (2 hộp'), findsOneWidget);
        await fixture.tap(tester, find.text('Đóng'));
        await say('Tôi vừa mua 1 hộp Sữa native E2E');
        await fixture.waitFor(tester, find.text('Lưu'));
        expect(find.text('Sữa native E2E'), findsWidgets);
        await fixture.tap(tester, find.text('Huỷ'));
        var inv = await fixture.request(
          '/workspaces/${actor['ws']}/inventory',
          'GET',
          null,
          actor['accessToken'] as String,
        );
        expect((inv['items'] as List).length, 1);
        expect((inv['items'] as List).single['productId'], productId);
        cancelQuantity = (inv['items'] as List).single['quantity'] as num;
        expect((inv['items'] as List).single['quantity'], 2);
        await say('Tôi vừa mua 1 hộp Sữa native E2E');
        await fixture.waitFor(tester, find.text('Lưu'));
        expect(find.text('Sữa native E2E'), findsWidgets);
        await fixture.tap(tester, find.text('Lưu'));
        await fixture.waitFor(tester, find.text('Cá nhân'));
        inv = await fixture.request(
          '/workspaces/${actor['ws']}/inventory',
          'GET',
          null,
          actor['accessToken'] as String,
        );
        expect((inv['items'] as List).length, 1);
        expect((inv['items'] as List).single['productId'], productId);
        confirmedQuantity = (inv['items'] as List).single['quantity'] as num;
        expect((inv['items'] as List).single['quantity'], 3);
      } finally {
        await fixture.request('/auth/account', 'DELETE', {
          'currentPassword': actor['password'],
        }, actor['accessToken'] as String);
        binding.reportData = {
          'realGeminiCallsAttempted': calls,
          'cancelQuantity': cancelQuantity,
          'confirmedQuantity': confirmedQuantity,
          'audioTranscription': 'NOT_VERIFIED',
        };
      }
    },
  );
}
