import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_quota_panel.dart';

import 'billing_distribution_test.dart'
    show DistributionGateway, legacy, expectNoInstructions;
import 'support/recording_profile_service.dart';

class ReadOnlyBilling extends DistributionGateway {
  ReadOnlyBilling(this.plan) : super(legacy);
  final String plan;
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => {
    'entitlement': {
      'plan': plan,
      'source': plan == 'free' ? 'free' : 'billing',
    },
    'workspaceType': plan == 'micro_pos' ? 'store' : 'household',
    'payments': [legacy],
  };
}

void main() {
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    for (final plan in ['free', 'personal', 'family', 'micro_pos']) {
      for (final width in [320.0, 430.0]) {
        testWidgets('$language $plan read-only billing at $width text200', (
          tester,
        ) async {
          AppText.setLanguage(language, persist: false);
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final total = {
            'free': 15,
            'personal': 60,
            'family': 100,
            'micro_pos': 200,
          }[plan]!;
          final profile = UserProfile(
            userId: 'owned',
            email: '',
            displayName: 'Owned',
            workspaceId: 'owned',
            workspaceName: 'Owned',
            role: 'owner',
            workspaceType: plan == 'micro_pos' ? 'store' : 'household',
            voiceQuota: VoiceQuota.fromJson({
              'periodId': 'owned-period',
              'plan': plan,
              'used': 1,
              'total': total,
              'remaining': total - 1,
              'startsAt': '2026-10-07T00:00:00Z',
              'expiresAt': '2026-11-06T00:00:00Z',
              'serverNow': '2026-10-07T01:00:00Z',
            }),
          );
          final gateway = ReadOnlyBilling(plan);
          var opens = 0;
          final billing = BillingPage(
            gateway: gateway,
            refreshEntitlements: () async {},
            voiceUsage: VoiceQuotaPanel(
              service: RecordingProfileService(profile),
              billingPresentation: true,
            ),
            launchCheckout: (_) async {
              opens++;
              return true;
            },
          );
          await tester.pumpRestoredPlanBillingWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: billing,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('billing_current')), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const Key('voice_quota_used_total')),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('1/$total'), findsOneWidget);
          expectNoInstructions();
          for (final key in [
            'billing_annual_soon',
            'billing_renewal_soon',
            'billing_refund_soon',
            'billing_support_surface',
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(Key(key)),
              180,
              maxScrolls: 60,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expectNoInstructions();
            expect(tester.takeException(), isNull);
          }
          expect(
            [gateway.creates, gateway.checks, gateway.cancels, opens],
            [0, 0, 0, 0],
          );
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pumpAndSettle();
          expect(
            [gateway.creates, gateway.checks, gateway.cancels, opens],
            [0, 0, 0, 0],
          );
          expect(tester.takeException(), isNull);
          await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
