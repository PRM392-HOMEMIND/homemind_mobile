import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:homemind_mobile/features/family/family_gateway.dart';
import 'package:homemind_mobile/features/family/family_page.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';

import 'support/billing_concealment_scenarios.dart';
import 'support/load_app_fonts.dart';
import 'billing_test.dart' show FakeBilling;

void main() {
  setUpAll(loadAppFonts);
  testWidgets(
    'S01-S10 real widgets, actual destinations and synthetic data',
    concealmentScenarios,
  );
  for (final text in [
    'Thanh toán đã hoàn tất',
    'Gói Miễn phí đã đủ',
    'Vĩnh viễn',
    'Subscription unavailable',
    'Upgrade your free plan',
    'Payment history',
  ]) {
    test(
      'system billing text is classified: $text',
      () => expect(PlanBillingVisibility.isBillingText(text), isTrue),
    );
  }
  test(
    'shopping units/prices/purchases are retained and raw records unchanged',
    () {
      for (final type in ['inventory', 'shopping']) {
        final row = {
          'type': type,
          'id': 'synthetic',
          'title': 'Gói trà',
          'summary': 'Đã mua 2 gói · 20.000đ',
        };
        expect(PlanBillingVisibility.isBillingRecord(row), isFalse);
        expect(row['title'], 'Gói trà');
      }
      expect(
        PlanBillingVisibility.isBillingRecord({
          'type': 'billing.cancelled',
          'title': 'Đơn cũ',
        }),
        isTrue,
      );
      expect(
        PlanBillingVisibility.isBillingRecord({
          'type': 'notification',
          'title': 'Thanh toán',
          'summary': 'Đã mua gói',
        }),
        isTrue,
      );
    },
  );
  testWidgets(
    'English system error is concealed, controlled restore preserves it',
    (tester) async {
      AppText.setLanguage('en', persist: false);
      for (final visible in [false, true]) {
        await tester.pumpWidget(
          PlanBillingVisibility(
            visible: visible,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Text(
                  PlanBillingVisibility.message(
                    context,
                    'Upgrade your free plan',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(
            visible
                ? 'Upgrade your free plan'
                : 'The current usage limit has been reached.',
          ),
          findsOneWidget,
        );
      }
      AppText.setLanguage('vi', persist: false);
    },
  );
  testWidgets('mounted usage identity disappears on visibility change', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    final page = BillingUsageCard(
      used: 2,
      total: 15,
      remaining: 13,
      expiresAt: DateTime.utc(2026, 11, 18),
      plan: 'free',
    );
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, value, child) =>
            PlanBillingVisibility(visible: value, child: child!),
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    );
    expect(find.text('Vĩnh viễn'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Vĩnh viễn'), findsNothing);
    expect(find.text('Miễn phí'), findsNothing);
    expect(find.text('2/15'), findsOneWidget);
    expect(find.byType(BillingPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
  testWidgets(
    'already loaded BillingPage on stack is guarded after visibility changes',
    (tester) async {
      final visible = ValueNotifier(true);
      final service = ConcealmentService();
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, value, child) => PlanBillingVisibility(
            visible: value,
            fallbackBuilder: (_) => ProfilePage(service: service),
            child: child!,
          ),
          child: MaterialApp(
            home: BillingPage(
              gateway: FakeBilling(),
              refreshEntitlements: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gói & thanh toán'), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);
      expectConcealed(tester);
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
    },
  );
  for (final owner in [false, true]) {
    testWidgets(
      'Family entitlement copy and ${owner ? 'end' : 'leave'} confirmation stay concealed',
      (tester) async {
        var writes = 0;
        final gateway = FamilyGateway(
          workspaceId: 'synthetic',
          userId: 'synthetic',
          newKey: () => 'synthetic',
          refreshContext: () async {},
          request: (method, path, {body, idempotencyKey}) async {
            if (method != 'GET') {
              writes++;
              throw StateError('Read only');
            }
            if (path == '/me/workspaces') return {'items': []};
            return {
              'role': owner ? 'owner' : 'member',
              'eligible': false,
              'name': 'Không gian kiểm thử',
              'relativeCount': 1,
              'pendingCount': 0,
              'availableSeats': 4,
              'members': [],
              'sharingEnabled': true,
            };
          },
        );
        final service = ConcealmentService();
        await tester.pumpWidget(
          concealmentApp(service, FamilyPage(gateway: gateway)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Không gian hiện tại chưa có quyền mời thêm người thân.'),
          findsOneWidget,
        );
        expectConcealed(tester);
        final action = find.text(owner ? 'Dừng chia sẻ' : 'Rời nhóm');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('mất quyền truy cập'), findsOneWidget);
        expectConcealed(tester);
        await tester.tap(find.text('Quay lại'));
        await tester.pumpAndSettle();
        expect(writes, 0);
      },
    );
  }
}
