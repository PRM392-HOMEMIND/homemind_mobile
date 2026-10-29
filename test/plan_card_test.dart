import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/plan_card.dart';

import 'support/recording_plan_service.dart';

Future<RecordingPlanService> _pump(
  WidgetTester tester, {
  String plan = 'free',
  int used = 10,
  int limit = 30,
  List<String> requested = const [],
  AccountRole role = AccountRole.consumer,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final service = RecordingPlanService(
    plan: plan,
    used: used,
    limit: limit,
    requested: requested,
    initialRole: role,
  );
  final home = await service.getHomeSummary();
  await tester.pumpRestoredPlanBillingWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: PlanCard(
            home: home,
            service: service,
            isMerchant: role == AccountRole.merchant,
          ),
        ),
      ),
    ),
  );
  return service;
}

Color _barColor(WidgetTester tester) {
  final bar = tester.widget<LinearProgressIndicator>(
    find.byKey(const Key('plan_card_progress')),
  );
  return (bar.valueColor! as AlwaysStoppedAnimation<Color>).value;
}

void main() {
  testWidgets('10/30: xanh, nút Xem các gói (outlined)', (tester) async {
    await _pump(tester, used: 10);
    expect(find.text('Gói Miễn phí · 10/30 sản phẩm'), findsOneWidget);
    expect(find.text('Còn 20 chỗ trống trong gói hiện tại.'), findsOneWidget);
    expect(_barColor(tester), HomeMindTheme.primary);
    expect(
      find.widgetWithText(OutlinedButton, 'Xem gói hiện tại'),
      findsOneWidget,
    );
    expect(find.textContaining('123.000đ/tháng'), findsOneWidget);
  });

  testWidgets('24/30: hổ phách, nút vàng Nâng cấp từ 29.000đ / 30 ngày', (
    tester,
  ) async {
    await _pump(tester, used: 24);
    expect(find.text('Sắp đầy! Chỉ còn 6 chỗ trống'), findsOneWidget);
    expect(_barColor(tester), HomeMindTheme.warning);
    expect(
      find.widgetWithText(ElevatedButton, 'Xem gói hiện tại'),
      findsOneWidget,
    );
  });

  testWidgets('30/30: đỏ, đã đầy', (tester) async {
    await _pump(tester, used: 30);
    expect(
      find.text('Đã đầy 30/30 sản phẩm — không thể thêm sản phẩm mới'),
      findsOneWidget,
    );
    expect(_barColor(tester), HomeMindTheme.danger);
    expect(
      find.widgetWithText(ElevatedButton, 'Xem gói hiện tại'),
      findsOneWidget,
    );
  });

  testWidgets('chạm nút mở bảng chọn gói', (tester) async {
    await _pump(tester, used: 24);
    await tester.tap(find.byKey(const Key('plan_card_cta')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
      findsOneWidget,
    );
  });

  testWidgets('đã có yêu cầu nâng cấp: ẩn CTA, hiện xác nhận + Đổi gói', (
    tester,
  ) async {
    await _pump(tester, used: 28, requested: ['personal']);
    expect(find.byKey(const Key('plan_card_cta')), findsOneWidget);
    expect(find.byKey(const Key('plan_card_change')), findsNothing);
    expect(find.textContaining('Chúng tôi sẽ liên hệ'), findsNothing);
    await tester.tap(find.byKey(const Key('plan_card_cta')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Thanh toán gói hiện chưa được hỗ trợ'),
      findsOneWidget,
    );
  });

  testWidgets('gói trả phí: thẻ yên lặng, không bán thêm', (tester) async {
    await _pump(tester, plan: 'family', used: 42);
    expect(
      find.text('Gói Gia đình · 42 sản phẩm — không giới hạn'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('plan_card_cta')), findsNothing);
    expect(find.text('Nâng lên Gia đình'), findsNothing);
    expect(find.textContaining('123.000đ'), findsNothing);
  });

  testWidgets('gói Cá nhân có liên kết Nâng lên Gia đình', (tester) async {
    await _pump(tester, plan: 'personal', used: 50);
    expect(
      find.text('Gói Cá nhân · 50 sản phẩm — không giới hạn'),
      findsOneWidget,
    );
    expect(find.text('Nâng lên Gia đình'), findsNothing);
  });

  testWidgets('cửa hàng gói free: mặt hàng + Micro-POS 149.000đ', (
    tester,
  ) async {
    await _pump(tester, used: 400, limit: 500, role: AccountRole.merchant);
    expect(find.text('Sắp đầy! Chỉ còn 100 chỗ trống'), findsOneWidget);
    expect(find.text('Gói Miễn phí · 400/500 mặt hàng'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Xem gói hiện tại'),
      findsOneWidget,
    );
  });

  testWidgets('cửa hàng gói Micro-POS: n/limit mặt hàng, không bán thêm', (
    tester,
  ) async {
    await _pump(
      tester,
      plan: 'micro_pos',
      used: 128,
      limit: 500,
      role: AccountRole.merchant,
    );
    expect(find.text('Gói Micro-POS · 128/500 mặt hàng'), findsOneWidget);
    expect(find.byKey(const Key('plan_card_cta')), findsNothing);
  });
}
