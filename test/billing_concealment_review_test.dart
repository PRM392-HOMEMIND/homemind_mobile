import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/home/presentation/global_search_surface.dart';
import 'package:homemind_mobile/features/home/presentation/notifications_sheet.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/billing_concealment_scenarios.dart';
import 'support/load_app_fonts.dart';

Widget _app(Widget child, {bool visible = false}) => PlanBillingVisibility(
  visible: visible,
  child: MaterialApp(
    theme: HomeMindTheme.themeData,
    home: Scaffold(body: child),
  ),
);

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('global_search_input')), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Map<String, Object?> _searchHit(String id) => {
  'type': 'notification',
  'id': id,
  'title': 'Premium gói trà $id',
  'summary': 'Trà sắp hết hạn.',
  'rank': 0,
};

HomeHubGateway _searchGateway({
  String scope = 'actor.workspace',
  required List<Map<String, Object?>> Function(String q) hits,
  required Future<Map<String, Object?>> Function(String id) detail,
}) => HomeHubGateway(
  scope: scope,
  workspaceId: scope,
  request: (method, path) async {
    expect(method, 'GET', reason: 'Search must not acknowledge notices');
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/search')) {
      final q = uri.queryParameters['q']!;
      return {'items': q.isEmpty ? [] : hits(q), 'nextCursor': null};
    }
    return detail(uri.pathSegments.last);
  },
);

Map<String, Object?> _notice(String id, String kind, String target) => {
  'id': id,
  'type': kind,
  'title': 'Premium gói trà',
  'body': 'Trà sắp hết hạn.',
  'detail': 'Premium gói trà sắp hết hạn.',
  'targetType': target,
  'targetId': 'synthetic-item',
  'read': false,
  'receivedAt': '2026-10-19T01:00:00Z',
  'occurredAt': '2026-10-19T01:00:00Z',
};

class _ReceiveService extends ConcealmentService {
  _ReceiveService({this.failPrecheck = false});
  final bool failPrecheck;
  var receives = 0;
  @override
  Future<List<InventoryItem>> getInventory() async => [];
  @override
  Future<HomeSummary> getHomeSummary() => failPrecheck
      ? Future.error(StateError('synthetic precheck unavailable'))
      : super.getHomeSummary();
  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async => (
    items: const [
      ShoppingItem(
        id: 's1',
        name: 'Premium gói trà',
        quantity: 1,
        unit: 'gói',
        status: 'needed',
        source: 'manual',
      ),
    ],
    suggestions: <Map<String, Object?>>[],
  );
  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) async {
    receives++;
    throw const HomeMindApiException(
      'Quota changed',
      statusCode: 402,
      code: 'PLAN_LIMIT',
      details: {'plan': 'micro_pos', 'limit': 500, 'count': 500},
    );
  }
}

class _FailedAddService extends ConcealmentService {
  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) async => throw StateError('synthetic save failure');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => AppText.setLanguage('vi', persist: false));
  for (final kind in [
    'inventory.expiry',
    'inventory.add',
    'shopping.add',
    'shopping.receive',
    'expiry',
  ]) {
    test(
      'product notification $kind preserves user labels and explicit billing target still wins',
      () {
        final row = _notice('product', kind, 'inventory');
        expect(PlanBillingVisibility.isBillingRecord(row), isFalse);
        expect(
          PlanBillingVisibility.isBillingRecord({
            ...row,
            'targetType': 'billing',
          }),
          isTrue,
        );
        expect(row['title'], 'Premium gói trà');
      },
    );
  }
  testWidgets(
    'durable product notification remains visible, opens and acknowledges normally',
    (tester) async {
      var reads = 0;
      final row = _notice('product', 'inventory.expiry', 'inventory');
      final gateway = HomeHubGateway(
        scope: 'actor.workspace',
        workspaceId: 'workspace',
        request: (method, path) async {
          if (method == 'PATCH') {
            reads++;
            return {'readAt': '2026-10-19T02:00:00Z', 'unreadCount': 0};
          }
          if (path.contains('notifications?')) {
            return {
              'items': [row],
              'unreadCount': 1,
              'hasMore': false,
            };
          }
          return row;
        },
      );
      await tester.pumpWidget(
        _app(DurableNotificationsSurface(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('durable_notification_product')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('durable_notification_product')));
      await tester.pumpAndSettle();
      expect(find.text('Premium gói trà sắp hết hạn.'), findsOneWidget);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('legacy expiry notification preserves the product name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        NotificationsSheet(
          initialNotifications: const [
            AppNotification(
              id: 'legacy',
              title: 'Premium gói trà',
              body: 'Trà sắp hết hạn.',
              context: 'Kho',
              type: 'expiry',
              read: false,
            ),
          ],
          onMarkRead: (_) async {},
          onMarkAllRead: () async =>
              (items: <AppNotification>[], unreadCount: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Premium gói trà'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'search classifies notification metadata, never product words, and never acknowledges',
    (tester) async {
      var gets = 0, writes = 0;
      final hits = <Map<String, Object?>>[
        {
          'type': 'notification',
          'id': 'product',
          'title': 'Premium gói trà',
          'summary': 'Trà sắp hết hạn.',
          'rank': 0,
        },
        {
          'type': 'notification',
          'id': 'bill',
          'title': 'Đơn cũ',
          'summary': 'Đã hủy.',
          'rank': 1,
        },
        {
          'type': 'inventory',
          'id': 'item',
          'title': 'Premium gói trà trong kho',
          'summary': 'gói',
          'rank': 1,
        },
      ];
      final gateway = HomeHubGateway(
        scope: 'actor.workspace',
        workspaceId: 'workspace',
        request: (method, path) async {
          if (method != 'GET') {
            writes++;
            throw StateError('No writes in search');
          }
          if (path.contains('/search?')) {
            return {
              'items': Uri.parse(path).queryParameters['q']!.isEmpty
                  ? []
                  : hits,
              'nextCursor': null,
            };
          }
          gets++;
          return path.endsWith('/product')
              ? _notice('product', 'inventory.expiry', 'inventory')
              : _notice('bill', 'billing.cancelled', 'billing');
        },
      );
      await tester.pumpWidget(_app(GlobalSearchSurface(gateway: gateway)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'Premium',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('search_result_notification_product')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('search_result_notification_bill')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('search_result_inventory_item')),
        findsOneWidget,
      );
      expect(gets, 2);
      expect(writes, 0);
      expect(hits.first.containsKey('notificationType'), isFalse);
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'Premium gói',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        gets,
        2,
        reason: 'metadata is immutable and cached only in this scoped surface',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final failure in ['unavailable', 'wrong id', 'missing kind']) {
    testWidgets(
      'search $failure is hidden and may retry, without caching failure',
      (tester) async {
        var reads = 0;
        final gateway = _searchGateway(
          hits: (_) => [_searchHit('product')],
          detail: (id) async {
            reads++;
            final row = _notice(id, 'shopping.add', 'shopping');
            if (reads == 1) {
              if (failure == 'unavailable') {
                throw StateError('Synthetic failure');
              }
              if (failure == 'wrong id') {
                return {...row, 'id': 'another-notice'};
              }
              return {...row}..remove('type');
            }
            return row;
          },
        );
        await tester.pumpWidget(_app(GlobalSearchSurface(gateway: gateway)));
        await tester.pumpAndSettle();
        await _query(tester, 'Premium');
        expect(
          find.byKey(const Key('search_result_notification_product')),
          findsNothing,
        );
        expect(reads, 1);
        await _query(tester, 'Premium gói');
        expect(
          find.byKey(const Key('search_result_notification_product')),
          findsOneWidget,
        );
        expect(reads, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'search discards late actor results and refreshes same-id metadata on scope change',
    (tester) async {
      final oldResult = Completer<Map<String, Object?>>();
      var oldReads = 0, newReads = 0;
      final oldGateway = _searchGateway(
        scope: 'old-actor.workspace',
        hits: (_) => [_searchHit('same-id')],
        detail: (_) {
          oldReads++;
          return oldResult.future;
        },
      );
      final newGateway = _searchGateway(
        scope: 'new-actor.workspace',
        hits: (_) => [_searchHit('same-id')],
        detail: (id) async {
          newReads++;
          // Plain search text must not reveal this billing destination.
          return _notice(id, 'billing.cancelled', 'billing');
        },
      );
      await tester.pumpWidget(_app(GlobalSearchSurface(gateway: oldGateway)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'Premium',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(oldReads, 1);
      await tester.pumpWidget(_app(GlobalSearchSurface(gateway: newGateway)));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'Premium gói',
      );
      await tester.pump(const Duration(milliseconds: 400));
      oldResult.complete(_notice('same-id', 'inventory.expiry', 'inventory'));
      await tester.pumpAndSettle();
      expect(newReads, 1);
      expect(
        find.byKey(const Key('search_result_notification_same-id')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'overlapping searches share a four-read bound and discard obsolete pages',
    (tester) async {
      final pending = <String, Completer<Map<String, Object?>>>{};
      var active = 0, maximum = 0;
      final gateway = _searchGateway(
        hits: (q) =>
            List.generate(q == 'first' ? 12 : 4, (i) => _searchHit('$q-$i')),
        detail: (id) async {
          active++;
          if (active > maximum) maximum = active;
          final result = pending[id] = Completer<Map<String, Object?>>();
          try {
            return await result.future;
          } finally {
            active--;
          }
        },
      );
      await tester.pumpWidget(_app(GlobalSearchSurface(gateway: gateway)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'first',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(pending.length, 4);
      await tester.enterText(
        find.byKey(const Key('global_search_input')),
        'second',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(pending.length, 4);
      for (final e in pending.entries.toList()) {
        e.value.complete(_notice(e.key, 'inventory.expiry', 'inventory'));
      }
      await tester.pump();
      expect(
        pending.length,
        8,
        reason: 'The obsolete page must not start its remaining reads',
      );
      for (final e in pending.entries.where(
        (e) => e.key.startsWith('second'),
      )) {
        e.value.complete(_notice(e.key, 'inventory.expiry', 'inventory'));
      }
      await tester.pumpAndSettle();
      expect(maximum, 4);
      expect(active, 0);
      expect(
        find.byKey(const Key('search_result_notification_first-0')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('search_result_notification_second-0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final failed in [false, true]) {
    testWidgets(
      'hidden server Micro-POS limit after ${failed ? 'failed' : 'stale'} precheck remains neutral',
      (tester) async {
        _phoneViewport(tester);
        final service = _ReceiveService(failPrecheck: failed);
        await tester.pumpWidget(_app(ShoppingPage(service: service)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đã mua').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('receive_submit')));
        await tester.pumpAndSettle();
        expect(service.receives, 1);
        expect(
          find.text('Không thể thêm sản phẩm mới vì đã đạt giới hạn lưu trữ.'),
          findsOneWidget,
        );
        expect(find.textContaining('Micro-POS'), findsNothing);
        expect(service.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('controlled visible mode keeps the server paid-limit message', (
    tester,
  ) async {
    _phoneViewport(tester);
    final service = _ReceiveService();
    await tester.pumpWidget(
      _app(ShoppingPage(service: service), visible: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã mua').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receive_submit')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gói Micro-POS đã đủ 500 mặt hàng. Hãy liên hệ để nâng hạn mức.',
      ),
      findsOneWidget,
    );
    expect(service.receives, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'local shopping failure is not replaced by a quota message due to the product name',
    (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(_app(ShoppingPage(service: _FailedAddService())));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shopping_quick_add')),
        'Premium gói trà',
      );
      await tester.tap(find.byKey(const Key('shopping_quick_add_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa thêm được "Premium gói trà". Bạn thử lại nhé.'),
        findsOneWidget,
      );
      expect(find.text('Đã đạt hạn mức sử dụng hiện tại.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
