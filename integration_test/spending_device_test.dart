import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/main.dart' as app;

import 'full_system_test.dart' as fixture;

// Chạy trên máy thật với backend local (adb reverse tcp:3000):
//   flutter test integration_test/spending_device_test.dart -d <device> \
//     --dart-define-from-file=config/development.json
// Tạo một tài khoản dùng một lần, kiểm tra tính năng giá/nơi cất/chi tiêu qua giao diện
// thật rồi xóa tài khoản.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  fixture.nativeTest('SPEND-01 giá, nơi cất, chi tiêu tháng và thông báo', (
    tester,
  ) async {
    final results = <String, Object?>{};
    void pass(String id, [Object? detail]) {
      results[id] = detail ?? 'PASS';
      debugPrint('SPEND_RESULT $id ${detail ?? 'PASS'}');
    }

    // ── Dữ liệu nền qua API ─────────────────────────────────────────────
    final email = 'spend+${fixture.nonce().substring(0, 16)}@example.com';
    final password = fixture.nonce();
    final session = await fixture.request('/auth/register', 'POST', {
      'acceptedTerms': true,
      'acceptedPrivacy': true,
      'displayName': 'Spend E2E',
      'email': email,
      'password': password,
      'workspaceType': 'household',
    });
    final token = session['accessToken'] as String;
    final me = await fixture.request('/me', 'GET', null, token);
    final ws = me['workspaceId'] as String;
    Future<Map<String, dynamic>> spending([String q = '']) =>
        fixture.request('/workspaces/$ws/spending$q', 'GET', null, token);

    expect((await spending())['totalVnd'], 0); // chưa có gì
    await fixture.request('/workspaces/$ws/inventory/items', 'POST', {
      'productName': 'Sữa test',
      'quantity': 2,
      'unit': 'hộp',
      'priceVnd': 45000,
      'storageLocation': 'Tủ lạnh',
    }, token);
    await fixture.request('/workspaces/$ws/inventory/items', 'POST', {
      'productName': 'Gạo test',
      'quantity': 5,
      'unit': 'kg',
    }, token);
    await fixture.request('/workspaces/$ws/shopping-items', 'POST', {
      'name': 'Cà chua test',
      'quantity': 1,
      'unit': 'kg',
    }, token);
    var s = await spending();
    expect(
      [s['totalVnd'], s['pricedCount'], s['unpricedCount']],
      [45000, 1, 1],
    );
    pass('API-01 giá/nơi cất lưu đúng, lô chưa giá được đếm');

    // Giá sai bị server từ chối.
    var rejected = false;
    try {
      await fixture.request('/workspaces/$ws/inventory/items', 'POST', {
        'productName': 'Hỏng',
        'quantity': 1,
        'unit': 'cái',
        'priceVnd': -5,
      }, token);
    } on StateError {
      rejected = true;
    }
    expect(rejected, isTrue);
    pass('API-02 giá âm bị từ chối');

    // ── Đăng nhập trên máy ──────────────────────────────────────────────
    await tester.pumpWidget(const SizedBox.shrink());
    await app.main();
    await fixture.waitFor(tester, find.text('Bỏ qua'));
    await fixture.tap(tester, find.text('Bỏ qua'));
    await fixture.waitFor(tester, find.byKey(const Key('login_identifier')));
    await fixture.fill(tester, 'login_identifier', email);
    await fixture.fill(tester, 'login_password', password);
    await fixture.dismissKeyboard(tester);
    await fixture.tap(tester, find.byKey(const Key('login_submit')));
    await fixture.waitFor(tester, find.byKey(const Key('nav_home')));

    // ── UI-01: thẻ chi tiêu trên trang chủ ──────────────────────────────
    final card = find.byKey(const Key('spending_card'));
    await fixture.waitForScrolled(tester, card, find.byType(ListView).first);
    expect(
      find.descendant(of: card, matching: find.text('45.000 ₫')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('1 lần mua chưa có giá'),
      ),
      findsOneWidget,
    );
    pass('UI-01 thẻ chi tiêu: 45.000 ₫ và cảnh báo 1 lần mua chưa có giá');

    // ── UI-02: nơi cất hiện ở kho ───────────────────────────────────────
    await fixture.tap(tester, find.byKey(const Key('nav_inventory')));
    await fixture.waitFor(tester, find.text('📍 Tủ lạnh'));
    pass('UI-02 kho hiện 📍 Tủ lạnh cho Sữa test');

    // ── UI-03: nhận hàng với giá sai bị chặn ────────────────────────────
    await fixture.tap(tester, find.byKey(const Key('nav_shopping')));
    await fixture.waitFor(tester, find.text('Cà chua test'));
    await fixture.tap(tester, find.text('Đã mua').first);
    await fixture.waitFor(tester, find.byKey(const Key('price_field')));
    await tester.enterText(find.byKey(const Key('price_field')), 'abc');
    await tester.pump();
    await fixture.tap(tester, find.byKey(const Key('receive_submit')));
    expect(find.textContaining('Chưa đọc được số tiền'), findsWidgets);
    expect(find.byKey(const Key('receive_submit')), findsOneWidget); // vẫn mở
    expect((await spending())['totalVnd'], 45000); // chưa ghi gì
    pass('UI-03 giá không đọc được thì chặn, không ghi');

    // ── UI-04: nhận hàng với giá 30k + nơi cất ──────────────────────────
    await tester.enterText(find.byKey(const Key('price_field')), '30k');
    await tester.pump();
    await fixture.tap(tester, find.text('Kệ khô'));
    await fixture.tap(tester, find.byKey(const Key('receive_submit')));
    final afterReceive = await fixture.persisted(
      tester,
      {'accessToken': token, 'ws': ws},
      '/workspaces/$ws/spending',
      (d) => d['totalVnd'] == 75000,
    );
    expect(afterReceive['pricedCount'], 2);
    expect(afterReceive['unpricedCount'], 1);
    pass('UI-04 nhận hàng 30k + Kệ khô: tổng 75.000 ₫');

    String? totalText() {
      final f = find.byKey(const Key('spending_total'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    // ── UI-05: mở trang chi tiêu, nhập giá bù ───────────────────────────
    await fixture.tap(tester, find.byKey(const Key('nav_home')));
    await fixture.waitForScrolled(tester, card, find.byType(ListView).first);
    await fixture.waitFor(
      tester,
      find.descendant(of: card, matching: find.text('75.000 ₫')),
    );
    pass('UI-05a thẻ trang chủ tự cập nhật sau khi nhận hàng: 75.000 ₫');
    await fixture.tap(tester, card);
    await fixture.waitFor(tester, find.byKey(const Key('spending_total')));
    expect(totalText(), '75.000 ₫');
    expect(find.textContaining('1 lần mua chưa có giá'), findsWidgets);
    expect(find.text('Gạo test'), findsOneWidget);
    expect(find.text('Sữa test'), findsNothing); // Sữa đã có giá
    pass('UI-05b trang chi tiêu: tổng 75.000 ₫, chỉ Gạo test chưa có giá');

    final unpriced = (await spending())['unpriced'] as List;
    final lotId = (unpriced.single as Map)['lotId'] as String;
    await fixture.tap(tester, find.byKey(Key('enter_price_$lotId')));
    await fixture.waitFor(tester, find.byKey(const Key('price_entry_save')));
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('price_entry_save')))
          .onPressed,
      isNull,
    ); // chưa có số thì Lưu bị tắt
    await tester.enterText(find.byKey(const Key('price_field')), '100.000');
    await tester.pump();
    await fixture.tap(tester, find.byKey(const Key('price_entry_save')));
    for (var i = 0; i < 50 && totalText() != '175.000 ₫'; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(totalText(), '175.000 ₫');
    expect(find.text('Gạo test'), findsNothing);
    final done = await fixture.persisted(
      tester,
      {'accessToken': token, 'ws': ws},
      '/workspaces/$ws/spending',
      (d) => d['totalVnd'] == 175000 && d['unpricedCount'] == 0,
    );
    expect(done['pricedCount'], 3);
    pass('UI-06 nhập bù 100.000 ₫: tổng 175.000 ₫, hết cảnh báo');

    // ── UI-07: tháng trước trống, không cho sang tháng sau ──────────────
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('spending_next_month')))
          .onPressed,
      isNull,
    );
    await fixture.tap(tester, find.byKey(const Key('spending_prev_month')));
    await fixture.waitFor(tester, find.textContaining('Chưa có lần mua nào'));
    pass('UI-07 tháng trước trống, nút tháng sau bị tắt ở tháng hiện tại');
    await fixture.back(tester);

    // ── API-03: thông báo nêu tổng chi tiêu ─────────────────────────────
    // Worker chuyển thông báo chạy mỗi giây; chờ tối đa vài giây.
    Map<String, dynamic>? spendNotice;
    for (var i = 0; i < 20 && spendNotice == null; i++) {
      await tester.pump(const Duration(seconds: 1));
      final list = await fixture.request(
        '/workspaces/$ws/notifications?limit=50',
        'GET',
        null,
        token,
      );
      for (final n in list['items'] as List) {
        if ((n['body'] as String).contains('Chi tiêu tháng')) {
          spendNotice ??= Map<String, dynamic>.from(n as Map);
        }
      }
    }
    expect(spendNotice, isNotNull, reason: 'Thông báo chi tiêu phải được giao');
    final detail = await fixture.request(
      '/workspaces/$ws/notifications/${spendNotice!['id']}',
      'GET',
      null,
      token,
    );
    debugPrint('SPEND_NOTICE ${spendNotice['body']} || ${detail['detail']}');
    pass('API-03 thông báo: ${spendNotice['body']}');

    // ── Dọn dẹp ─────────────────────────────────────────────────────────
    await fixture.request('/auth/account', 'DELETE', {
      'currentPassword': password,
    }, token);
    binding.reportData = results;
  });
}
