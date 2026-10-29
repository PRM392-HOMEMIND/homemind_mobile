import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';

import 'billing_test.dart' show FakeBilling;

class EligibilityBilling extends FakeBilling {
  EligibilityBilling(this.plan);
  final String plan;
  int creates = 0;
  @override
  Future<Map<String, Object?>> plans() async => {
    'checkoutEnabled': true,
    'plans': [
      for (final item in [
        ('personal', 29000, 60),
        ('family', 59000, 100),
        ('micro_pos', 149000, 200),
      ])
        {
          'id': '${item.$1}-month-v2',
          'plan': item.$1,
          'amount': item.$2,
          'currency': 'VND',
          'workspaceTypes': [item.$1 == 'micro_pos' ? 'store' : 'household'],
          'durationSeconds': 2592000,
          'voiceLimit': item.$3,
          'productLimit': item.$1 == 'micro_pos' ? 500 : null,
        },
    ],
  };
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => {
    'entitlement': {
      'plan': plan,
      'source': plan == 'free' ? 'free' : 'billing',
    },
    'workspaceType': plan == 'micro_pos' ? 'store' : 'household',
    'eligibility': {
      'personal': plan == 'personal'
          ? 'PLAN_ALREADY_ACTIVE'
          : plan == 'family'
          ? 'PLAN_DOWNGRADE_BLOCKED'
          : plan == 'micro_pos'
          ? 'PLAN_SEGMENT_MISMATCH'
          : null,
      'family': plan == 'family'
          ? 'PLAN_ALREADY_ACTIVE'
          : plan == 'micro_pos'
          ? 'PLAN_SEGMENT_MISMATCH'
          : null,
      'micro_pos': plan == 'micro_pos'
          ? 'PLAN_ALREADY_ACTIVE'
          : 'PLAN_SEGMENT_MISMATCH',
    },
    'payments': [],
  };
  @override
  Future<Map<String, Object?>> create(String id) async {
    creates++;
    throw StateError('No test checkout authorized');
  }
}

void main() {
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    for (final plan in ['free', 'personal', 'family', 'micro_pos']) {
      for (final width in [320.0, 360.0]) {
        testWidgets(
          '$language $plan current plan remains readable without purchase at ${width.toInt()}px and 200% text',
          (tester) async {
            AppText.setLanguage(language, persist: false);
            tester.view.physicalSize = Size(width, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final gateway = EligibilityBilling(plan);

            await tester.pumpRestoredPlanBillingWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: BillingPage(
                  gateway: gateway,
                  refreshEntitlements: () async {},
                ),
              ),
            );

            await tester.pump();

            final error = tester.takeException();

            expect(error, isNull);
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );

            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('billing_current')), findsOneWidget);
            for (final tier in ['personal', 'family', 'micro_pos']) {
              expect(find.byKey(Key('billing_plan_$tier')), findsNothing);
              expect(find.byKey(Key('billing_buy_$tier')), findsNothing);
            }
            expect(
              find.textContaining(
                language == 'en'
                    ? 'Plan payments are currently unavailable'
                    : 'Thanh toán gói hiện chưa được hỗ trợ',
              ),
              findsOneWidget,
            );
            expect(gateway.creates, 0);

            await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
          },
        );
      }
    }
    testWidgets(
      '$language annual/renew/refund is visibly unavailable and sends no request',
      (tester) async {
        AppText.setLanguage(language, persist: false);
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final gateway = EligibilityBilling('free');
        await tester.pumpRestoredPlanBillingWidget(
          MaterialApp(
            home: BillingPage(
              gateway: gateway,
              refreshEntitlements: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final feature in ['annual', 'renewal', 'refund']) {
          final card = find.byKey(Key('billing_${feature}_soon'));
          await tester.scrollUntilVisible(
            card,
            250,
            scrollable: find
                .descendant(
                  of: find.byType(BillingPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(card);
          await tester.tap(card);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.descendant(of: card, matching: find.byType(ButtonStyleButton)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.enabled == false &&
                    widget.properties.label?.contains(tr('Chưa thể sử dụng')) ==
                        true,
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: card,
              matching: find.text(
                tr(feature == 'annual' ? 'Sắp ra mắt' : 'Đang phát triển'),
              ),
            ),
            findsOneWidget,
          );
        }
        expect(gateway.creates, 0);
        expect(gateway.reconciles, 0);
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
  }
}
