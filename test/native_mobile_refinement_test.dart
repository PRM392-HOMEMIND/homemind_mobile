import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/global_search_surface.dart';
import 'package:homemind_mobile/features/home/presentation/home_header.dart';
import 'package:homemind_mobile/features/home/presentation/home_section.dart';
import 'package:homemind_mobile/features/home/presentation/home_surface.dart';

void main() {
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final language in ['vi', 'en']) {
    for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets('mobile surfaces $language ${width}x$scale', (
          tester,
        ) async {
          AppText.setLanguage(language, persist: false);
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var notifications = 0, sectionOpens = 0;
          final gateway = HomeHubGateway(
            scope: 'owned',
            workspaceId: 'owned',
            request: (method, path) async => {
              'items': [
                {
                  'type': 'feature',
                  'id': 'home',
                  'title': 'Trang chủ Home',
                  'summary': '',
                },
                {
                  'type': 'feature',
                  'id': 'profile',
                  'title': 'Hồ sơ Cá nhân Profile Không gian',
                  'summary': '',
                },
              ],
            },
          );
          await tester.pumpRestoredPlanBillingWidget(
            MaterialApp(
              theme: HomeMindTheme.themeData,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          HomeHeader(
                            unread: 107,
                            onNotifications: () => notifications++,
                            onSearch: () => Navigator.of(context).push(
                              homeSearchRoute(
                                reducedMotion: true,
                                builder: (_) =>
                                    GlobalSearchSurface(gateway: gateway),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          HomeSection(
                            children: [
                              HomeSectionHeader(
                                title: tr('Danh sách cần mua'),
                                subtitle: tr(
                                  'Các món đã hết hoặc được thêm để mua lại',
                                ),
                                actionLabel: '${tr('Xem tất cả')} (12)',
                                onAction: () => sectionOpens++,
                              ),
                              const HomeEmptyState(
                                message: 'Test-owned empty state',
                                icon: Icons.shopping_basket_outlined,
                              ),
                            ],
                          ),
                          const ComingSoonCard(
                            title: 'Refund',
                            description: 'Unavailable',
                            icon: Icons.handyman_outlined,
                          ),
                          const BillingSupportCard(),
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
          expect(
            tester.getSize(find.byKey(const Key('home_notifications'))),
            const Size(48, 48),
          );
          expect(
            tester.getSize(find.byKey(const Key('home_search'))).height,
            48,
          );
          expect(find.text('99+'), findsOneWidget);
          await tester.tap(find.byKey(const Key('home_notifications')));
          expect(notifications, 1);
          await tester.ensureVisible(find.text('${tr('Xem tất cả')} (12)'));
          await tester.tap(find.text('${tr('Xem tất cả')} (12)'));
          expect(sectionOpens, 1);
          await tester.ensureVisible(find.byType(BillingSupportCard));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
          final support = find.descendant(
            of: find.byType(BillingSupportCard),
            matching: find.byType(RichText),
          );
          for (final element in support.evaluate()) {
            final render = element.renderObject;
            if (render is RenderParagraph) {
              expect(render.didExceedMaxLines, isFalse);
            }
          }
          await tester.ensureVisible(find.byKey(const Key('home_search')));
          await tester.tap(find.byKey(const Key('home_search')));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            tester.getSize(find.byKey(const Key('mobile_search_sheet'))).width,
            width,
          );
          expect(
            tester.getSize(find.byKey(const Key('mobile_search_sheet'))).height,
            greaterThan(700),
          );
          expect(find.text('Trang chủ Home'), findsNothing);
          expect(find.text(tr('Trang chủ')), findsOneWidget);
          expect(find.text(tr('Hồ sơ & Tài khoản')), findsOneWidget);
          expect(find.byIcon(Icons.home_outlined), findsOneWidget);
          expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
          final filters = tester.widget<ListView>(
            find.byKey(const Key('search_filters')),
          );
          expect(filters.scrollDirection, Axis.horizontal);
          await tester.drag(
            find.byKey(const Key('search_filters')),
            const Offset(-800, 0),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.tap(find.byKey(const Key('global_search_input')));
          await tester.pumpAndSettle();
          final field = tester.getRect(
            find.byKey(const Key('global_search_input')),
          );
          expect(field.bottom, lessThanOrEqualTo(600));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('hub_close')));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
        });
      }
    }
  }

  for (final language in ['vi', 'en']) {
    testWidgets(
      'known search metadata respects locale and user data $language',
      (tester) async {
        AppText.setLanguage(language, persist: false);
        final gateway = HomeHubGateway(
          scope: 'owned',
          workspaceId: 'owned',
          request: (method, path) async => {
            'items': [
              {
                'type': 'inventory',
                'id': 'milk',
                'title': 'Owner Milk',
                'summary': 'in_stock · Owner unit · in_stock',
              },
              {
                'type': 'shopping',
                'id': 'rice',
                'title': 'Owner Rice',
                'summary': 'Owner category · bag · needed',
              },
              {
                'type': 'plan',
                'id': 'personal',
                'title': 'Cá nhân Personal',
                'summary': 'Gói thanh toán',
              },
              {
                'type': 'profile',
                'id': 'owned-profile',
                'title': 'Owner Name',
                'summary': 'Hồ sơ · Profile',
              },
            ],
          },
        );
        await tester.pumpRestoredPlanBillingWidget(
          MaterialApp(
            home: Scaffold(body: GlobalSearchSurface(gateway: gateway)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Owner Milk'), findsOneWidget);
        expect(
          find.text(
            '${tr('Tủ đồ')} · in_stock · Owner unit · ${tr('Còn hàng')}',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            '${tr('Đi chợ')} · Owner category · bag · ${tr('Cần mua')}',
          ),
          findsOneWidget,
        );
        expect(find.text(tr('Gói Cá nhân')), findsOneWidget);
        expect(find.text('Cá nhân Personal'), findsNothing);
        expect(find.text('Owner Name'), findsOneWidget);
        expect(find.text('Hồ sơ · Profile'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'search clear, filter, cursor, retry and resolve preserve gateway contract',
    (tester) async {
      final requests = <({String method, Uri uri})>[];
      var fail = false;
      final gateway = HomeHubGateway(
        scope: 'owned',
        workspaceId: 'owned',
        request: (method, path) async {
          final uri = Uri.parse(path);
          requests.add((method: method, uri: uri));
          if (fail) {
            fail = false;
            throw StateError('Owned failure');
          }
          if (uri.path.endsWith('/resolve')) {
            return {'type': 'inventory', 'id': 'owned-item'};
          }
          final q = uri.queryParameters['q'];
          return {
            'items': q == ''
                ? []
                : [
                    {
                      'type': 'inventory',
                      'id': 'owned-item',
                      'title': 'Owner supplied Milk',
                      'summary': 'in_stock',
                    },
                  ],
            'nextCursor': q == '' ? null : 'opaque-cursor',
          };
        },
      );
      HubTarget? selected;
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push(
                    context,
                    homeSearchRoute(
                      reducedMotion: true,
                      builder: (_) => GlobalSearchSurface(gateway: gateway),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'milk',
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(requests.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(requests.last.uri.queryParameters['q'], 'milk');
      expect(find.text('Owner supplied Milk'), findsOneWidget);
      await tester.tap(find.text(tr('Trang tiếp')));
      await tester.pumpAndSettle();
      expect(requests.last.uri.queryParameters['cursor'], 'opaque-cursor');
      await tester.tap(find.byKey(const Key('search_clear')));
      await tester.pumpAndSettle();
      expect(
        requests.length,
        3,
        reason:
            'Clear uses existing shortcut state, no implicit network request',
      );
      await tester.tap(find.byKey(const Key('search_filter_inventory')));
      await tester.pumpAndSettle();
      expect(requests.last.uri.queryParameters['filter'], 'inventory');
      expect(requests.last.uri.queryParameters.containsKey('cursor'), isFalse);
      fail = true;
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'milk',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('Thử lại')));
      await tester.pumpAndSettle();
      expect(requests.last.uri.queryParameters['q'], 'milk');
      await tester.tap(
        find.byKey(const Key('search_result_inventory_owned-item')),
      );
      await tester.pumpAndSettle();
      expect(selected?.id, 'owned-item');
      expect(requests.last.uri.path, '/workspaces/owned/search/resolve');
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
}
