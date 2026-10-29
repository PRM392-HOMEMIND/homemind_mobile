import 'support/restored_plan_billing_ui.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/home_header.dart';
import 'package:homemind_mobile/features/home/presentation/home_surface.dart';
import 'package:homemind_mobile/features/home/presentation/global_search_surface.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';

import 'support/recording_plan_service.dart';
import 'billing_test.dart' show FakeBilling;

class HubFixtureService extends RecordingPlanService {
  @override
  Future<List<InventoryItem>> getInventory() => SynchronousFuture([]);
  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() => SynchronousFuture((items: [], suggestions: []));
  @override
  Future<({List<AppNotification> items, int unreadCount})> getNotifications() =>
      SynchronousFuture((items: [], unreadCount: 0));
}

class _Observer extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route route, Route? previousRoute) {
    pushes++;
  }
}

class _Elapsed implements Stopwatch {
  int milliseconds = 0;
  int starts = 0, stops = 0;
  @override
  int get elapsedMilliseconds => milliseconds;
  @override
  void start() {
    starts++;
  }

  @override
  void stop() {
    stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowCheck extends FakeBilling {
  final completion = Completer<Map<String, Object?>>();
  @override
  Future<Map<String, Object?>> reconcile(String id) {
    reconciles++;
    return completion.future;
  }
}

void main() {
  setUp(() => AppText.setLanguage('vi', persist: false));
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    for (final role in AccountRole.values) {
      for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
        for (final scale in [1.0, 1.3, 1.5, 2.0]) {
          testWidgets(
            'header and nav $language ${role.name} $width scale$scale full labels safe inset',
            (tester) async {
              AppText.setLanguage(language, persist: false);
              tester.view.physicalSize = Size(width, 850);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              await tester.pumpRestoredPlanBillingWidget(
                MaterialApp(
                  theme: HomeMindTheme.themeData,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: const EdgeInsets.only(bottom: 24),
                    ),
                    child: child!,
                  ),
                  home: AppShell(
                    assistantService: HubFixtureService()..switchRole(role),
                    speechService: const UnavailableSpeechRecognitionService(),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final nav = find.byKey(const Key('nav_voice'));
              expect(nav, findsOneWidget);
              for (final key in [
                'nav_home',
                'nav_inventory',
                'nav_voice',
                'nav_shopping',
                'nav_profile',
              ]) {
                final button = find.byKey(Key(key));
                final label = find.descendant(
                  of: button,
                  matching: find.byType(Text),
                );
                final richLabel = find.descendant(
                  of: label,
                  matching: find.byType(RichText),
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  richLabel,
                );
                expect(
                  paragraph.didExceedMaxLines,
                  isFalse,
                  reason: '$key must display its full label',
                );
                expect(
                  tester.getRect(label).bottom,
                  lessThanOrEqualTo(tester.getRect(button).bottom),
                );
              }
              expect(
                tester.getRect(find.text(tr('Nói'))).bottom,
                lessThanOrEqualTo(826),
              );
              expect(
                tester
                    .getRect(find.byKey(const Key('nav_home')))
                    .overlaps(
                      tester.getRect(find.byKey(const Key('nav_profile'))),
                    ),
                isFalse,
              );
              expect(find.byKey(const Key('home_search')), findsOneWidget);
              expect(
                find.byKey(const Key('home_notifications')),
                findsOneWidget,
              );
              await tester.pumpRestoredPlanBillingWidget(const SizedBox());
            },
          );
        }
      }
    }
  }
  testWidgets('header real long Unicode name and capped/unknown badge', (
    tester,
  ) async {
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(
            searchHint: 'Nguyễn Đặng tên dài 🏡',
            unread: 100,
            onSearch: () {},
            onNotifications: () {},
          ),
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.textContaining('Nguyễn Đặng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'read-only pending stays idle across 60s and resume; no manual check',
    (tester) async {
      final gateway = FakeBilling()
        ..payment = {
          'id': 'owned',
          'status': 'PENDING',
          'financialState': 'UNPAID',
          'fulfillment': 'NONE',
        };
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: BillingPage(gateway: gateway, refreshEntitlements: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 65));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(gateway.reconciles, 0);
      expect(find.text('Ki\u1ec3m tra tr\u1ea1ng th\u00e1i'), findsNothing);
      expect(find.byKey(const Key('billing_countdown')), findsNothing);
      expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
    },
  );
  testWidgets(
    'support clipboard is exact and action does not open another surface',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          if (c.method == 'Clipboard.setData') {
            copied.add((c.arguments as Map)['text'] as String);
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
        const MaterialApp(home: Scaffold(body: BillingSupportCard())),
      );
      await tester.tap(find.text('Sao chép email hỗ trợ'));
      await tester.pump();
      expect(copied, ['homemind.support@gmail.com']);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'cancelled and paid-review visuals are distinct, Free is lifetime',
    (tester) async {
      expect(
        BillingStatusBadge.visual({'status': 'CANCELLED'}).color,
        HomeMindTheme.danger,
      );
      expect(
        BillingStatusBadge.visual({
          'status': 'PAID',
          'financialState': 'PAID',
          'fulfillment': 'REVIEW',
        }).color,
        isNot(HomeMindTheme.primaryStrong),
      );
      await tester.pumpRestoredPlanBillingWidget(
        const MaterialApp(
          home: Scaffold(body: BillingCurrentPlanCard(plan: 'free')),
        ),
      );
      expect(find.text('Vĩnh viễn'), findsOneWidget);
    },
  );
  testWidgets(
    'notification detail replaces list in one route and reads after render',
    (tester) async {
      final observer = _Observer(),
          detail = Completer<Map<String, Object?>>(),
          read = Completer<Map<String, Object?>>();
      int readCalls = 0, listLimit = 0;
      final gateway = HomeHubGateway(
        scope: 'owned',
        workspaceId: 'owned',
        request: (method, path) {
          if (method == 'PATCH') {
            readCalls++;
            return read.future;
          }
          if (path.contains('/notifications?')) {
            listLimit = int.parse(Uri.parse(path).queryParameters['limit']!);
            return Future.value({
              'items': [
                {
                  'id': 'n1',
                  'title': 'Thông báo thật từ fixture',
                  'body': 'Đã lưu',
                  'type': 'profile.updated',
                  'read': false,
                  'receivedAt': '2026-10-05T12:00:00Z',
                },
              ],
              'unreadCount': 1,
              'hasMore': true,
              'nextCursor': 'owned-cursor',
            });
          }
          return detail.future;
        },
      );
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  homeSurfaceRoute(
                    reducedMotion: true,
                    builder: (_) =>
                        DurableNotificationsSurface(gateway: gateway),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(listLimit, 5);
      expect(observer.pushes, 2);
      expect(readCalls, 0);
      await tester.tap(find.byKey(const Key('durable_notification_n1')));
      await tester.pump();
      expect(readCalls, 0);
      detail.complete({
        'id': 'n1',
        'title': 'Chi tiết thật',
        'detail': 'Dữ liệu durable',
        'read': false,
        'targetType': 'profile',
        'receivedAt': '2026-10-05T12:00:00Z',
        'occurredAt': '2026-10-05T11:59:00Z',
      });
      await tester.pump();
      await tester.pump();
      expect(readCalls, 1);
      expect(find.byKey(const Key('durable_notification_n1')), findsNothing);
      expect(observer.pushes, 2);
      read.complete({'unreadCount': 0});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('durable_notification_n1')), findsOneWidget);
      expect(observer.pushes, 2);
      await tester.tap(find.byKey(const Key('hub_close')));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'search debounce and late old response never replace latest query',
    (tester) async {
      final old = Completer<Map<String, Object?>>(),
          fresh = Completer<Map<String, Object?>>();
      final queries = <String>[];
      final gateway = HomeHubGateway(
        scope: 'owned',
        workspaceId: 'owned',
        request: (method, path) {
          final q = Uri.parse(path).queryParameters['q'] ?? '';
          queries.add(q);
          if (q == 'sua') return old.future;
          if (q == 'gao') return fresh.future;
          return Future.value({'items': []});
        },
      );
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: GlobalSearchSurface(gateway: gateway),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('global_search_input')), 's');
      await tester.pump(const Duration(milliseconds: 400));
      expect(queries, ['']);
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'sua',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'gao',
      );
      await tester.pump(const Duration(milliseconds: 300));
      fresh.complete({
        'items': [
          {
            'id': 'new',
            'type': 'shopping',
            'title': 'Gạo mới',
            'summary': 'needed',
          },
        ],
      });
      await tester.pump();
      old.complete({
        'items': [
          {
            'id': 'old',
            'type': 'inventory',
            'title': 'Sữa cũ',
            'summary': 'in_stock',
          },
        ],
      });
      await tester.pump();
      expect(find.text('Gạo mới'), findsOneWidget);
      expect(find.text('Sữa cũ'), findsNothing);
    },
  );
  testWidgets(
    'old pending manual verification cannot start or publish a late response',
    (tester) async {
      final gateway = _SlowCheck()
        ..payment = {
          'id': 'owned',
          'status': 'PENDING',
          'financialState': 'UNPAID',
          'fulfillment': 'NONE',
        };
      var refresh = 0;
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: BillingPage(
            gateway: gateway,
            refreshEntitlements: () async {
              refresh++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ki\u1ec3m tra tr\u1ea1ng th\u00e1i'), findsNothing);
      await tester.pump(const Duration(seconds: 26));
      gateway.completion.complete({
        'id': 'owned',
        'status': 'PAID',
        'financialState': 'PAID',
        'fulfillment': 'GRANTED',
      });
      await tester.pumpAndSettle();
      expect(gateway.reconciles, 0);
      expect(refresh, 0);
      expect(find.byKey(const Key('billing_verified')), findsNothing);
      expect(find.byKey(const Key('billing_error')), findsNothing);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    },
  );
  testWidgets(
    'checkout countdown uses monotonic elapsed and never invents server expiry',
    (tester) async {
      final elapsed = _Elapsed(), states = <bool>[];
      String? label;
      final payment = {
        'id': 'owned',
        'status': 'PENDING',
        'expiresAt': '2026-10-05T07:30:00Z',
        'serverNow': '2026-10-05T07:00:00Z',
      };
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: CheckoutWindow(
            payment: payment,
            stopwatchFactory: () => elapsed,
            builder: (context, disabled, time) {
              states.add(disabled);
              label = time;
              return Text(time ?? 'unknown');
            },
          ),
        ),
      );
      expect(label, '30:00');
      elapsed.milliseconds = 1799000;
      await tester.pump(const Duration(seconds: 1));
      expect(label, '00:01');
      elapsed.milliseconds = 1800000;
      await tester.pump(const Duration(seconds: 1));
      expect(label, '00:00');
      expect(states.last, true);
      expect(payment['status'], 'PENDING');
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('receipt clock survives delayed mount, disposal and remount', (
    tester,
  ) async {
    final elapsed = _Elapsed();
    final payment = <String, Object?>{
      'id': 'owned',
      'status': 'PENDING',
      'serverNow': '2026-10-05T07:00:00Z',
      'expiresAt': '2026-10-05T07:30:00Z',
    };
    final clock = CheckoutClock.fromPayment(
      payment,
      stopwatchFactory: () => elapsed,
    );
    Widget window() => MaterialApp(
      home: CheckoutWindow(
        payment: {...payment},
        clock: clock,
        builder: (_, disabled, time) =>
            Text('${disabled ? 'closed' : 'open'} $time'),
      ),
    );
    elapsed.milliseconds = 76000;
    await tester.pumpRestoredPlanBillingWidget(window());
    expect(find.text('open 28:44'), findsOneWidget);
    await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    expect(
      elapsed.stops,
      0,
    ); // A lazy card cannot stop the page's receipt clock.
    elapsed.milliseconds = 152000;
    await tester.pumpRestoredPlanBillingWidget(window());
    expect(find.text('open 27:28'), findsOneWidget);
    await tester.pumpRestoredPlanBillingWidget(window());
    expect(find.text('open 27:28'), findsOneWidget);
    expect(elapsed.starts, 1);
    elapsed.milliseconds = 1800000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('closed 00:00'), findsOneWidget);
    expect(payment['status'], 'PENDING');
    await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    clock.stop();
  });
  testWidgets(
    'read-only BillingPage never renders a pending payment countdown even on remount',
    (tester) async {
      final elapsed = <_Elapsed>[];
      final gateway = FakeBilling()
        ..payment = {
          'id': 'owned',
          'status': 'PENDING',
          'financialState': 'UNPAID',
          'fulfillment': 'NONE',
          'serverNow': '2026-10-05T07:00:00Z',
          'expiresAt': '2026-10-05T07:30:00Z',
        };
      Widget page() => MaterialApp(
        home: BillingPage(
          gateway: gateway,
          refreshEntitlements: () async {},
          checkoutStopwatchFactory: () {
            final watch = _Elapsed();
            elapsed.add(watch);
            return watch;
          },
        ),
      );
      await tester.pumpRestoredPlanBillingWidget(page());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 76));
      expect(elapsed, hasLength(1));
      expect(find.byKey(const Key('billing_countdown')), findsNothing);
      expect(find.text('Ki\u1ec3m tra tr\u1ea1ng th\u00e1i'), findsNothing);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      gateway.payment = {
        ...gateway.payment!,
        'serverNow': '2026-10-05T07:02:00Z',
      };
      await tester.pumpRestoredPlanBillingWidget(page());
      await tester.pumpAndSettle();
      expect(elapsed, hasLength(2));
      expect(gateway.reconciles, 0);
      expect(find.byKey(const Key('billing_countdown')), findsNothing);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    },
  );
  testWidgets(
    'checkout invalid time fails closed and changed deadline rebinds',
    (tester) async {
      final elapsed = _Elapsed();
      Widget window(Map payment) => MaterialApp(
        home: CheckoutWindow(
          payment: payment,
          stopwatchFactory: () => elapsed,
          builder: (_, closed, time) => Text('$closed ${time ?? 'unknown'}'),
        ),
      );
      final payment = {
        'id': 'owned',
        'serverNow': '2026-10-05T07:00:00Z',
        'expiresAt': '2026-10-05T07:30:00Z',
      };
      await tester.pumpRestoredPlanBillingWidget(window(payment));
      expect(find.text('false 30:00'), findsOneWidget);
      await tester.pumpRestoredPlanBillingWidget(
        window({...payment, 'expiresAt': 'invalid'}),
      );
      expect(find.text('true unknown'), findsOneWidget);
      await tester.pumpRestoredPlanBillingWidget(
        window({...payment, 'serverNow': null}),
      );
      expect(find.text('true unknown'), findsOneWidget);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'read-only historical receipt preserves exact creation timestamp without transfer details',
    (tester) async {
      final payment = {
        'id': 'owned',
        'createdAt': '2026-10-05T07:00:01Z',
        'status': 'CANCELLED',
        'amountPaid': 0,
      };
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BillingPaymentCard(
                payment: payment,
                stateText: 'Đã hủy',
                pending: false,
                checkoutEnabled: true,
                busy: false,
                onCheck: () {},
                onOpen: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('billing_transfer_details')), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(
        find.text('T\u1ea1o l\u00fac: ${billingDate(payment['createdAt'])}'),
        findsOneWidget,
      );
      expect(find.byType(ButtonStyleButton), findsNothing);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'one anchored surface fits keyboard $width text$scale and bounded preview/all windows',
        (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final limits = <int>[], observer = _Observer();
          final gateway = HomeHubGateway(
            scope: 'owner',
            workspaceId: 'owned',
            request: (m, path) async {
              final limit =
                  int.tryParse(
                    Uri.parse(path).queryParameters['limit'] ?? '',
                  ) ??
                  5;
              limits.add(limit);
              return {
                'items': List.generate(
                  limit,
                  (i) => {
                    'id': 'n$i',
                    'title': 'Thông báo dài hợp lệ $i',
                    'body': 'Thay đổi đã lưu.',
                    'type': 'profile.updated',
                    'read': false,
                    'receivedAt': '2026-10-05T07:00:00Z',
                  },
                ),
                'unreadCount': 30,
                'hasMore': true,
                'nextCursor': 'owned-next',
              };
            },
          );
          await tester.pumpRestoredPlanBillingWidget(
            MaterialApp(
              navigatorObservers: [observer],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 260),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      homeSurfaceRoute(
                        reducedMotion: true,
                        preview: true,
                        anchor: const Rect.fromLTWH(120, 50, 48, 48),
                        builder: (_) =>
                            DurableNotificationsSurface(gateway: gateway),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(limits, [5]);
          expect(observer.pushes, 2);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const Key('notifications_view_all')),
            100,
            scrollable: find.byType(Scrollable).last,
            maxScrolls: 50,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('notifications_view_all')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('notifications_view_all')));
          await tester.pumpAndSettle();
          expect(limits, [5, 20]);
          expect(observer.pushes, 2);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('hub_close')));
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
