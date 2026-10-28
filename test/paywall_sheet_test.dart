import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/paywall_sheet.dart';

import 'support/recording_plan_service.dart';

Future<void> _open(
  WidgetTester tester,
  RecordingPlanService service, {
  String source = 'home_card',
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpRestoredPlanBillingWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                PaywallSheet.show(context, service: service, source: source),
            child: const Text('mở'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [
    (
      plan: 'free',
      role: AccountRole.consumer,
      source: 'home_card',
      fail: false,
    ),
    (
      plan: 'free',
      role: AccountRole.merchant,
      source: 'home_card',
      fail: false,
    ),
    (
      plan: 'free',
      role: AccountRole.consumer,
      source: 'limit_reached',
      fail: false,
    ),
    (
      plan: 'personal',
      role: AccountRole.consumer,
      source: 'home_card',
      fail: false,
    ),
    (
      plan: 'family',
      role: AccountRole.consumer,
      source: 'profile',
      fail: false,
    ),
    (
      plan: 'micro_pos',
      role: AccountRole.merchant,
      source: 'profile',
      fail: false,
    ),
    (plan: 'free', role: AccountRole.consumer, source: 'home_card', fail: true),
  ]) {
    testWidgets(
      'legacy ${scenario.plan} ${scenario.role.name} ${scenario.source} failure=${scenario.fail} stays read-only',
      (tester) async {
        final service = RecordingPlanService(
          plan: scenario.plan,
          initialRole: scenario.role,
        );
        if (scenario.fail) service.failWith = StateError('boom');
        await _open(tester, service, source: scenario.source);
        final notice = find.textContaining(
          'Thanh to\u00e1n g\u00f3i hi\u1ec7n ch\u01b0a \u0111\u01b0\u1ee3c h\u1ed7 tr\u1ee3',
        );
        expect(notice, findsOneWidget);
        for (final plan in ['free', 'personal', 'family', 'micro_pos']) {
          expect(find.byKey(Key('paywall_plan_$plan')), findsNothing);
          expect(find.byKey(Key('paywall_radio_on_$plan')), findsNothing);
        }
        expect(find.byKey(const Key('paywall_submit')), findsNothing);
        expect(find.textContaining('29.000'), findsNothing);
        expect(find.textContaining('59.000'), findsNothing);
        expect(find.textContaining('149.000'), findsNothing);
        await tester.tap(notice);
        await tester.pumpAndSettle();
        expect(service.calls, isEmpty);
        expect(find.textContaining('boom'), findsNothing);
        expect(find.textContaining('\u0110\u00e3 ghi nh\u1eadn'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(notice, findsNothing);
        expect(service.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
