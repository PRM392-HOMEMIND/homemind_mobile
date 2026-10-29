import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/money.dart';
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/shopping/presentation/receive_sheet.dart';
import 'package:homemind_mobile/features/spending/presentation/price_location_fields.dart';
import 'package:homemind_mobile/features/spending/presentation/spending_card.dart';
import 'package:homemind_mobile/features/spending/presentation/spending_page.dart';

import 'support/fake_assistant_service.dart';

class _Spending extends FakeAssistantService implements SpendingSource {
  _Spending(this.summary) : super(delay: Duration.zero);

  @override
  bool get spendingAvailable => true;

  SpendingSummary summary;
  int reads = 0;
  final updates = <({String lotId, int? price, String? place})>[];

  @override
  Future<SpendingSummary> getSpending({String? month}) async {
    reads++;
    return summary;
  }

  @override
  Future<void> updateLot({
    required String lotId,
    int? priceVnd,
    String? storageLocation,
  }) async {
    updates.add((lotId: lotId, price: priceVnd, place: storageLocation));
    summary = SpendingSummary(
      month: summary.month,
      totalVnd: summary.totalVnd + (priceVnd ?? 0),
      pricedCount: summary.pricedCount + 1,
      unpricedCount: summary.unpricedCount - 1,
      previousTotalVnd: summary.previousTotalVnd,
      byCategory: summary.byCategory,
      unpriced: [
        for (final u in summary.unpriced)
          if (u.lotId != lotId) u,
      ],
    );
  }
}

SpendingSummary _october() => SpendingSummary(
  month: currentSpendingMonth(),
  totalVnd: 1250000,
  pricedCount: 5,
  unpricedCount: 2,
  previousTotalVnd: 1000000,
  byCategory: const [
    (category: 'Thịt cá', totalVnd: 900000),
    (category: null, totalVnd: 350000),
  ],
  unpriced: [
    UnpricedPurchase(
      lotId: 'lot-1',
      productId: 'p-1',
      name: 'Sữa tươi',
      purchasedAt: DateTime(2026, 10, 3),
      storageLocation: 'Tủ lạnh',
    ),
    UnpricedPurchase(
      lotId: 'lot-2',
      productId: 'p-2',
      name: 'Gạo ST25',
      purchasedAt: DateTime(2026, 10, 5),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      // Khóa mới mỗi lần để State không bị dùng lại giữa hai lần dựng trong cùng một test.
      home: KeyedSubtree(key: UniqueKey(), child: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('tiền', () {
    test('định dạng VND', () {
      expect(formatVnd(0), '0 ₫');
      expect(formatVnd(999), '999 ₫');
      expect(formatVnd(1000), '1.000 ₫');
      expect(formatVnd(1250000), '1.250.000 ₫');
      expect(formatVnd(-45000), '-45.000 ₫');
    });

    test('đọc số tiền người dùng gõ', () {
      expect(parseVnd('45000'), 45000);
      expect(parseVnd('45.000'), 45000);
      expect(parseVnd('1.250.000 ₫'), 1250000);
      expect(parseVnd('45k'), 45000);
      expect(parseVnd('45K'), 45000);
      expect(parseVnd('1,5tr'), 1500000);
      expect(parseVnd('1.2 triệu'), 1200000);
      expect(parseVnd('0'), 0);
    });

    test('từ chối chuỗi không phải tiền', () {
      for (final bad in ['', '  ', 'abc', '12,34', '1.2.3', '-5', 'k', '1e5']) {
        expect(parseVnd(bad), isNull, reason: bad);
      }
      expect(parseVnd('999999999999'), isNull); // vượt trần 100 tỷ
    });
  });

  group('SpendingSummary', () {
    test('đọc JSON của server, chịu được thiếu trường', () {
      final s = SpendingSummary.fromJson({
        'month': '2026-10',
        'totalVnd': 1250000,
        'pricedCount': 5,
        'unpricedCount': 1,
        'previousTotalVnd': 0,
        'byCategory': [
          {'category': null, 'totalVnd': 1250000},
        ],
        'unpriced': [
          {
            'lotId': 'l',
            'productId': 'p',
            'name': 'Sữa',
            'purchasedAt': '2026-10-03T03:00:00.000Z',
            'storageLocation': null,
          },
        ],
      });
      expect(s.totalVnd, 1250000);
      expect(s.byCategory.single.category, isNull);
      expect(s.unpriced.single.name, 'Sữa');
      expect(SpendingSummary.fromJson(const {}).isEmpty, isTrue);
    });

    test('so với tháng trước chỉ có khi cả hai tháng có số liệu', () {
      expect(spendingDelta(_october())!.up, isTrue);
      expect(spendingDelta(_october())!.text, contains('25%'));
      final none = SpendingSummary.fromJson(const {'totalVnd': 100});
      expect(spendingDelta(none), isNull);
    });

    test('tháng hiện tại theo giờ Việt Nam và chuyển tháng', () {
      // 23:30 UTC ngày 30/09 đã là 06:30 ngày 01/10 ở Việt Nam.
      expect(
        currentSpendingMonth(DateTime.utc(2026, 9, 30, 23, 30)),
        '2026-10',
      );
      expect(
        currentSpendingMonth(DateTime.utc(2026, 12, 31, 16, 59)),
        '2026-12',
      );
      expect(
        currentSpendingMonth(DateTime.utc(2026, 12, 31, 17, 0)),
        '2027-01',
      );
    });
  });

  group('PriceLocationFields', () {
    testWidgets('gợi ý đơn giá, chọn nơi cất và xuất đúng tham số', (
      tester,
    ) async {
      final c = PriceLocationController();
      addTearDown(c.dispose);
      await _pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: PriceLocationFields(
                controller: c,
                quantity: 2,
                unit: 'hộp',
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      expect(c.toArguments(), isEmpty); // không nhập gì thì không gửi gì

      await tester.enterText(find.byKey(const Key('price_field')), '45k');
      await tester.pump();
      expect(find.textContaining('22.500'), findsOneWidget); // ≈ / hộp
      await tester.tap(find.text('Tủ lạnh'));
      await tester.pump();
      expect(c.toArguments(), {
        'priceVnd': 45000,
        'storageLocation': 'Tủ lạnh',
      });

      await tester.enterText(find.byKey(const Key('price_field')), 'abc');
      await tester.pump();
      expect(c.priceInvalid, isTrue);
      expect(find.text('Chưa đọc được số tiền'), findsOneWidget);
    });

    testWidgets('thu gọn mặc định và hiện tóm tắt khi đã có dữ liệu', (
      tester,
    ) async {
      final c = PriceLocationController(location: 'Kệ khô');
      addTearDown(c.dispose);
      await _pump(tester, Scaffold(body: PriceLocationFields(controller: c)));
      // Đã có nơi cất thì tự mở.
      expect(find.byKey(const Key('price_field')), findsOneWidget);
      final empty = PriceLocationController();
      addTearDown(empty.dispose);
      await _pump(
        tester,
        Scaffold(body: PriceLocationFields(controller: empty)),
      );
      expect(find.byKey(const Key('price_field')), findsNothing);
      expect(find.text('Không bắt buộc'), findsOneWidget);
    });
  });

  group('ReceiveSheet', () {
    testWidgets('trả về giá và nơi cất khi nhập, và bỏ qua khi để trống', (
      tester,
    ) async {
      ReceiveResult? result;
      Future<void> open({String? place}) async {
        await _pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async => result = await ReceiveSheet.show(
                    context,
                    item: const ShoppingItem(
                      id: 's1',
                      name: 'Sữa tươi',
                      quantity: 2,
                      unit: 'hộp',
                      status: 'needed',
                      source: 'manual',
                    ),
                    merchant: false,
                    initialLocation: place,
                  ),
                  child: const Text('mở'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('mở'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(find.byKey(const Key('price_field')), '45k');
      await tester.pump();
      await tester.tap(find.text('Tủ lạnh'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('receive_submit')));
      await tester.tap(find.byKey(const Key('receive_submit')));
      await tester.pumpAndSettle();
      expect(result!.priceVnd, 45000);
      expect(result!.storageLocation, 'Tủ lạnh');
      expect(result!.quantity, 2);

      result = null;
      await open(place: 'Kệ khô'); // điền sẵn nơi cất của món đã có trong kho
      await tester.ensureVisible(find.byKey(const Key('receive_submit')));
      await tester.tap(find.byKey(const Key('receive_submit')));
      await tester.pumpAndSettle();
      expect(result!.priceVnd, isNull); // giá là tùy chọn
      expect(result!.storageLocation, 'Kệ khô');
    });

    testWidgets('số tiền không đọc được thì chặn lại và báo rõ', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(
          body: ReceiveSheet(
            item: ShoppingItem(
              id: 's1',
              name: 'Sữa tươi',
              quantity: 1,
              unit: 'hộp',
              status: 'needed',
              source: 'manual',
            ),
            merchant: false,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('price_field')), 'abc');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('receive_submit')));
      await tester.tap(find.byKey(const Key('receive_submit')));
      await tester.pump();
      expect(find.textContaining('Chưa đọc được số tiền'), findsWidgets);
    });
  });

  group('SpendingPage', () {
    testWidgets('hiện tổng, cảnh báo thiếu giá và nhập giá ngay tại chỗ', (
      tester,
    ) async {
      final service = _Spending(_october());
      await _pump(
        tester,
        SpendingPage(service: service, source: service, merchant: false),
      );
      expect(find.text('1.250.000 ₫'), findsWidgets);
      expect(find.textContaining('2 lần mua chưa có giá'), findsOneWidget);
      expect(find.text('Sữa tươi'), findsOneWidget);
      expect(find.text('Gạo ST25'), findsOneWidget);

      await tester.tap(find.byKey(const Key('enter_price_lot-1')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('price_entry_save'));
      expect(
        tester.widget<ElevatedButton>(save).onPressed,
        isNull,
      ); // chưa có số
      await tester.enterText(find.byKey(const Key('price_field')), '45000');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(service.updates, [(lotId: 'lot-1', price: 45000, place: null)]);
      expect(find.text('Sữa tươi'), findsNothing);
      expect(find.text('1.295.000 ₫'), findsWidgets);
      expect(find.textContaining('1 lần mua chưa có giá'), findsOneWidget);
    });

    testWidgets(
      'không cho sang tháng tương lai; tháng trước đọc lại từ server',
      (tester) async {
        final service = _Spending(_october());
        await _pump(
          tester,
          SpendingPage(service: service, source: service, merchant: false),
        );
        final next = tester.widget<IconButton>(
          find.byKey(const Key('spending_next_month')),
        );
        expect(next.onPressed, isNull);
        final readsBefore = service.reads;
        await tester.tap(find.byKey(const Key('spending_prev_month')));
        await tester.pumpAndSettle();
        expect(service.reads, readsBefore + 1);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('spending_next_month')))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('tháng chưa có lần mua nào thì nói rõ, không hiện tổng giả', (
      tester,
    ) async {
      final service = _Spending(
        SpendingSummary.fromJson({'month': currentSpendingMonth()}),
      );
      await _pump(
        tester,
        SpendingPage(service: service, source: service, merchant: true),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('Chưa có lần mua nào'), findsOneWidget);
    });
  });

  group('SpendingCard', () {
    testWidgets('ẩn khi tháng này chưa có lần mua; hiện khi có', (
      tester,
    ) async {
      final empty = _Spending(SpendingSummary.fromJson(const {}));
      await _pump(
        tester,
        Scaffold(body: SpendingCard(service: empty, merchant: false)),
      );
      expect(find.byKey(const Key('spending_card')), findsNothing);

      final data = _Spending(_october());
      await _pump(
        tester,
        Scaffold(body: SpendingCard(service: data, merchant: false)),
      );
      expect(find.byKey(const Key('spending_card')), findsOneWidget);
      expect(find.text('1.250.000 ₫'), findsOneWidget);
      expect(find.textContaining('chưa có giá'), findsOneWidget);
    });

    test('dịch vụ giả lập không hỗ trợ chi tiêu thì thẻ tự ẩn', () {
      expect(SpendingCard.supported(FakeAssistantService()), isFalse);
      // Bản bọc đệm quanh dịch vụ không có chi tiêu cũng phải báo là không hỗ trợ.
      expect(
        SpendingCard.supported(CachedAssistantService(FakeAssistantService())),
        isFalse,
      );
      expect(SpendingCard.supported(_Spending(_october())), isTrue);
    });
  });

  group('CachedAssistantService chi tiêu', () {
    test('đệm kết quả, và xóa đệm sau mỗi lần ghi', () async {
      final inner = _Spending(_october());
      final cache = CachedAssistantService(inner);
      addTearDown(cache.dispose);

      await cache.getSpending();
      await cache.getSpending();
      expect(inner.reads, 1);

      await cache.receiveShoppingItem(
        itemId: 'x',
        quantity: 1,
        unit: 'hộp',
        priceVnd: 1000,
      );
      await cache.getSpending(); // chờ hàng đợi ghi xong rồi đọc lại
      expect(inner.reads, 2);

      await cache.updateLot(lotId: 'lot-2', priceVnd: 30000);
      expect(inner.updates.single.lotId, 'lot-2');
      await cache.getSpending();
      expect(inner.reads, 3);
    });

    test('đọc thông báo không làm mất đệm chi tiêu', () async {
      final inner = _Spending(_october());
      final cache = CachedAssistantService(inner);
      addTearDown(cache.dispose);
      await cache.getSpending();
      await cache.markNotificationRead('n1');
      await cache.getSpending();
      expect(inner.reads, 1);
    });

    test('hai nơi hỏi cùng lúc chỉ tốn một request', () async {
      final inner = _Spending(_october());
      final cache = CachedAssistantService(inner);
      addTearDown(cache.dispose);
      await Future.wait([cache.getSpending(), cache.getSpending()]);
      expect(inner.reads, 1);
    });
  });
}
