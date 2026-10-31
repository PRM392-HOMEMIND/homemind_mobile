import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';

import 'full_system_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fixture.nativeTest(
    'NOTICE-01 production scoped hub household and store parity',
    (tester) async {
      if (!fixture.productionSafe) {
        throw StateError('Explicit production-safe target required');
      }
      for (final type in ['household', 'store']) {
        final actor = await fixture.start(tester, type: type);
        await fixture.notificationFlow(tester, actor);
        await fixture.tap(tester, find.byKey(const Key('nav_profile')));
        await fixture.waitForScrolled(
          tester,
          find.byKey(const Key('voice_quota_used_total')),
          find.byType(ProfilePage),
        );
        final quota = await fixture.request(
          '/me',
          'GET',
          null,
          actor['accessToken'] as String,
        );
        expect((quota['voiceQuota'] as Map)['used'], 0);
        await fixture.closeFlow(tester, actor, delete: true);
      }
      binding.reportData = {
        'revision': fixture.expectedRevision,
        'scope': 'HOUSEHOLD_STORE_HUB_PROFILE',
        'realGeminiCallsAttempted': 0,
        'financialMutation': 'NONE',
        'audioTranscription': 'NOT_VERIFIED',
      };
    },
  );
  fixture.nativeTest(
    'PROD-02 actual Flutter public HTTPS owned traversal and real AI',
    (tester) async {
      if (!fixture.productionSafe) {
        throw StateError('Explicit production-safe target required');
      }
      final actor = await fixture.start(tester);
      await fixture.tap(tester, find.byKey(const Key('nav_inventory')));
      await fixture.waitFor(tester, find.text('Sữa native E2E'));
      await fixture.tap(tester, find.byKey(const Key('nav_shopping')));
      await fixture.waitFor(tester, find.text('Trứng native E2E'));
      await fixture.notificationFlow(tester, actor);
      await fixture.accountLifecycle(tester, actor);
      await fixture.host('background-resume');
      int calls = 0;
      Future<void> say(String text) async {
        expect(calls, lessThan(3));
        calls++;
        await fixture.say(tester, text);
      }

      await say('Trong kho còn những gì?');
      await fixture.waitFor(tester, find.text('HomeMind trả lời:'));
      await fixture.tap(tester, find.text('Đóng'));
      await say('Tôi vừa mua 1 hộp Sữa native production cancel');
      await fixture.waitFor(tester, find.text('Lưu'));
      await fixture.tap(tester, find.text('Huỷ'));
      var inv = await fixture.request(
        '/workspaces/${actor['ws']}/inventory',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(
        (inv['items'] as List).any(
          (dynamic p) => p['name'] == 'Sữa native production cancel',
        ),
        false,
      );
      await say('Tôi vừa mua 1 hộp Sữa native production confirm');
      await fixture.waitFor(tester, find.text('Lưu'));
      await fixture.tap(tester, find.text('Lưu'));
      inv = await fixture.persisted(
        tester,
        actor,
        '/workspaces/${actor['ws']}/inventory',
        (data) => (data['items'] as List).any(
          (dynamic p) =>
              p['name'] == 'Sữa native production confirm' &&
              p['quantity'] == 1,
        ),
      );
      expect(
        (inv['items'] as List)
            .where((dynamic p) => p['name'] == 'Sữa native production confirm')
            .length,
        1,
      );
      await fixture.tap(tester, find.byKey(const Key('nav_profile')));
      await fixture.tap(tester, find.byKey(const Key('profile_upgrade')));
      await fixture.waitFor(tester, find.byKey(const Key('billing_current')));
      expect(find.textContaining('Gói hiện tại: Miễn phí'), findsOneWidget);
      await fixture.back(tester);
      await fixture.closeFlow(tester, actor, delete: true);
      binding.reportData = {
        'realGeminiCallsAttempted': calls,
        'revision': fixture.expectedRevision,
        'financialMutation': 'NONE',
        'audioTranscription': 'NOT_VERIFIED',
      };
    },
  );
  fixture.nativeTest(
    'BILL-03 production read-only billing household and store without checkout',
    (tester) async {
      if (!fixture.productionSafe) {
        throw StateError('Explicit production-safe target required');
      }
      for (final type in ['household', 'store']) {
        final actor = await fixture.start(tester, type: type);
        await fixture.billingReadOnlyFlow(tester, actor);
      }
      binding.reportData = {
        'revision': fixture.expectedRevision,
        'scope': 'READ_ONLY_BILLING',
        'payosCreateRequests': 0,
        'realMoney': 0,
      };
    },
  );
  tearDownAll(fixture.cleanupOwned);
}
