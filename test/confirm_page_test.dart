import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/assistant/presentation/confirm_page.dart';

class _Service implements AssistantService {
  _Service(this.role);

  final AccountRole role;
  List<ToolCall>? confirmed;
  bool cancelled = false;

  @override
  AccountRole get currentRole => role;

  @override
  Listenable get dataChanges => _dataChanges;
  final _dataChanges = ChangeNotifier();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  @override
  Future<List<InventoryItem>> getInventory() async => const [
    InventoryItem(
      productId: 'p1',
      name: 'Bánh Oreo vani 133g',
      category: 'Bánh kẹo',
      quantity: 12,
      unit: 'gói',
      expiryDate: null,
      expiryLevel: 'ok',
      status: 'in_stock',
    ),
  ];

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async {
    confirmed = tools;
    return AssistantTurn.fromJson({'kind': 'write_committed', 'message': 'ok'});
  }

  @override
  Future<AssistantTurn> cancel({required String turnId}) async {
    cancelled = true;
    return AssistantTurn.fromJson({'kind': 'cancelled'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AssistantTurn _draft(String tool, Map<String, Object?> args) =>
    AssistantTurn.fromJson({
      'turnId': 't1',
      'kind': 'write_draft',
      'correctedInput': 'bánh Oreo vừa thanh lý hết rồi',
      'toolsProposed': [
        {'toolId': tool, 'arguments': args},
      ],
    });

Future<void> _open(
  WidgetTester tester,
  _Service service,
  AssistantTurn draft,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: ConfirmPage(service: service, draft: draft),
    ),
  );
  await tester.pumpAndSettle();
}

const _markOut = {
  'productId': 'p1',
  'productName': 'Bánh Oreo vani 133g',
  'quantity': null,
  'addToShoppingList': false,
};

void main() {
  group('Bán hết / xả kho (inventory.mark_out)', () {
    testWidgets(
      'cửa hàng: dùng chữ "cần nhập", hiện số đang còn, mặc định hết toàn bộ',
      (tester) async {
        final service = _Service(AccountRole.merchant);
        await _open(tester, service, _draft('inventory.mark_out', _markOut));

        expect(find.text('Hiện còn 12 gói'), findsOneWidget);
        expect(find.text('Hết toàn bộ'), findsOneWidget);
        expect(find.text('Chỉ trừ một phần'), findsOneWidget);
        expect(find.text('Thêm vào danh sách cần nhập'), findsOneWidget);
        expect(find.textContaining('đi chợ'), findsNothing);
        // Hết toàn bộ thì không có ô nhập số lượng bỏ trống gây khó hiểu.
        expect(find.text('Số lượng đã trừ'), findsNothing);

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        final args = service.confirmed!.single.arguments;
        expect(service.confirmed!.single.toolId, 'inventory.mark_out');
        expect(args['productId'], 'p1');
        expect(args['quantity'], isNull);
        expect(args['addToShoppingList'], false);
      },
    );

    testWidgets('gia đình: vẫn dùng chữ "đi chợ"', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(tester, service, _draft('inventory.mark_out', _markOut));
      expect(find.text('Thêm vào danh sách đi chợ'), findsOneWidget);
      expect(find.textContaining('cần nhập'), findsNothing);
    });

    testWidgets(
      'chỉ trừ một phần: bắt buộc nhập số hợp lệ và không vượt quá tồn',
      (tester) async {
        final service = _Service(AccountRole.merchant);
        await _open(tester, service, _draft('inventory.mark_out', _markOut));

        await tester.tap(find.text('Chỉ trừ một phần'));
        await tester.pumpAndSettle();
        expect(find.text('Số lượng đã trừ'), findsOneWidget);

        // Chưa nhập số.
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Hãy nhập số lượng đã trừ'), findsOneWidget);
        expect(service.confirmed, isNull);

        // Nhập nhiều hơn số đang còn.
        await tester.enterText(find.byType(TextField).last, '20');
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        expect(find.textContaining('chỉ còn 12'), findsOneWidget);
        expect(service.confirmed, isNull);

        // Hợp lệ.
        await tester.enterText(find.byType(TextField).last, '5');
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        expect(service.confirmed!.single.arguments['quantity'], 5);
      },
    );

    testWidgets('AI đã nói số lượng thì mở sẵn ở chế độ một phần', (
      tester,
    ) async {
      final service = _Service(AccountRole.merchant);
      await _open(
        tester,
        service,
        _draft('inventory.mark_out', {..._markOut, 'quantity': 3}),
      );
      expect(find.text('Số lượng đã trừ'), findsOneWidget);
      expect(find.textContaining('Trừ 3'), findsOneWidget);
    });

    testWidgets('Huỷ gọi cancel và không lưu', (tester) async {
      final service = _Service(AccountRole.merchant);
      await _open(tester, service, _draft('inventory.mark_out', _markOut));
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(service.cancelled, isTrue);
      expect(service.confirmed, isNull);
    });
  });

  group('Bỏ qua món cần mua (shopping.skip)', () {
    testWidgets('hiện đúng các món, bỏ bớt một món rồi gửi đúng itemId', (
      tester,
    ) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('shopping.skip', {
          'items': [
            {'itemId': 'i1', 'name': 'ớt'},
            {'itemId': 'i2', 'name': 'chanh'},
          ],
        }),
      );
      expect(find.text('ớt'), findsWidgets);
      expect(find.text('chanh'), findsWidgets);
      expect(
        find.textContaining('Bỏ qua khỏi danh sách đi chợ'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Bỏ món này').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      final tool = service.confirmed!.single;
      expect(tool.toolId, 'shopping.skip');
      expect(tool.arguments['items'], [
        {'itemId': 'i1', 'name': 'ớt'},
      ]);
    });
  });

  group('Thêm hàng (inventory.add)', () {
    testWidgets(
      'cửa hàng: "vào kho"; chỉ cần tên, thiếu số lượng/đơn vị vẫn lưu được',
      (tester) async {
        final service = _Service(AccountRole.merchant);
        await _open(
          tester,
          service,
          _draft('inventory.add', {
            'productName': 'bia',
            'quantity': null,
            'unit': null,
          }),
        );
        expect(find.textContaining('vào kho'), findsOneWidget);
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        final args = service.confirmed!.single.arguments;
        expect(args['productName'], 'bia');
        expect(args['quantity'], isNull); // không bịa số lượng
        expect(args['unit'], isNull);
      },
    );

    testWidgets('số lượng đã nhập thì vẫn phải hợp lệ', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('inventory.add', {'productName': 'bia', 'quantity': null}),
      );
      await tester.enterText(find.byType(TextField).at(1), '0');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Số lượng chưa đúng'), findsOneWidget);
      expect(service.confirmed, isNull);
    });

    testWidgets(
      'nhiều món: mỗi món một hạn riêng, món thiếu số lượng vẫn lưu, bỏ món rồi gửi items',
      (tester) async {
        final service = _Service(AccountRole.consumer);
        await _open(
          tester,
          service,
          _draft('inventory.add', {
            'items': [
              {
                'productName': 'Sữa rửa mặt',
                'quantity': null,
                'unit': null,
                'expiryDate': '2027-09-01',
              },
              {
                'productName': 'Toner',
                'quantity': 2,
                'unit': 'chai',
                'expiryDate': '2029-01-01',
              },
              {
                'productName': 'Son dưỡng',
                'quantity': 3,
                'unit': 'cây',
                'expiryDate': '2028-06-01',
              },
            ],
          }),
        );
        expect(find.text('Món 1'), findsOneWidget);
        expect(find.text('Món 3'), findsOneWidget);
        expect(find.text('01/09/2027'), findsOneWidget);
        expect(find.text('01/01/2029'), findsOneWidget);
        expect(find.text('01/06/2028'), findsOneWidget);

        // Sữa rửa mặt chưa có số lượng/đơn vị: vẫn lưu được, và gửi null (không bịa).
        await tester.ensureVisible(find.byTooltip('Bỏ món này').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Bỏ món này').last);
        await tester.pumpAndSettle();
        expect(find.text('Món 3'), findsNothing);

        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();
        final tool = service.confirmed!.single;
        expect(tool.toolId, 'inventory.add');
        final items = (tool.arguments['items'] as List).cast<Map>();
        expect(items.map((i) => i['productName']), ['Sữa rửa mặt', 'Toner']);
        expect(items.map((i) => i['expiryDate']), ['2027-09-01', '2029-01-01']);
        expect(items.first['quantity'], isNull);
        expect(items.first['unit'], isNull);
        expect(items.last['quantity'], 2);
        expect(items.last['unit'], 'chai');
      },
    );
  });

  group('Giá và nơi cất trợ lý nghe được (inventory.add)', () {
    testWidgets('điền sẵn từ lời nói, gửi đúng khi lưu; người dùng sửa được', (
      tester,
    ) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('inventory.add', {
          'items': [
            {
              'productName': 'sữa chua',
              'quantity': 2,
              'unit': 'hộp',
              'priceVnd': 45000,
              'storageLocation': 'Tủ lạnh',
            },
            {'productName': 'gạo', 'quantity': 5, 'unit': 'kg'},
          ],
        }),
      );
      // Món có giá/nơi cất thì mở sẵn và hiện tóm tắt; món không có thì thu gọn.
      expect(find.text('45.000 ₫ · Tủ lạnh'), findsOneWidget);
      expect(find.byKey(const Key('price_field')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('price_field')), '50k');
      await tester.pump();
      await tester.ensureVisible(find.text('Lưu'));
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      final items = service.confirmed!.single.arguments['items'] as List;
      expect((items[0] as Map)['priceVnd'], 50000);
      expect((items[0] as Map)['storageLocation'], 'Tủ lạnh');
      expect((items[1] as Map).containsKey('priceVnd'), isFalse);
      expect((items[1] as Map).containsKey('storageLocation'), isFalse);
    });

    testWidgets('xóa giá đã điền sẵn thì không gửi giá lên', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('inventory.add', {
          'productName': 'thịt bò',
          'quantity': 1,
          'unit': 'ký',
          'priceVnd': 250000,
        }),
      );
      expect(find.text('250.000 ₫'), findsWidgets);
      await tester.enterText(find.byKey(const Key('price_field')), '');
      await tester.pump();
      await tester.ensureVisible(find.text('Lưu'));
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(
        service.confirmed!.single.arguments.containsKey('priceVnd'),
        isFalse,
      );
    });
  });

  group('Đặt hạn cho hàng đã có (inventory.set_expiry)', () {
    const args = {
      'productId': 'p1',
      'productName': 'Bánh Oreo vani 133g',
      'quantity': 2,
      'expiryDate': '2026-10-20',
    };

    testWidgets('hiện số đang còn, điền sẵn hạn, gửi đúng khi lưu', (
      tester,
    ) async {
      final service = _Service(AccountRole.consumer);
      await _open(tester, service, _draft('inventory.set_expiry', args));
      expect(find.text('Hiện còn 12 gói'), findsOneWidget);
      expect(find.text('20/10/2026'), findsOneWidget);
      expect(find.textContaining('Đặt hạn 20/10/2026 cho 2'), findsWidgets);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      final sent = service.confirmed!.single;
      expect(sent.toolId, 'inventory.set_expiry');
      expect(sent.arguments['productId'], 'p1');
      expect(sent.arguments['quantity'], 2);
      expect(sent.arguments['expiryDate'], '2026-10-20');
    });

    testWidgets('không cho lưu khi nhiều hơn tồn kho', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('inventory.set_expiry', {...args, 'quantity': 13}),
      );
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Trong kho chỉ còn 12'), findsOneWidget);
      expect(service.confirmed, isNull);
    });

    testWidgets('bỏ trống số lượng = áp dụng cho tất cả', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(
        tester,
        service,
        _draft('inventory.set_expiry', {...args, 'quantity': null}),
      );
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(service.confirmed!.single.arguments['quantity'], isNull);
    });
  });

  group('Nhiều việc trong một câu', () {
    testWidgets('hiện "Việc k/n" khi là một phần của câu nhiều việc', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final service = _Service(AccountRole.consumer);
      await tester.pumpWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: ConfirmPage(
            service: service,
            draft: _draft('shopping.add', {'name': 'dầu ăn'}),
            step: (index: 2, total: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Việc 2/3 trong câu bạn vừa nói'), findsOneWidget);
    });

    testWidgets('một việc thì không hiện nhãn', (tester) async {
      final service = _Service(AccountRole.consumer);
      await _open(tester, service, _draft('shopping.add', {'name': 'dầu ăn'}));
      expect(find.byKey(const Key('confirm_step')), findsNothing);
    });

    test('AssistantTurn đọc followUps của server', () {
      final turn = AssistantTurn.fromJson({
        'turnId': 't1',
        'kind': 'write_draft',
        'toolsProposed': [
          {
            'toolId': 'inventory.add',
            'arguments': {'productName': 'sữa'},
          },
        ],
        'followUps': [
          {
            'turnId': 't2',
            'kind': 'write_draft',
            'toolsProposed': [
              {
                'toolId': 'shopping.add',
                'arguments': {'name': 'dầu ăn'},
              },
            ],
          },
        ],
      });
      expect(turn.followUps.single.turnId, 't2');
      expect(turn.followUps.single.toolsProposed.single.toolId, 'shopping.add');
      expect(
        AssistantTurn.fromJson({'kind': 'write_draft'}).followUps,
        isEmpty,
      );
    });
  });
}
