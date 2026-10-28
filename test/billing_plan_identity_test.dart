import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';

void main() {
  const expected = {
    'free': Icons.home_rounded,
    'personal': Icons.person_rounded,
    'family': Icons.family_restroom_rounded,
    'micro_pos': Icons.storefront_rounded,
  };
  tearDown(() => AppText.setLanguage('vi', persist: false));

  for (final language in ['vi', 'en']) {
    for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('plan identity $language $width text $scale', (
          tester,
        ) async {
          AppText.setLanguage(language, persist: false);
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          for (final tier in expected.keys) {
            var purchases = 0;
            for (final state in ['current', 'available', 'disabled']) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: HomeMindTheme.themeData,
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              BillingCurrentPlanCard(plan: tier),
                              BillingPlanCard(
                                key: ValueKey('$tier-$state'),
                                plan: {'plan': tier, 'amount': 29000},
                                current: state == 'current',
                                canPurchase: state == 'available',
                                onPurchase: () => purchases++,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final identities = find.byType(PlanVisualIdentity);
              expect(identities, findsNWidgets(2));
              for (final identity in identities.evaluate()) {
                final root = find.byWidget(identity.widget);
                final icon = find.descendant(
                  of: root,
                  matching: find.byType(Icon),
                );
                expect(tester.widget<Icon>(icon).icon, expected[tier]);
                expect(tester.getSize(root), const Size(52, 52));
                expect(tester.getSize(icon), const Size(26, 26));
                expect(tester.getCenter(root), tester.getCenter(icon));
                expect(
                  tester
                      .widget<ExcludeSemantics>(
                        find
                            .descendant(
                              of: root,
                              matching: find.byType(ExcludeSemantics),
                            )
                            .first,
                      )
                      .excluding,
                  true,
                );
                expect(tester.widget<Icon>(icon).semanticLabel, isNull);
              }
              final currentIcon = tester.getRect(identities.first);
              final title = tester.getRect(
                find.byKey(const Key('billing_current')),
              );
              expect(title.left - currentIcon.right, greaterThanOrEqualTo(12));
              expect(currentIcon.overlaps(title), false);
              expect(
                find.bySemanticsLabel(billingPlanName(tier)),
                findsWidgets,
              );
              final header = find.byKey(Key('billing_plan_$tier'));
              await tester.ensureVisible(header);
              await tester.pumpAndSettle();
              await tester.tapAt(
                tester.getTopLeft(header) + const Offset(24, 24),
              );
              await tester.pumpAndSettle();
              final buy = find.byKey(Key('billing_buy_$tier'));
              if (state == 'current') {
                expect(buy, findsNothing);
              } else {
                expect(buy, findsNothing);
              }
              expect(purchases, 0);
              expect(tester.takeException(), isNull);
            }
          }
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
