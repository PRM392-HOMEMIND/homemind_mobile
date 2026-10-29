import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/inventory/presentation/repurchase_dialog.dart';

Future<bool?> _open(WidgetTester tester, {required bool merchant}) async {
  // Màn hình hẹp như điện thoại thật (360dp) để bắt lỗi chữ bị che.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  bool? result = true;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await RepurchaseDialog.show(
                  context,
                  'Tương ớt Chinsu 250g',
                  merchant: merchant,
                );
                done = true;
              },
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
  expect(done, isFalse);
  return result;
}

void main() {
  testWidgets('nút rộng đầy, chữ nằm gọn trong nút (không bị che)', (
    tester,
  ) async {
    await _open(tester, merchant: true);
    // Không có lỗi tràn layout nào được ném ra.
    expect(tester.takeException(), isNull);

    for (final label in ['Thêm vào danh sách cần nhập', 'Không, chỉ báo hết']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      final text = tester.getSize(find.text(label));
      final box = tester.getSize(button);
      expect(text.width, lessThan(box.width), reason: label);
      // Chữ một dòng, không bị cắt cao.
      expect(text.height, lessThan(box.height), reason: label);
    }
  });

  testWidgets('cửa hàng: "cần nhập"; gia đình: "đi chợ"', (tester) async {
    await _open(tester, merchant: false);
    expect(find.text('Thêm vào danh sách đi chợ'), findsOneWidget);
    expect(find.textContaining('cần nhập'), findsNothing);
  });

  testWidgets('trả về true / false / null đúng theo nút bấm', (tester) async {
    bool? result;
    Future<void> openAndTap(String label) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async =>
                      result = await RepurchaseDialog.show(context, 'Sữa'),
                  child: const Text('mở'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await openAndTap('Thêm vào danh sách đi chợ');
    expect(result, isTrue);
    await openAndTap('Không, chỉ báo hết');
    expect(result, isFalse);
    result = true;
    await openAndTap('Huỷ');
    expect(result, isNull);
  });
}
