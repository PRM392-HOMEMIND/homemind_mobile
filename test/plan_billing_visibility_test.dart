import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/presentation/confirm_page.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/home/presentation/global_search_surface.dart';
import 'package:homemind_mobile/features/home/presentation/paywall_sheet.dart';
import 'package:homemind_mobile/features/home/presentation/plan_card.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/main.dart';

import 'billing_test.dart' show FakeBilling, PaidBillingService;
import 'support/mock_auth_service.dart';
import 'support/recording_plan_service.dart';
import 'support/load_app_fonts.dart';

class _QuotaService extends RecordingPlanService implements VoiceQuotaSource {
  _QuotaService({super.plan, super.used, this.exhausted = false});
  final bool exhausted;
  @override
  Future<List<InventoryItem>> getInventory() => SynchronousFuture([]);
  @override
  Future<VoiceQuota?> getVoiceQuota() => SynchronousFuture(
    VoiceQuota(
      periodId: 'owned-period',
      plan: plan,
      used: exhausted ? 15 : 10,
      total: 15,
      remaining: exhausted ? 0 : 5,
      startsAt: DateTime.utc(2026, 10, 7),
      expiresAt: DateTime.utc(2026, 11, 6, 4, 29, 28),
      serverNow: DateTime.utc(2026, 10, 14),
    ),
  );
}

class _NeverBilling extends FakeBilling {
  int reads = 0;
  @override
  Future<Map<String, Object?>> plans() async {
    reads++;
    return super.plans();
  }
}

Widget _app(
  Widget page, {
  bool visible = false,
  double scale = 1,
  bool dark = false,
}) => PlanBillingVisibility(
  visible: visible,
  child: MaterialApp(
    theme: HomeMindTheme.themeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        platformBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: child!,
    ),
    home: page,
  ),
);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => AppText.setLanguage('vi', persist: false));
  test('missing define hides UI and does not change purchases or target permission', () {
    expect(PlanBillingVisibility.defaultVisible, isTrue);
    expect(EnvConfig.externalBillingAllowed, isFalse);
    for (final target in [
      ('plan', 'family'),
      ('billing', 'old-payment'),
      ('feature', 'billing'),
      ('feature', 'history'),
      ('feature', 'help'),
    ]) {
      expect(PlanBillingVisibility.isPlanTarget(target.$1, target.$2), isTrue);
    }
    for (final type in [
      'profile',
      'inventory',
      'shopping',
      'family',
      'notification',
    ]) {
      expect(PlanBillingVisibility.isPlanTarget(type, 'owned'), isFalse);
    }
  });
  for (final plan in ['free', 'personal', 'family', 'micro_pos']) {
    for (final size in [const Size(320, 800), const Size(393, 852)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('read-only profile $plan ${size.width} scale$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final service = _QuotaService(plan: plan);
          await tester.pumpWidget(
            _app(
              ProfilePage(service: service),
              scale: scale,
              dark: scale == 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('profile_row_plan')), findsNothing);
          expect(find.byKey(const Key('profile_upgrade')), findsNothing);
          for (final text in [
            'Gói của bạn',
            'Miễn phí',
            'Cá nhân',
            'Gia đình',
            'Micro-POS',
            'Vĩnh viễn',
            'Xem gói hiện tại',
          ]) {
            expect(find.text(text), findsNothing);
          }
          expect(find.byType(BillingPage), findsNothing);
          await tester.scrollUntilVisible(
            find.text('Còn 5 lượt trong kỳ'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('10/15'), findsOneWidget);
          expect(find.text('Còn 5 lượt trong kỳ'), findsOneWidget);
          expect(find.textContaining('06/11/2026'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(service.calls, isEmpty);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
  testWidgets(
    'loading profile preserves its skeleton and never offers billing',
    (tester) async {
      final pending = Completer<UserProfile>();
      final service = _LoadingProfile(pending);
      await tester.pumpWidget(_app(ProfilePage(service: service)));
      await tester.pump();
      expect(find.byKey(const Key('profile_upgrade')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      pending.complete(await RecordingPlanService().getMe());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_row_plan')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'card and inventory warning retain information without callbacks',
    (tester) async {
      final service = _QuotaService(used: 29);
      final home = await service.getHomeSummary();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PlanCard(home: home, service: service, isMerchant: false),
          ),
        ),
      );
      expect(find.byKey(const Key('plan_card')), findsNothing);
      expect(find.byKey(const Key('plan_card_cta')), findsNothing);
      expect(find.text('Sắp đầy! Chỉ còn 1 chỗ trống'), findsNothing);
      await tester.pumpWidget(
        _app(Scaffold(body: InventoryPage(service: service))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory_plan_banner')), findsOneWidget);
      expect(find.text('Xem gói hiện tại'), findsNothing);
      expect(service.calls, isEmpty);
    },
  );
  testWidgets('direct constructors and shared helper never load payment data', (
    tester,
  ) async {
    final billing = _NeverBilling();
    var initialReads = 0;
    await tester.pumpWidget(
      _app(
        BillingPage(
          gateway: billing,
          refreshEntitlements: () async {},
          initialPayment: () async {
            initialReads++;
            return {};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);
    expect(find.text('Gói & thanh toán'), findsNothing);
    expect(billing.reads, 0);
    expect(initialReads, 0);
    final service = PaidBillingService();
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                PaywallSheet.show(context, service: service, source: 'stale'),
            child: const Text('stale handler'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('stale handler'));
    await tester.pumpAndSettle();
    expect(find.byType(BillingPage), findsNothing);
    await tester.pumpWidget(
      _app(PaywallSheet(service: service, source: 'direct')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ & Tài khoản'), findsOneWidget);
    expect(find.byKey(const Key('paywall_submit')), findsNothing);
  });
  testWidgets(
    'restored scope retains profile entry and existing billing page; purchases still off',
    (tester) async {
      await tester.pumpWidget(
        _app(ProfilePage(service: PaidBillingService()), visible: true),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profile_row_plan')));
      await tester.tap(find.byKey(const Key('profile_row_plan')));
      await tester.pumpAndSettle();
      expect(find.text('Gói & thanh toán'), findsOneWidget);
      expect(find.byKey(const Key('billing_current')), findsOneWidget);
      expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
      expect(EnvConfig.externalBillingAllowed, isFalse);
    },
  );
  for (final path in [
    '/billing',
    '/plans',
    '/subscription?SHOW_PLAN_AND_BILLING_UI=true',
    '/billing/payments/legacy',
  ]) {
    testWidgets('cold and warm unregistered URL $path falls back safely', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = path;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      await tester.pumpWidget(
        HomeMindApp(
          authService: MockAuthService(),
          initialOnboardingCompleted: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gói & thanh toán'), findsNothing);
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(Navigator.of(context).pushNamed(path));
      await tester.pumpAndSettle();
      expect(find.text('Gói & thanh toán'), findsNothing);
      expect(find.byType(BillingPage), findsNothing);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'search hides plan/payment filters and all actual aliases, keeps ordinary routes',
    (tester) async {
      final gateway = HomeHubGateway(
        scope: 'owned',
        workspaceId: 'owned',
        request: (method, path) async => {
          'items': [
            for (final id in ['billing', 'history', 'help', 'profile'])
              {'type': 'feature', 'id': id, 'title': id, 'summary': 'fixture'},
            {
              'type': 'plan',
              'id': 'family',
              'title': 'Gia đình',
              'summary': 'fixture',
            },
            {
              'type': 'billing',
              'id': 'legacy',
              'title': 'Đơn cũ',
              'summary': 'fixture',
            },
          ],
          'nextCursor': null,
        },
      );
      await tester.pumpWidget(
        _app(Scaffold(body: GlobalSearchSurface(gateway: gateway))),
      );
      await tester.pumpAndSettle();
      for (final id in ['billing', 'history', 'help']) {
        expect(find.byKey(Key('search_result_feature_$id')), findsNothing);
      }
      expect(find.byKey(const Key('search_result_plan_family')), findsNothing);
      expect(
        find.byKey(const Key('search_result_billing_legacy')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('search_result_feature_profile')),
        findsOneWidget,
      );
      expect(find.widgetWithText(ChoiceChip, 'Gói'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Thanh toán'), findsNothing);
    },
  );
  for (final type in ['billing', 'plan', 'profile']) {
    testWidgets(
      'notification $type hides billing content without acknowledging it',
      (tester) async {
        var reads = 0;
        final gateway = HomeHubGateway(
          scope: 'owned',
          workspaceId: 'owned',
          request: (method, path) async {
            if (method == 'PATCH') {
              reads++;
              return {'unreadCount': 0};
            }
            if (path.contains('notifications?')) {
              return {'items': [], 'unreadCount': 0, 'hasMore': false};
            }
            return {
              'id': 'n1',
              'title': 'Sự kiện có ích',
              'detail': 'Nội dung vẫn đọc được',
              'read': false,
              'targetType': type,
              'targetId': type == 'billing' ? 'legacy' : type,
              'receivedAt': '2026-10-14T01:00:00Z',
              'occurredAt': '2026-10-14T01:00:00Z',
            };
          },
        );
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: DurableNotificationsSurface(
                gateway: gateway,
                initialId: 'n1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Nội dung vẫn đọc được'),
          type == 'profile' ? findsOneWidget : findsNothing,
        );
        expect(reads, type == 'profile' ? 1 : 0);
        expect(
          find.text('Mở nội dung liên quan'),
          type == 'profile' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'voice exhausted keeps truthful message and does not show upgrade action',
    (tester) async {
      await tester.pumpWidget(
        _app(
          AppShell(
            assistantService: _QuotaService(exhausted: true),
            speechService: const UnavailableSpeechRecognitionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_voice')));
      await tester.pump();
      expect(find.text('Đã hết lượt trợ lý trong kỳ này.'), findsOneWidget);
      expect(find.text('Xem gói hiện tại'), findsNothing);
      expect(find.byType(SnackBarAction), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('confirm cannot turn a free-plan block into save or upgrade', (
    tester,
  ) async {
    final service = RecordingPlanService(used: 30);
    final draft = AssistantTurn.fromJson({
      'kind': 'write_draft',
      'turnId': 'owned',
      'toolsProposed': [
        {
          'toolId': 'inventory.add',
          'arguments': {
            'productName': 'Sản phẩm mới',
            'quantity': 1,
            'unit': 'gói',
          },
        },
      ],
    });
    await tester.pumpWidget(_app(ConfirmPage(service: service, draft: draft)));
    await tester.pumpAndSettle();
    expect(find.text('Xem gói hiện tại'), findsNothing);
    expect(find.textContaining('Không thể thêm sản phẩm mới.'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Huỷ'), findsOneWidget);
    expect(service.calls, isEmpty);
  });

  testWidgets('server plan label never renders at 320px text200', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const label = 'Gói gia đình có tên dài từ dữ liệu để kiểm tra hiển thị';
    await tester.pumpWidget(
      _app(ProfilePage(service: _QuotaService(plan: label)), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_row_plan')), findsNothing);
    expect(find.text(label), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rendered frames compare restored and hidden plan row with real typography',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _QuotaService();
      const capture = Key('visibility_capture');
      for (final visible in [true, false]) {
        await tester.pumpWidget(
          _app(
            RepaintBoundary(
              key: capture,
              child: ProfilePage(service: service),
            ),
            visible: visible,
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(
          Key(visible ? 'profile_row_plan' : 'voice_quota_used_total'),
        );
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(row), alignment: 0.38);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile_upgrade')),
          visible ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        final output = Platform.environment['HOMEMIND_VISIBILITY_SCREENSHOTS'];
        if (output != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final dir = Directory(output);
            await dir.create(recursive: true);
            await File(
              '${dir.path}/${visible ? 'profile_before_restored' : 'profile_after_hidden'}.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}

class _LoadingProfile extends RecordingPlanService {
  _LoadingProfile(this.pending);
  final Completer<UserProfile> pending;
  @override
  Future<UserProfile> getMe() => pending.future;
}
