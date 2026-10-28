import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

/// Service có trạng thái thật trong bộ nhớ: ghi rồi đọc lại phải thấy thay đổi,
/// giống backend. Mọi thao tác ghi đều được ghi vào [calls].
class _StatefulService implements AssistantService {
  @override
  Future<UserProfile> getMe() async => const UserProfile(
    userId: 'fixture-user',
    email: 'fixture@example.com',
    displayName: 'Fixture',
    workspaceId: 'fixture-workspace',
    workspaceName: 'Cửa hàng fixture',
    workspaceType: 'store',
    role: 'owner',
  );
  _StatefulService();

  final AccountRole role = AccountRole.merchant;
  final calls = <String>[];
  bool failReads = false;
  bool failWrites = false;

  final inventory = <InventoryItem>[
    const InventoryItem(
      productId: 'p1',
      name: 'Tương ớt Chinsu 250g',
      category: 'Gia vị',
      quantity: 10,
      unit: 'chai',
      expiryDate: '2026-09-28',
      expiryLevel: 'expired',
      status: 'in_stock',
    ),
    const InventoryItem(
      productId: 'p2',
      name: 'Bia Saigon',
      category: 'Nước giải khát',
      quantity: 48,
      unit: 'lon',
      expiryDate: null,
      expiryLevel: 'ok',
      status: 'in_stock',
    ),
  ];
  final shopping = <ShoppingItem>[
    const ShoppingItem(
      id: 's1',
      name: 'Muối i-ốt',
      quantity: 20,
      unit: 'gói',
      status: 'needed',
      source: 'repurchase',
    ),
  ];

  @override
  AccountRole get currentRole => role;

  @override
  Listenable get dataChanges => _dataChanges;
  final _dataChanges = ChangeNotifier();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  @override
  Future<List<InventoryItem>> getInventory() async {
    if (failReads) throw Exception('network');
    return List.of(inventory);
  }

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async {
    if (failReads) throw Exception('network');
    final outs = inventory.where((i) => i.status == 'out');
    return (
      items: List.of(shopping),
      suggestions: [
        for (final o in outs)
          if (!shopping.any((s) => s.name == o.name && s.status == 'needed'))
            {'name': o.name, 'reason': 'out', 'productId': o.productId},
      ],
    );
  }

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) async {
    if (failWrites) throw Exception('server');
    calls.add('markOut:$productId:$addToShoppingList');
    final i = inventory.indexWhere((x) => x.productId == productId);
    final old = inventory[i];
    inventory[i] = InventoryItem(
      productId: old.productId,
      name: old.name,
      category: old.category,
      quantity: 0,
      unit: old.unit,
      expiryDate: old.expiryDate,
      expiryLevel: old.expiryLevel,
      status: 'out',
    );
    if (addToShoppingList) {
      shopping.add(
        ShoppingItem(
          id: 's-$productId',
          name: old.name,
          quantity: null,
          unit: null,
          status: 'needed',
          source: 'repurchase',
        ),
      );
    }
  }

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) async {
    if (failWrites) throw Exception('server');
    calls.add('add:$name');
    shopping.add(
      ShoppingItem(
        id: 'new-${shopping.length}',
        name: name,
        quantity: quantity,
        unit: unit,
        status: 'needed',
        source: 'manual',
      ),
    );
  }

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) async {
    if (failWrites) throw Exception('server');
    calls.add(
      'receive:$itemId:${quantity?.toInt()}:$unit:${expiryDate ?? '-'}',
    );
    final i = shopping.indexWhere((x) => x.id == itemId);
    final old = shopping[i];
    shopping[i] = ShoppingItem(
      id: old.id,
      name: old.name,
      quantity: old.quantity,
      unit: old.unit,
      status: 'bought',
      source: old.source,
    );
    inventory.add(
      InventoryItem(
        productId: 'new-${old.id}',
        name: old.name,
        category: null,
        quantity: quantity,
        unit: unit,
        expiryDate: expiryDate,
        expiryLevel: 'ok',
        status: 'in_stock',
      ),
    );
  }

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) async {
    if (failWrites) throw Exception('server');
    calls.add('status:$itemId:$status');
    final i = shopping.indexWhere((x) => x.id == itemId);
    final old = shopping[i];
    shopping[i] = ShoppingItem(
      id: old.id,
      name: old.name,
      quantity: old.quantity,
      unit: old.unit,
      status: status,
      source: old.source,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) => MaterialApp(
  theme: HomeMindTheme.themeData,
  home: Scaffold(body: child),
);

void main() {
  group('Kho hàng: báo hết hàng ghi thật lên server', () {
    testWidgets(
      'chọn "Thêm vào mua sắm" thì gọi API và món biến khỏi danh sách',
      (tester) async {
        final service = _StatefulService();
        await tester.pumpWidget(_host(InventoryPage(service: service)));
        await tester.pumpAndSettle();
        expect(find.text('Tương ớt Chinsu 250g'), findsOneWidget);

        await tester.tap(find.text('Báo hết hàng').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Thêm vào danh sách cần nhập'));
        await tester.pumpAndSettle();

        expect(service.calls, ['markOut:p1:true']);
        expect(find.text('Tương ớt Chinsu 250g'), findsNothing);
        expect(find.text('Bia Saigon'), findsOneWidget);
      },
    );

    testWidgets('đóng hộp thoại mà không chọn thì không gọi API', (
      tester,
    ) async {
      final service = _StatefulService();
      await tester.pumpWidget(_host(InventoryPage(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Báo hết hàng').first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // chạm ngoài để đóng
      await tester.pumpAndSettle();

      expect(service.calls, isEmpty);
      expect(find.text('Tương ớt Chinsu 250g'), findsOneWidget);
    });

    testWidgets('server lỗi thì báo lỗi dễ hiểu và giữ nguyên danh sách', (
      tester,
    ) async {
      final service = _StatefulService()..failWrites = true;
      await tester.pumpWidget(_host(InventoryPage(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Báo hết hàng').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Không, chỉ báo hết'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa báo hết được'), findsOneWidget);
      expect(find.text('Tương ớt Chinsu 250g'), findsOneWidget);
    });

    testWidgets('không tải được thì có nút Thử lại và bấm là tải lại', (
      tester,
    ) async {
      final service = _StatefulService()..failReads = true;
      await tester.pumpWidget(_host(InventoryPage(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);

      service.failReads = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Tương ớt Chinsu 250g'), findsOneWidget);
    });

    testWidgets('bộ lọc là các nhóm lớn, chỉ hiện nhóm đang có món', (
      tester,
    ) async {
      final service = _StatefulService();
      await tester.pumpWidget(_host(InventoryPage(service: service)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gia vị (1)'), findsOneWidget);
      expect(find.textContaining('Đồ uống (1)'), findsOneWidget);
      expect(find.textContaining('Đồ dùng gia đình'), findsNothing);

      await tester.tap(find.textContaining('Đồ uống (1)'));
      await tester.pumpAndSettle();
      // Mô tả nhóm giúp người dùng biết nhóm này gồm những gì.
      expect(find.textContaining('Nước ngọt, nước suối, bia'), findsOneWidget);
      expect(find.text('Bia Saigon'), findsOneWidget);
      expect(find.text('Tương ớt Chinsu 250g'), findsNothing);
    });
  });

  group('Cần nhập / Đi chợ: thao tác ghi thật', () {
    testWidgets(
      '"Nhập vào kho" hỏi số lượng thực nhận, rồi hàng nằm trong kho thật',
      (tester) async {
        final service = _StatefulService();
        await tester.pumpWidget(_host(ShoppingPage(service: service)));
        await tester.pumpAndSettle();
        // Không còn nút/tab "Đã nhập".
        expect(find.text('Đã nhập'), findsNothing);
        expect(find.textContaining('Đã nhập ('), findsNothing);

        await tester.tap(find.text('Đã nhập hàng'));
        await tester.pumpAndSettle();
        // Khung hỏi có sẵn số lượng/đơn vị theo danh sách mua.
        expect(find.text('Xác nhận đã nhập'), findsOneWidget);
        expect(find.textContaining('tự cập nhật vào kho'), findsOneWidget);
        expect(find.widgetWithText(TextField, '20'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'gói'), findsOneWidget);

        // Thực nhận 18 gói thay vì 20.
        await tester.enterText(find.widgetWithText(TextField, '20'), '18');
        await tester.tap(find.text('Xác nhận đã nhập'));
        await tester.pumpAndSettle();

        expect(service.calls, ['receive:s1:18:gói:-']);
        expect(find.text('Muối i-ốt'), findsNothing); // rời danh sách cần nhập
        // Và có mặt trong kho (nguồn dữ liệu của tab Kho hàng).
        final stock = await service.getInventory();
        final received = stock.firstWhere((i) => i.name == 'Muối i-ốt');
        expect(received.quantity, 18);
        expect(received.unit, 'gói');
        expect(received.status, 'in_stock');
      },
    );

    testWidgets(
      'số lượng sai thì không lưu; để trống số lượng/đơn vị thì vẫn lưu',
      (tester) async {
        final service = _StatefulService();
        await tester.pumpWidget(_host(ShoppingPage(service: service)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đã nhập hàng'));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, '20'), '0');
        await tester.tap(find.text('Xác nhận đã nhập'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Số lượng chưa đúng'), findsOneWidget);
        expect(service.calls, isEmpty);

        // Xóa trống cả số lượng lẫn đơn vị: vẫn ghi nhận là đã nhập hàng.
        await tester.enterText(find.widgetWithText(TextField, '0'), '');
        await tester.enterText(find.widgetWithText(TextField, 'gói'), '');
        await tester.tap(find.text('Xác nhận đã nhập'));
        await tester.pumpAndSettle();
        expect(service.calls, ['receive:s1:null:null:-']);
      },
    );

    testWidgets('huỷ khung nhập thì không gọi API', (tester) async {
      final service = _StatefulService();
      await tester.pumpWidget(_host(ShoppingPage(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã nhập hàng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(find.text('Muối i-ốt'), findsOneWidget);
    });

    testWidgets(
      'server lỗi khi nhập kho thì báo dễ hiểu và món vẫn ở danh sách',
      (tester) async {
        final service = _StatefulService()..failWrites = true;
        await tester.pumpWidget(_host(ShoppingPage(service: service)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đã nhập hàng'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận đã nhập'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Chưa ghi được'), findsOneWidget);
        expect(find.text('Muối i-ốt'), findsOneWidget);
      },
    );

    testWidgets('"Bỏ qua" gọi API', (tester) async {
      final service = _StatefulService();
      await tester.pumpWidget(_host(ShoppingPage(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ qua').first);
      await tester.pumpAndSettle();
      expect(service.calls, ['status:s1:skipped']);
    });

    testWidgets(
      'ô thêm nhanh: gõ tên rồi bấm + thì thêm vào danh sách và xoá ô',
      (tester) async {
        final service = _StatefulService();
        await tester.pumpWidget(_host(ShoppingPage(service: service)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('shopping_quick_add')),
          '  Sả tươi  ',
        );
        await tester.tap(find.byKey(const Key('shopping_quick_add_button')));
        await tester.pumpAndSettle();
        expect(service.calls, ['add:Sả tươi']);
        expect(find.text('Sả tươi'), findsWidgets);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('shopping_quick_add')))
              .controller!
              .text,
          isEmpty,
        );
        // Ô trống thì không gọi API.
        await tester.tap(find.byKey(const Key('shopping_quick_add_button')));
        await tester.pumpAndSettle();
        expect(service.calls, ['add:Sả tươi']);
      },
    );

    testWidgets('gợi ý hàng đã hết: "Thêm" thật sự thêm vào danh sách', (
      tester,
    ) async {
      final service = _StatefulService();
      await service.markInventoryOut(productId: 'p2', addToShoppingList: false);
      service.calls.clear();
      await tester.pumpWidget(_host(ShoppingPage(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thêm').first);
      await tester.pumpAndSettle();

      expect(service.calls, ['add:Bia Saigon']);
      expect(service.shopping.any((s) => s.name == 'Bia Saigon'), isTrue);
    });

    testWidgets('lỗi mạng khi tải thì có nút Thử lại', (tester) async {
      final service = _StatefulService()..failReads = true;
      await tester.pumpWidget(_host(ShoppingPage(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);
    });
  });
}
