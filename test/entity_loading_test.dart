import 'support/load_app_fonts.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/core/widgets/page_skeleton.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/hub_entity_page.dart';

Future<void> captureFrame(WidgetTester tester, String name) async {
  final folder = Platform.environment['HOMEMIND_LOCAL_FRAME_DIR'];
  if (folder == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('local_frame')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Widget app(Widget child, {double scale = 1}) => RepaintBoundary(
  key: const Key('local_frame'),
  child: MaterialApp(
    theme: HomeMindTheme.themeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  ),
);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => AppText.setLanguage('vi', persist: false));
  for (final scale in [1.0, 2.0]) {
    testWidgets('real detail nullable fields and zero price fit320px/$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final response = Completer<Map<String, Object?>>();
      var retry = false;
      final body = <String, Object?>{
        'name': 'Món đồ có tên dài để kiểm tra bố cục chi tiết thực tế',
        'status': 'in_stock',
        'quantity': null,
        'category': null,
        'lots': [
          {
            'lotId': 'unknown',
            'quantity': null,
            'unit': null,
            'expiryDate': null,
            'priceVnd': null,
            'storageLocation': null,
          },
          {
            'lotId': 'zero',
            'quantity': 2,
            'unit': 'hộp',
            'expiryDate': '2026-10-30',
            'priceVnd': 0,
            'storageLocation': 'Tủ bếp',
            'purchasedAt': '2026-10-13',
          },
        ],
      };
      final gateway = HomeHubGateway(
        workspaceId: 'local',
        scope: 'user.local',
        request: (method, path) => retry ? Future.value(body) : response.future,
      );
      await tester.pumpWidget(
        app(
          HubEntityPage(
            gateway: gateway,
            target: const HubTarget('inventory', 'item'),
          ),
          scale: scale,
        ),
      );
      await tester.pump();
      expect(find.byType(PageSkeleton), findsOneWidget);
      await captureFrame(tester, 'detail_loading_$scale');
      response.completeError(StateError('controlled offline'));
      await tester.pumpAndSettle();
      expect(find.text('Tải lại'), findsOneWidget);
      retry = true;
      await tester.tap(find.text('Tải lại'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Chưa ghi số lượng'), 150);
      expect(find.text('Chưa ghi số lượng'), findsOneWidget);
      expect(find.text('Giá mua: Chưa ghi giá mua'), findsOneWidget);
      expect(find.text('Nơi cất: Chưa ghi nơi cất'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      await captureFrame(tester, 'detail_partial_$scale');
      await tester.scrollUntilVisible(find.text('Nơi cất: Tủ bếp'), 200);
      expect(find.textContaining('0'), findsWidgets);
      expect(find.text('Ngày nhập: 2026-10-13'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureFrame(tester, 'detail_lot_$scale');
    });
  }
  testWidgets('page-specific skeleton frames remain static and accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      for (final page in SkeletonPage.values) {
        await tester.pumpWidget(
          app(
            Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(child: PageSkeleton(page)),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.bySemanticsLabel('Đang tải dữ liệu'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: page.name);
        await captureFrame(tester, 'skeleton_${page.name}');
      }
    } finally {
      semantics.dispose();
    }
  });
}
