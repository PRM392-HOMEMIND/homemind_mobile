import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';

import 'support/fake_assistant_service.dart';

Future<void> _settle(WidgetTester tester) async {
  // Dữ liệu mẫu đọc từ file thật nên cần để thời gian THẬT trôi qua (runAsync);
  // không dùng pumpAndSettle vì vòng quay tải dữ liệu chạy vô hạn khi chưa xong.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Nạp font thật để kiểm tra bố cục như trên máy (font mặc định của test rộng hơn).
Future<void> _loadFont() async {
  final loader = FontLoader('BeVietnamPro');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/BeVietnamPro-$w.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _openShell(WidgetTester tester) async {
  await tester.runAsync(_loadFont);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: HomeMindTheme.themeData,
      home: AppShell(
        assistantService: FakeAssistantService(delay: Duration.zero),
        speechService: const UnavailableSpeechRecognitionService(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('Tủ đồ: rời tab rồi quay lại thì bộ lọc về "Tất cả"', (
    tester,
  ) async {
    await _openShell(tester);

    await tester.tap(find.text('Tủ đồ'));
    await _settle(tester);
    // Dữ liệu mẫu có 3 món: 2 đồ tươi + 1 gia vị.
    expect(find.text('Sữa chua Vinamilk'), findsOneWidget);
    expect(find.text('Nước mắm'), findsOneWidget);

    // Chọn nhóm "Đồ tươi": món gia vị bị ẩn đi.
    await tester.tap(find.textContaining('Đồ tươi ('));
    await _settle(tester);
    expect(find.text('Sữa chua Vinamilk'), findsOneWidget);
    expect(find.text('Nước mắm'), findsNothing);

    // Sang Trang chủ rồi quay lại Tủ đồ.
    await tester.tap(find.text('Trang chủ'));
    await _settle(tester);
    await tester.tap(find.text('Tủ đồ'));
    await _settle(tester);

    // Về lại "Tất cả": thấy đủ mọi món, không còn kẹt ở "Đồ tươi".
    expect(find.text('Sữa chua Vinamilk'), findsOneWidget);
    expect(find.text('Nước mắm'), findsOneWidget);
  });

  testWidgets('Tủ đồ: ô tìm kiếm cũng được xoá khi quay lại', (tester) async {
    await _openShell(tester);
    await tester.tap(find.text('Tủ đồ'));
    await _settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(InventoryPage),
        matching: find.byType(TextField),
      ),
      'nước mắm',
    );
    await _settle(tester);
    expect(find.text('Sữa chua Vinamilk'), findsNothing);

    await tester.tap(find.text('Đi chợ'));
    await _settle(tester);
    await tester.tap(find.text('Tủ đồ'));
    await _settle(tester);

    expect(find.text('Sữa chua Vinamilk'), findsOneWidget);
  });

  testWidgets('Đi chợ: rời tab rồi quay lại thì về tab "Cần mua"', (
    tester,
  ) async {
    await _openShell(tester);
    await tester.tap(find.text('Đi chợ'));
    await _settle(tester);
    // Tab "Cần mua" có nút "Đã mua" ở từng món.
    expect(find.text('Đã mua'), findsWidgets);

    await tester.tap(find.textContaining('Đã hết ('));
    await _settle(tester);
    expect(find.text('Đã mua'), findsNothing); // đang ở tab "Đã hết"

    await tester.tap(find.text('Trang chủ'));
    await _settle(tester);
    await tester.tap(find.text('Đi chợ'));
    await _settle(tester);
    // Quay lại thấy tab "Cần mua" (không kẹt ở "Đã hết").
    expect(find.text('Đã mua'), findsWidgets);
  });
}
