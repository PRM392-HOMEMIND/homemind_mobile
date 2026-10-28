import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';

import 'billing_test.dart' show FakeBilling;

// Shape is the existing billing_order_public contract; these are UI fixtures,
// never provider receipts or evidence of real-money settlement.
class HistoryBilling extends FakeBilling {
  HistoryBilling(this.rows, {this.more = const []});
  final List<Map<String, Object?>> rows, more;
  final offsets = <int>[];
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async {
    offsets.add(offset);
    return {
      'entitlement': {'plan': 'free', 'source': 'free'},
      'workspaceType': 'household',
      'eligibility': {
        'personal': null,
        'family': null,
        'micro_pos': 'PLAN_SEGMENT_MISMATCH',
      },
      'payments': offset == 0 ? rows : more,
      if (offset == 0 && more.isNotEmpty) 'nextOffset': rows.length,
    };
  }
}

Map<String, Object?> history(String status, String code) => {
  'id': 'test-$code',
  'orderCode': code,
  'origin': 'SIMULATED_TEST',
  'status': status,
  'financialState': ['PAID', 'REVIEW'].contains(status) ? 'PAID' : 'UNPAID',
  'fulfillment': status == 'PAID'
      ? 'GRANTED'
      : status == 'REVIEW'
      ? 'REVIEW'
      : 'NONE',
  'price': {'plan': 'personal', 'amount': 29000, 'currency': 'VND'},
  'amountPaid': ['PAID', 'REVIEW'].contains(status) ? 29000 : 0,
  'createdAt': '2026-01-31T06:07:08Z',
  'paidAt': ['PAID', 'REVIEW'].contains(status) ? '2026-01-31T06:08:09Z' : null,
  'expiresAt': '2026-01-31T06:22:08Z',
  if (status == 'PAID')
    'grant': {
      'startsAt': '2026-01-31T06:08:09Z',
      'expiresAt': '2026-02-05T07:09:10Z',
      'originalExpiresAt': '2026-03-02T06:08:09Z',
      'supersededAt': '2026-02-05T07:09:10Z',
      'supersededBy': 'separate-test-grant',
    },
};

String localSecond(String value) {
  final d = DateTime.parse(value).toLocal();
  String two(int v) => '$v'.padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Future<void> mount(WidgetTester tester, HistoryBilling gateway) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpRestoredPlanBillingWidget(
    MaterialApp(
      home: BillingPage(gateway: gateway, refreshEntitlements: () async {}),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    testWidgets(
      '$language empty history contains no invented Free transaction',
      (tester) async {
        AppText.setLanguage(language, persist: false);
        final gateway = HistoryBilling([]);
        await mount(tester, gateway);
        await tester.scrollUntilVisible(
          find.text(
            language == 'en' ? 'Payment history' : 'Lịch sử thanh toán',
          ),
          250,
        );
        expect(
          find.byWidgetPredicate((w) => w is ListTile && w.onTap != null),
          findsNothing,
        );
        expect(gateway.offsets, [0]);
        expect(gateway.reconciles, 0);
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
    for (final status in [
      'PENDING',
      'CANCELLED',
      'EXPIRED',
      'REVIEW',
      'PAID',
    ]) {
      testWidgets(
        '$language $status detail shows persisted amount and exact-second timestamps',
        (tester) async {
          AppText.setLanguage(language, persist: false);
          final row = history(status, 'history-$status');
          final gateway = HistoryBilling([row]);
          await mount(tester, gateway);
          final entry = find.byKey(Key('billing_history_test-history-$status'));
          await tester.scrollUntilVisible(entry, 250);
          await Scrollable.ensureVisible(
            tester.element(entry),
            alignment: 0.05,
          );
          await tester.pumpAndSettle();
          await tester.tapAt(tester.getTopLeft(entry) + const Offset(30, 30));
          await tester.pumpAndSettle();

          expect(find.text('SIMULATED_TEST'), findsNothing);
          final observations = <String, bool>{
            'server-priced amount visible':
                find
                    .textContaining(
                      language == 'en'
                          ? 'Order amount: 29000 VND'
                          : 'Số tiền đơn: 29000 VND',
                    )
                    .evaluate()
                    .length ==
                (row['financialState'] == 'PAID' ? 1 : 0),
            'createdAt seconds visible': find
                .textContaining(
                  '${language == 'en' ? 'Created at: ' : 'Tạo lúc: '}${localSecond(row['createdAt'] as String)}',
                )
                .evaluate()
                .isNotEmpty,
            if (row['paidAt'] != null)
              'paidAt seconds visible': find
                  .textContaining(
                    '${language == 'en' ? 'Paid at: ' : 'Đã thanh toán lúc: '}${localSecond(row['paidAt'] as String)}',
                  )
                  .evaluate()
                  .isNotEmpty,
            if (status == 'PAID') ...{
              'grant start seconds visible': find
                  .textContaining(
                    localSecond((row['grant'] as Map)['startsAt'] as String),
                  )
                  .evaluate()
                  .isNotEmpty,
              'effective expiry seconds visible': find
                  .textContaining(
                    localSecond((row['grant'] as Map)['expiresAt'] as String),
                  )
                  .evaluate()
                  .isNotEmpty,
              'original expiry seconds visible': find
                  .textContaining(
                    localSecond(
                      (row['grant'] as Map)['originalExpiresAt'] as String,
                    ),
                  )
                  .evaluate()
                  .isNotEmpty,
            },
          };
          expect(observations, {
            for (final field in observations.keys) field: true,
          });
          expect(
            gateway.reconciles,
            0,
            reason:
                'Viewing history must not trigger a new financial operation',
          );
          expect(find.byKey(const Key('billing_verified')), findsNothing);
          await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
        },
      );
    }
    testWidgets(
      '$language paginated history retains earlier rows without duplicates',
      (tester) async {
        AppText.setLanguage(language, persist: false);
        final gateway = HistoryBilling(
          [history('CANCELLED', 'page-a')],
          more: [history('EXPIRED', 'page-b')],
        );
        await mount(tester, gateway);
        final more = find.text(language == 'en' ? 'Load more' : 'Xem thêm');
        await tester.scrollUntilVisible(more, 250, maxScrolls: 40);
        await tester.pumpAndSettle();
        await tester.tap(more);
        await tester.pumpAndSettle();
        for (final code in ['page-a', 'page-b']) {
          final row = find.byKey(Key('billing_history_test-$code'));
          await tester.scrollUntilVisible(
            row,
            code == 'page-a' ? -250 : 250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(row, findsOneWidget);
        }
        expect(gateway.offsets, [0, 1]);
        expect(
          find.text(language == 'en' ? 'Load more' : 'Xem thêm'),
          findsNothing,
        );
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
  }
}
