import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';
import 'package:homemind_mobile/main.dart' as app;

import 'full_system_test.dart' as fixture;

// Nói (gõ) qua khung giọng nói thật, trợ lý Gemini thật, màn xác nhận thật, backend local.
// Cần: backend có GEMINI_API_KEY, `adb reverse tcp:3000 tcp:3000`, và đã cấp quyền micro:
//   adb shell pm grant vn.homemind.homemind_mobile android.permission.RECORD_AUDIO
//   flutter test integration_test/voice_spending_device_test.dart -d <device> \
//     --dart-define-from-file=config/development.json
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  fixture.nativeTest('VOICE-01 nói giá + nơi cất, sửa kho theo số còn lại', (
    tester,
  ) async {
    final results = <String, Object?>{};
    void pass(String id) {
      results[id] = 'PASS';
      debugPrint('VOICE_RESULT $id PASS');
    }

    final email = 'voice+${fixture.nonce().substring(0, 16)}@example.com';
    final password = fixture.nonce();
    final session = await fixture.request('/auth/register', 'POST', {
      'acceptedTerms': true,
      'acceptedPrivacy': true,
      'displayName': 'Voice E2E',
      'email': email,
      'password': password,
      'workspaceType': 'household',
    });
    final token = session['accessToken'] as String;
    final ws = (await fixture.request(
      '/me',
      'GET',
      null,
      token,
    ))['workspaceId'];

    await tester.pumpWidget(const SizedBox.shrink());
    await const FlutterSecureStorage()
        .deleteAll(); // bỏ phiên đăng nhập còn lại trên máy
    await app.main();
    await fixture.waitFor(tester, find.text('Bỏ qua'));
    await fixture.tap(tester, find.text('Bỏ qua'));
    await fixture.waitFor(tester, find.byKey(const Key('login_identifier')));
    await fixture.fill(tester, 'login_identifier', email);
    await fixture.fill(tester, 'login_password', password);
    await fixture.dismissKeyboard(tester);
    await fixture.tap(tester, find.byKey(const Key('login_submit')));
    await fixture.waitFor(tester, find.byKey(const Key('nav_home')));

    // Gõ vào khung giọng nói như lời nói đã được nhận dạng, rồi bấm Xong.
    Future<void> say(String text) async {
      await fixture.tap(tester, find.byKey(const Key('nav_voice')));
      await fixture.waitFor(tester, find.byType(VoiceSheet));
      final field = find.descendant(
        of: find.byType(VoiceSheet),
        matching: find.byType(TextField),
      );
      await fixture.waitFor(tester, field);
      await tester.enterText(field, text);
      await fixture.dismissKeyboard(tester);
      await fixture.tap(tester, find.text('Xong'));
    }

    Future<Map<String, dynamic>> inventoryItem(String name) async {
      final inv = await fixture.request(
        '/workspaces/$ws/inventory?limit=100',
        'GET',
        null,
        token,
      );
      return (inv['items'] as List).cast<Map<String, dynamic>>().firstWhere(
        (i) => (i['name'] as String).contains(name),
      );
    }

    // ── V1: câu của người dùng, nghe sai chính tả ───────────────────────
    await say('thietj lơn mua đc 3 ký giá 275000 để ở tử dá');
    await fixture.waitFor(tester, find.text('Lưu'), seconds: 60);
    expect(find.textContaining('thịt lợn'), findsWidgets);
    expect(find.textContaining('275.000 ₫'), findsWidgets); // giá điền sẵn
    expect(find.textContaining('Tủ đá'), findsWidgets); // nơi cất điền sẵn
    pass('V1a màn xác nhận điền sẵn thịt lợn, 275.000 ₫, Tủ đá');
    await fixture.tap(tester, find.text('Lưu'));
    final lot = await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/spending',
      (d) => d['totalVnd'] == 275000,
    );
    expect(lot['pricedCount'], 1);
    final pork = await inventoryItem('thịt lợn');
    expect(pork['quantity'], 3);
    expect(pork['storageLocation'], contains('đá'));
    pass('V1b đã lưu: tồn 3, chi tiêu 275.000 ₫, nơi cất tủ đá');

    // ── V2: mâu thuẫn với tồn kho => trợ lý hỏi lại, không trừ ──────────
    await say('thịt lợn ăn gần hết rồi còn 3 ký thôi');
    await fixture.waitFor(
      tester,
      find.textContaining('Kho đang ghi còn 3'),
      seconds: 60,
    );
    expect((await inventoryItem('thịt lợn'))['quantity'], 3);
    pass('V2 "còn 3 ký" trong khi kho đang 3: hỏi lại, kho giữ nguyên');
    await fixture.tap(tester, find.text('Đã hiểu'));

    // ── V3: còn nửa ký => trừ 2,5 ───────────────────────────────────────
    await say('thịt lợn ăn gần hết rồi chỉ còn nửa ký');
    await fixture.waitFor(tester, find.text('Lưu'), seconds: 60);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/inventory?limit=100',
      (d) => (d['items'] as List).any(
        (dynamic i) =>
            (i['name'] as String).contains('thịt lợn') && i['quantity'] == 0.5,
      ),
    );
    pass('V3 còn nửa ký: kho từ 3 xuống 0,5');

    // ── V4: hỏi chi tiêu bằng giọng nói ─────────────────────────────────
    await say('tháng này tôi tiêu hết bao nhiêu tiền');
    await fixture.waitFor(
      tester,
      find.textContaining('275.000 ₫'),
      seconds: 60,
    );
    pass('V4a trợ lý đọc đúng chi tiêu tháng: 275.000 ₫');
    await fixture.tap(tester, find.text('Xem chi tiêu'));
    await fixture.waitFor(tester, find.byKey(const Key('spending_total')));
    pass('V4b nút "Xem chi tiêu" mở trang chi tiêu');
    await fixture.back(tester);

    // ── V5: kể hạn của hàng ĐÃ có: không được cộng thêm thành 7 ─────────
    await say('vừa mua 5 gói mì tôm');
    await fixture.waitFor(tester, find.text('Lưu'), seconds: 60);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/inventory?limit=100',
      (d) => (d['items'] as List).any(
        (dynamic i) =>
            (i['name'] as String).contains('mì tôm') && i['quantity'] == 5,
      ),
    );
    await say('có 2 gói mì tôm sắp hết hạn');
    await fixture.waitFor(
      tester,
      find.text('Đã hiểu'),
      seconds: 60,
    ); // hỏi lại ngày, không có nút Lưu
    expect(find.text('Lưu'), findsNothing);
    expect((await inventoryItem('mì tôm'))['quantity'], 5);
    pass('V5a "có 2 gói sắp hết hạn": hỏi lại ngày, kho vẫn 5 (không thành 7)');
    await fixture.tap(tester, find.text('Đã hiểu'));

    await say('trong 5 gói mì tôm có 2 gói hạn 20 tháng 10 năm 2026');
    await fixture.waitFor(tester, find.text('Lưu'), seconds: 60);
    expect(find.text('20/10/2026'), findsWidgets);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/inventory?limit=100',
      (d) => (d['items'] as List).any(
        (dynamic i) =>
            (i['name'] as String).contains('mì tôm') &&
            i['expiryDate'] == '2026-10-20',
      ),
    );
    final noodles = await inventoryItem('mì tôm');
    expect(noodles['quantity'], 5);
    pass('V5b đặt hạn 20/10 cho 2 gói: tồn vẫn 5, hạn gần nhất 2026-10-20');

    // ── V6: chỉ có tên ──────────────────────────────────────────────────
    await say('vừa mua muối');
    await fixture.waitFor(tester, find.text('Lưu'), seconds: 60);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/inventory?limit=100',
      (d) => (d['items'] as List).any(
        (dynamic i) =>
            (i['name'] as String).contains('muối') &&
            i['quantity'] == null &&
            i['status'] == 'in_stock',
      ),
    );
    pass('V6 chỉ có tên: lưu được, không bịa số lượng/đơn vị');
    await fixture.tap(tester, find.byKey(const Key('nav_inventory')));
    await fixture.waitFor(tester, find.textContaining('muối'));
    pass('V6b kho hiển thị muối khi không có số lượng');

    // ── V7: câu dài nói liền (ca thật): 5 món, giá riêng, hạn chung ─────
    await say(
      'vừa mua được 3 kg thịt lợn với giá 175.000đ hai chai một chai dầu gội một chai sữa tắm một chai dầu xả mỗi chai trung bình có giá 150.000 một chai hạn sử dụng là đến năm 2027 và tháng 9 mua được 3 kg muối với giá là 10.000 một ký hạn sử dụng là một',
    );
    await fixture.waitFor(
      tester,
      find.text('Món 5'),
      seconds: 60,
    ); // không còn "xử lý từng việc một"
    expect(find.textContaining('từng việc một'), findsNothing);
    expect(find.text('30/09/2027'), findsNWidgets(3));
    await fixture.tap(tester, find.text('Lưu'));
    final big = await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/spending',
      (d) => d['totalVnd'] == 275000 + 175000 + 3 * 150000 + 30000,
    );
    expect(big['pricedCount'], 6); // thịt lợn (V1) + 5 món của câu dài
    final shower = await inventoryItem('sữa tắm');
    expect(shower['expiryDate'], '2027-09-30');
    expect((await inventoryItem('muối'))['quantity'], 3);
    pass(
      'V7 câu dài 5 món: một màn xác nhận, giá từng món, hạn 30/09/2027 cho 3 chai, muối hạn trống',
    );

    // ── V8: nhiều việc khác loại trong một câu: duyệt lần lượt, không bắt nói từng việc ──
    await say('vừa mua 2 hộp sữa và 3 quả trứng rồi hết dầu ăn');
    await fixture.waitFor(
      tester,
      find.text('Việc 1/2 trong câu bạn vừa nói'),
      seconds: 60,
    );
    expect(find.textContaining('từng việc một'), findsNothing);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.waitFor(
      tester,
      find.text('Việc 2/2 trong câu bạn vừa nói'),
      seconds: 30,
    );
    expect(find.textContaining('dầu ăn'), findsWidgets);
    await fixture.tap(tester, find.text('Lưu'));
    await fixture.persisted(
      tester,
      {'accessToken': token},
      '/workspaces/$ws/shopping-items',
      (d) => (d['items'] as List).any(
        (dynamic i) => (i['name'] as String).contains('dầu ăn'),
      ),
    );
    expect((await inventoryItem('sữa'))['quantity'], 2);
    expect((await inventoryItem('trứng'))['quantity'], 3);
    pass(
      'V8 một câu 2 việc: Việc 1/2 nhập sữa+trứng, Việc 2/2 thêm dầu ăn vào danh sách mua',
    );

    await fixture.request('/auth/account', 'DELETE', {
      'currentPassword': password,
    }, token);
    binding.reportData = results;
  });
}
