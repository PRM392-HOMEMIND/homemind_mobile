import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';

import '../test/support/billing_visual_fixtures.dart';
import 'native_ui_sync.dart';

// On-device presentation acceptance. Fixtures cannot reach any API/provider.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'billing branding native presentation, existing actions and visual evidence',
    (tester) async {
      AppText.setLanguage('vi', persist: false);
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Keep rendering while Android acquires the rasterized image surface.
        // A settled widget tree alone can still leave the previous surface frame.
        await awaitWithFrames(
          tester,
          binding.takeScreenshot(name).then<void>((_) {}),
        );
      }

      Future<void> show(Finder finder) async {
        final pageScroll = find
            .descendant(
              of: find.byType(BillingPage),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: pageScroll,
          maxScrolls: 60,
        );
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.05);
        await tester.pumpAndSettle();
      }

      final free = VisualBilling();
      await tester.pumpWidget(visualBillingApp(free, width: 430));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BillingCurrentPlanCard),
          matching: find.byIcon(Icons.home_rounded),
        ),
        findsOneWidget,
      );
      await capture('billing-free-430-initial');
      await capture('billing-free-430');
      expect(find.byKey(const Key('billing_current')), findsOneWidget);
      final plan = find.byKey(const Key('billing_plan_personal'));
      await show(plan);
      await tester.tap(plan);
      await capture('plan-expanded');
      final buy = find.byKey(const Key('billing_buy_personal'));
      await show(buy);
      await tester.tap(buy);
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận gói'), findsOneWidget);
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      expect(free.creates, 0);
      await show(find.byKey(const Key('billing_annual_soon')));
      await capture('coming-soon');
      await show(find.byType(BillingEmptyHistory));
      await capture('history-empty');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        visualBillingApp(VisualBilling(plan: 'family'), width: 430),
      );
      await capture('billing-paid-430');
      await show(plan);
      await tester.tap(plan);
      await tester.pumpAndSettle();
      await show(buy);
      expect(tester.widget<FilledButton>(buy).onPressed, isNull);
      await capture('disabled-lower-plan');
      for (final tier in ['personal', 'micro_pos']) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          visualBillingApp(VisualBilling(plan: tier), width: 430),
        );
        await capture('billing-${tier.replaceAll('_', '-')}-430');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        visualBillingApp(
          VisualBilling(withPayment: true, withHistory: true),
          width: 430,
        ),
      );
      await tester.pumpAndSettle();
      await show(find.byKey(const Key('billing_payment_state')));
      expect(
        tester
            .widget<BillingPaymentCard>(find.byType(BillingPaymentCard))
            .clock,
        isNotNull,
      );
      expect(find.byKey(const Key('billing_countdown')), findsOneWidget);
      await capture('payment-qr');
      final details = find.byKey(const Key('billing_transfer_details'));
      await show(details);
      await tester.tap(find.text('Thông tin chuyển khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Chủ tài khoản: DEMO RECEIVER'), findsOneWidget);
      expect(find.byKey(const Key('billing_created_at')), findsOneWidget);
      await capture('transfer-expanded');
      final paid = find.byKey(const Key('billing_history_visual-PAID'));
      await show(paid);
      await capture('history-collapsed');
      await tester.tapAt(tester.getTopLeft(paid) + const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(find.text('Mã đơn: DEMO-PAID'), findsOneWidget);
      await capture('history-expanded');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        visualBillingApp(VisualBilling(), width: 320, scale: 1.5),
      );
      await capture('billing-free-320-text150');
      expect(
        tester.getSize(find.byKey(const Key('billing_current'))).width,
        lessThanOrEqualTo(248),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        visualBillingApp(VisualBilling(), width: 320, scale: 2),
      );
      await capture('billing-free-320-text200');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(free.creates, 0);
    },
  );
}
