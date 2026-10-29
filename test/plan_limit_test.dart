import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/presentation/confirm_page.dart';
import 'package:homemind_mobile/features/home/presentation/plan_catalog.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/recording_plan_service.dart';

HomeSummary _home(String plan, int used, int limit) => HomeSummary(
  totalProducts: used,
  inStockCount: used,
  outCount: 0,
  expiredCount: 0,
  expiringSoonCount: 0,
  shoppingNeededCount: 0,
  freePlanLimit: limit,
  productCountTowardLimit: used,
  expiringSoon: const [],
  expired: const [],
  alerts: const [],
  plan: plan,
);

InventoryItem _inv(String name) => InventoryItem(
  productId: name,
  name: name,
  category: null,
  quantity: 1,
  unit: 'gói',
  expiryDate: null,
  expiryLevel: 'ok',
  status: 'in_stock',
);

class _Service extends RecordingPlanService {
  _Service({super.plan, super.used, super.limit});

  List<InventoryItem> inventory = [_inv('Sữa Vinamilk')];
  List<ToolCall>? confirmed;
  Object? confirmError;
  final received = <String>[];

  @override
  Future<List<InventoryItem>> getInventory() async => inventory;

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async {
    confirmed = tools;
    if (confirmError != null) throw confirmError!;
    return AssistantTurn.fromJson({'kind': 'write_committed', 'message': 'ok'});
  }

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async => (
    items: const [
      ShoppingItem(
        id: 's1',
        name: 'Bột giặt',
        quantity: 1,
        unit: 'túi',
        status: 'needed',
        source: 'manual',
      ),
    ],
    suggestions: const <Map<String, Object?>>[],
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
    received.add(itemId);
    if (confirmError != null) throw confirmError!;
  }
}

AssistantTurn _draft(String name) => AssistantTurn.fromJson({
  'turnId': 't1',
  'kind': 'write_draft',
  'toolsProposed': [
    {
      'toolId': 'inventory.add',
      'arguments': {'productName': name, 'quantity': 2, 'unit': 'gói'},
    },
  ],
});

Future<void> _openConfirm(WidgetTester tester, _Service s, String name) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpRestoredPlanBillingWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: ConfirmPage(service: s, draft: _draft(name)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PlanGate', () {
    final inv = [_inv('Sữa Vinamilk')];
    PlanGateResult check(HomeSummary h, String n) =>
        PlanGate.checkAddProduct(home: h, inventory: inv, productName: n);

    test('free 29/30 cho phép', () {
      expect(check(_home('free', 29, 30), 'Gạo'), PlanGateResult.allowed);
    });
    test('free 30/30 tên mới bị chặn', () {
      expect(check(_home('free', 30, 30), 'Gạo'), PlanGateResult.blockedFree);
    });
    test('free 30/30 tên đã có (không phân biệt hoa thường/khoảng trắng)', () {
      expect(
        check(_home('free', 30, 30), '  sữa vinamilk '),
        PlanGateResult.allowed,
      );
    });
    test('micro_pos 500/500 bị chặn kiểu hạn mức trả phí', () {
      expect(
        check(_home('micro_pos', 500, 500), 'Gạo'),
        PlanGateResult.blockedPaidLimit,
      );
    });
    test('personal/family không bao giờ bị chặn', () {
      expect(check(_home('personal', 999, 30), 'Gạo'), PlanGateResult.allowed);
      expect(check(_home('family', 999, 30), 'Gạo'), PlanGateResult.allowed);
    });
  });

  group('ConfirmPage chặn thêm món mới', () {
    testWidgets('bị chặn: banner + nút Nâng cấp để thêm, không gọi confirm', (
      tester,
    ) async {
      final s = _Service(used: 30);
      await _openConfirm(tester, s, 'Gạo ST25');
      expect(
        find.text(
          'Gói Miễn phí đã đủ 30 sản phẩm. Nâng cấp để thêm sản phẩm mới.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lưu'), findsNothing);
      await tester.tap(find.text('Xem gói hiện tại'));
      await tester.pumpAndSettle();
      expect(s.confirmed, isNull);
      expect(
        find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
        findsOneWidget,
      );
    });

    testWidgets('sửa tên thành món đã có thì Lưu lại được', (tester) async {
      final s = _Service(used: 30);
      await _openConfirm(tester, s, 'Gạo ST25');
      await tester.enterText(
        find.widgetWithText(TextField, 'Gạo ST25'),
        'sữa vinamilk',
      );
      await tester.pumpAndSettle();
      expect(find.text('Xem gói hiện tại'), findsNothing);
      expect(find.byKey(const Key('confirm_plan_banner')), findsNothing);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(s.confirmed, isNotNull);
    });

    testWidgets('gói trả phí đủ hạn mức: nút vô hiệu', (tester) async {
      final s = _Service(plan: 'micro_pos', used: 500, limit: 500);
      await _openConfirm(tester, s, 'Gạo ST25');
      expect(
        find.text(
          'Gói Micro-POS đã đủ 500 mặt hàng. Hãy liên hệ để nâng hạn mức.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Đã đủ hạn mức'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('server trả PLAN_LIMIT: hiện trạng thái chặn, mở paywall', (
      tester,
    ) async {
      final s = _Service(used: 10)
        ..confirmError = const HomeMindApiException(
          'x',
          statusCode: 402,
          code: 'PLAN_LIMIT',
          details: {'plan': 'free', 'limit': 30, 'count': 30},
        );
      await _openConfirm(tester, s, 'Gạo ST25');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa lưu được. Bạn bấm Thử lại nhé.'), findsNothing);
      expect(
        find.text(
          'Gói Miễn phí đã đủ 30 sản phẩm. Nâng cấp để thêm sản phẩm mới.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
        findsOneWidget,
      );
    });
  });

  group('ShoppingPage nhận hàng', () {
    Future<void> pump(WidgetTester tester, _Service s) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(body: ShoppingPage(service: s)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('free đầy + món mới: mở paywall, không gửi', (tester) async {
      final s = _Service(used: 30);
      await pump(tester, s);
      await tester.tap(find.text('Đã mua').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
        findsOneWidget,
      );
      expect(s.received, isEmpty);
    });

    testWidgets(
      'server quota after preflight opens paywall and keeps failure visible',
      (tester) async {
        final s = _Service(used: 10)
          ..confirmError = const HomeMindApiException(
            'Quota changed',
            statusCode: 402,
            code: 'PLAN_LIMIT',
            details: {'plan': 'free', 'limit': 30, 'count': 30},
          );
        await pump(tester, s);
        await tester.tap(find.text('Đã mua').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('receive_submit')));
        await tester.pumpAndSettle();
        expect(s.received, ['s1']);
        expect(
          find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
          findsOneWidget,
        );
        expect(
          find.text('Chưa ghi được "Bột giặt". Bạn thử lại nhé.'),
          findsNothing,
        );
      },
    );

    testWidgets('micro_pos đầy: SnackBar, không gửi', (tester) async {
      final s = _Service(plan: 'micro_pos', used: 500, limit: 500);
      await pump(tester, s);
      await tester.tap(find.text('Đã mua').first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Gói Micro-POS đã đủ 500 mặt hàng. Hãy liên hệ để nâng hạn mức.',
        ),
        findsOneWidget,
      );
      expect(s.received, isEmpty);
    });
  });
}
