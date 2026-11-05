import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/auth/domain/account_auth_service.dart';
import 'package:homemind_mobile/features/auth/domain/auth_models.dart';
import 'package:homemind_mobile/features/auth/presentation/account_settings_page.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_service.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/home/presentation/global_search_surface.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/main.dart';

import 'mock_auth_service.dart';
import 'recording_plan_service.dart';

// Synthetic data adapter only; every rendered page/widget is production code.
// No API, authentication, AI provider, payment provider or database is contacted.
class ConcealmentService extends RecordingPlanService
    implements VoiceQuotaSource {
  ConcealmentService({super.plan = 'free'})
    : super(email: 'ui-audit@example.invalid');
  VoiceQuota get quota => VoiceQuota(
    periodId: 'synthetic-period',
    plan: plan,
    used: 2,
    total: 15,
    remaining: 13,
    startsAt: DateTime.utc(2026, 10, 19),
    expiresAt: DateTime.utc(2026, 11, 18, 4, 13, 25),
    serverNow: DateTime.utc(2026, 10, 19),
  );
  UserProfile get profile => UserProfile(
    userId: 'synthetic-ui-user',
    email: email,
    displayName: 'Tài khoản kiểm thử',
    workspaceId: 'synthetic-ui-workspace',
    workspaceName: 'Không gian kiểm thử',
    workspaceType: 'household',
    role: 'consumer',
    voiceQuota: quota,
  );
  @override
  Future<UserProfile> getMe() => SynchronousFuture(profile);
  @override
  Future<VoiceQuota?> getVoiceQuota() => SynchronousFuture(quota);
  @override
  Future<List<InventoryItem>> getInventory() => SynchronousFuture([]);
  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() => SynchronousFuture((
    items: <ShoppingItem>[],
    suggestions: <Map<String, Object?>>[],
  ));
  @override
  Future<({List<AppNotification> items, int unreadCount})> getNotifications() =>
      SynchronousFuture((items: <AppNotification>[], unreadCount: 0));
}

class ConcealmentAuth extends MockAuthService implements AccountAuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Read-only UI scenario: auth mutations forbidden');
}

class NoBillingCalls implements BillingGateway {
  int calls = 0;
  Never _refuse() {
    calls++;
    throw StateError('Hidden billing must not load');
  }

  @override
  Future<Map<String, Object?>> plans() async => _refuse();
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => _refuse();
  @override
  Future<Map<String, Object?>?> pending() async => _refuse();
  @override
  Future<Map<String, Object?>> create(String priceId) async => _refuse();
  @override
  Future<Map<String, Object?>> reconcile(String id) async => _refuse();
  @override
  Future<Map<String, Object?>> cancel(String id) async => _refuse();
  @override
  Future<void> clearPending() async {
    _refuse();
  }
}

Widget concealmentApp(ConcealmentService service, Widget page) =>
    PlanBillingVisibility(
      visible: false,
      fallbackBuilder: (_) => ProfilePage(service: service),
      child: MaterialApp(theme: HomeMindTheme.themeData, home: page),
    );

void expectConcealed(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final text = (element.widget as Text).data ?? '';
    expect(
      PlanBillingVisibility.isBillingText(text),
      isFalse,
      reason: 'Visible text: $text',
    );
  }
  expect(find.byKey(const Key('profile_row_plan')), findsNothing);
  expect(find.byKey(const Key('profile_upgrade')), findsNothing);
  expect(find.byKey(const Key('billing_current')), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> concealmentScenarios(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  AppText.setLanguage('vi', persist: false);
  final service = ConcealmentService(), auth = ConcealmentAuth();
  Future<void> shot(String id) async {
    await tester.pumpAndSettle();
    expectConcealed(tester);
    if (capture != null) await capture(id);
    // Machine-readable assertion boundary, also captured in the native log.
    debugPrint('CONCEALMENT $id PASS');
  }

  Future<void> show(Widget page) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(concealmentApp(service, page));
    await tester.pumpAndSettle();
  }

  Future<void> quotaVisible() => tester.scrollUntilVisible(
    find.byKey(const Key('voice_quota_used_total')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await show(
    ProfilePage(service: service, authService: auth, user: service.profile),
  );
  await shot('s01-profile');
  await quotaVisible();
  expect(find.text('2/15'), findsOneWidget);
  expect(find.text('Còn 13 lượt trong kỳ'), findsOneWidget);
  expect(find.textContaining('18/11/2026'), findsOneWidget);
  await shot('s02-usage');
  await tester.ensureVisible(find.text('Cách tính lượt'));
  await tester.tap(find.text('Cách tính lượt'));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('Lượt dùng chung trong không gian.'),
    findsOneWidget,
  );
  await shot('s03-usage-details');
  await show(AccountSettingsPage(auth: auth, profile: service.profile));
  await shot('s04-settings');
  await show(
    AppShell(
      assistantService: service,
      speechService: const UnavailableSpeechRecognitionService(),
    ),
  );
  await shot('s05-home-menu');

  final billing = NoBillingCalls();
  Future<void> direct(String id, {bool history = false}) async {
    await show(ProfilePage(service: service));
    final context = tester.element(find.byType(ProfilePage));
    // Exact production destination: PaywallSheet/HomePage use BillingPage for
    // both overview and initial payment detail. No invented history route.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillingPage(
          gateway: billing,
          refreshEntitlements: () async {},
          initialPayment: history
              ? () async {
                  throw StateError('Must not read payment detail');
                }
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);
    expect(billing.calls, 0);
    await shot(id);
    Navigator.of(tester.element(find.byType(ProfilePage).last)).pop();
    await tester.pumpAndSettle();
    expectConcealed(tester);
  }

  await direct('s06-direct-billing');
  await direct('s07-direct-payment-history', history: true);

  var reads = 0;
  final hub = HomeHubGateway(
    scope: 'synthetic',
    workspaceId: 'synthetic',
    request: (method, path) async {
      if (method == 'PATCH') {
        reads++;
        return {'unreadCount': 0};
      }
      if (path.contains('/search?')) {
        return {
          'items': [
            {
              'type': 'feature',
              'id': 'billing',
              'title': 'Gói & thanh toán',
              'summary': '',
            },
            {
              'type': 'notification',
              'id': 'synthetic-paid',
              'title': 'Thanh toán thành công',
              'summary': '',
            },
            {
              'type': 'shopping',
              'id': 'synthetic-item',
              'title': 'Gói trà',
              'summary': 'gói · needed',
            },
          ],
          'nextCursor': null,
        };
      }
      if (path.contains('notifications?')) {
        return {'items': [], 'unreadCount': 1, 'hasMore': false};
      }
      return {
        'id': 'synthetic-paid',
        'type': 'billing.paid',
        'targetType': 'billing',
        'targetId': 'synthetic-order',
        'title': 'Thanh toán thành công',
        'detail': 'Lịch sử thanh toán',
        'read': false,
      };
    },
  );
  await show(
    Scaffold(
      body: DurableNotificationsSurface(
        gateway: hub,
        initialId: 'synthetic-paid',
      ),
    ),
  );
  expect(reads, 0);
  await shot('s08-notification-target');
  await show(Scaffold(body: GlobalSearchSurface(gateway: hub)));
  expect(find.text('Gói trà'), findsOneWidget);
  expect(find.byKey(const Key('search_result_feature_billing')), findsNothing);
  expect(
    find.byKey(const Key('search_result_notification_synthetic-paid')),
    findsNothing,
  );
  await shot('s08-search');

  // Real app route factory and auth shell, warm unknown URL and fresh mount.
  for (final fresh in [false, true]) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      HomeMindApp(
        authService: auth,
        initialOnboardingCompleted: true,
        initialSession: AuthSession(
          token: 'synthetic-not-a-real-token',
          profile: service.profile,
          loginTime: DateTime.utc(2026, 10, 19),
        ),
        assistantService: service,
        speechService: const UnavailableSpeechRecognitionService(),
      ),
    );
    await tester.pumpAndSettle();
    if (!fresh) {
      Navigator.of(tester.element(find.byType(Scaffold).first))
          .pushNamed('/billing/payments/synthetic-order');
      await tester.pumpAndSettle();
    }
    await shot(fresh ? 's09-fresh-app' : 's09-unknown-url');
  }
  await show(ProfilePage(service: service, user: service.profile));
  await quotaVisible();
  await shot('s10-free-usage');
  expect(billing.calls, 0);
  expect(service.calls, isEmpty);
  await tester.pumpWidget(const SizedBox.shrink());
}
