import 'support/restored_plan_billing_ui.dart';

import 'dart:async';

import 'package:homemind_mobile/core/widgets/page_skeleton.dart';

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/billing_visual_fixtures.dart';

class LoadingBilling extends VisualBilling {
  final loading = Completer<Map<String, Object?>>();
  @override
  Future<Map<String, Object?>> plans() => loading.future;
}

void main() {
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets(
          '$language billing components width=$width scale=$scale no clipping',
          (tester) async {
            AppText.setLanguage(language, persist: false);
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpRestoredPlanBillingWidget(
              visualComponents(scale: scale),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester
                  .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .value,
              1,
            );
            expect(find.byType(QrImageView), findsNothing);
            expect(
              find.byKey(const Key('billing_transfer_details')),
              findsNothing,
            );
            for (final key in [
              'billing_plan_personal',
              'billing_history_visual-PAID',
              'billing_history_visual-CANCELLED',
              'billing_history_visual-PENDING',
            ]) {
              final target = find.byKey(Key(key)).last;
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              // Tap the header, not the centre of a tall expanded card.
              await tester.tapAt(
                tester.getTopLeft(target) + const Offset(32, 24),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  testWidgets(
    'read-only pending receipt exposes no QR, copy or payment callback',
    (tester) async {
      final semantics = tester.ensureSemantics();

      var checks = 0, opens = 0, cancels = 0;
      final copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BillingPaymentCard(
                payment: visualPayment('PENDING'),
                stateText: 'Pending',
                pending: true,
                checkoutEnabled: true,
                busy: false,
                onCheck: () => checks++,
                onOpen: () => opens++,
                onCancel: () => cancels++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byKey(const Key('billing_transfer_details')), findsNothing);
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.textContaining('DEMO RECEIVER'), findsNothing);
      expect(find.textContaining('DEMO ONLY NO PAYMENT'), findsNothing);
      final receipt = find.byType(ExpansionTile);
      await tester.tap(receipt);
      await tester.pumpAndSettle();
      expect(find.byType(ButtonStyleButton), findsNothing);
      semantics.dispose();
      expect(copies, isEmpty);
      expect([checks, opens, cancels], [0, 0, 0]);
    },
  );
  testWidgets(
    'coming soon exposes disabled semantics with no action or navigation',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: ComingSoonCard(
              title: 'Annual',
              description: 'Unavailable',
              icon: Icons.construction,
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(ComingSoonCard));
      expect(
        node.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), false);
      await tester.tap(find.text('Annual'));
      await tester.pump();
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      semantics.dispose();
    },
  );
  testWidgets('loading card is visible until the existing load completes', (
    tester,
  ) async {
    final gateway = LoadingBilling();
    await tester.pumpRestoredPlanBillingWidget(visualBillingApp(gateway));
    await tester.pump();
    expect(find.byType(PageSkeleton), findsOneWidget);
    expect(
      tester.widget<PageSkeleton>(find.byType(PageSkeleton)).page,
      SkeletonPage.billing,
    );
    expect(find.byType(BillingCurrentPlanCard), findsNothing);
    gateway.loading.complete(await VisualBilling().plans());
    await tester.pumpAndSettle();
    expect(find.byType(PageSkeleton), findsNothing);
    expect(find.byType(BillingPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BillingCurrentPlanCard),
        matching: find.byIcon(Icons.home_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test('old logo absent and owner branding registered', () {
    expect(File('assets/images/logo.png').existsSync(), false);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final folder in ['assets/logos/', 'assets/icons/']) {
      expect(pubspec, contains(folder));
    }
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      expect(
        file.readAsStringSync(),
        isNot(contains('assets/images/logo.png')),
        reason: file.path,
      );
    }
  });
}
