import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/home_page.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/fake_assistant_service.dart';

/// Các trang chạy trên dịch vụ có cache: khi cache đổi (ghi lạc quan / làm mới
/// nền) trang phải dựng lại KHÔNG ném lỗi và hiện dữ liệu mới.
class _CacheFixtureService extends FakeAssistantService {
  _CacheFixtureService()
    : super(
        delay: Duration.zero,
        fixtureReader: (path) => File(path).readAsStringSync(),
      );

  final _out = <String>{};

  @override
  Future<List<InventoryItem>> getInventory() async => [
    for (final item in await super.getInventory())
      _out.contains(item.productId) ? item.copyWith(status: 'out') : item,
  ];

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) async {
    _out.add(productId);
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: HomeMindTheme.themeData,
  home: Scaffold(body: child),
);

class _PendingProfileService extends FakeAssistantService {
  _PendingProfileService() : super(delay: Duration.zero);
  final profile = Completer<UserProfile>();
  @override
  Future<UserProfile> getMe() => profile.future;
  Future<UserProfile> loadProfile() => super.getMe();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CachedAssistantService service;

  setUp(() {
    service = CachedAssistantService(
      _CacheFixtureService(),
      reconcileDelay: const Duration(milliseconds: 30),
    );
  });
  tearDown(() => service.dispose());

  testWidgets('Trang chủ: cache đã sẵn sàng khi hồ sơ vẫn đang chờ', (
    tester,
  ) async {
    final inner = _PendingProfileService();
    final cached = CachedAssistantService(inner);
    addTearDown(cached.dispose);
    final profile = await tester.runAsync(inner.loadProfile);
    await tester.runAsync(cached.refresh);
    expect(cached.hasData, isTrue);
    await tester.pumpWidget(
      _app(
        HomePage(
          service: cached,
          onOpenAssistant: () {},
          onOpenShopping: () {},
        ),
      ),
    );
    inner.profile.complete(profile!);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('home_search')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Trang chủ: đổi cache không ném lỗi, huy hiệu chuông giảm ngay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        HomePage(
          service: service,
          onOpenAssistant: () {},
          onOpenShopping: () {},
          onOpenInventory: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = (await service.getNotifications()).unreadCount;
    expect(before, greaterThan(0));

    final first = (await service.getNotifications()).items.firstWhere(
      (n) => !n.read,
    );
    await service.markNotificationRead(first.id); // ghi lạc quan: đổi ngay
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect((await service.getNotifications()).unreadCount, before - 1);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect((await service.getNotifications()).unreadCount, before - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kho và Đi chợ: ghi lạc quan cập nhật trang ngay, không lỗi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            Expanded(child: InventoryPage(service: service)),
            Expanded(child: ShoppingPage(service: service)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inv = await service.getInventory();
    final inStock = inv.firstWhere((i) => i.status == 'in_stock');
    await service.markInventoryOut(
      productId: inStock.productId,
      addToShoppingList: true,
    );
    await tester.pump();
    expect(
      (await service.getInventory())
          .firstWhere((i) => i.productId == inStock.productId)
          .status,
      'out',
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final after = await service.getInventory();
    expect(
      after.firstWhere((i) => i.productId == inStock.productId).status,
      'out',
    );
  });

  test(
    'canh gác: không viết setState(() => _future = ...) (trả về Future)',
    () {
      final offenders = <String>[];
      final pattern = RegExp(r'setState\(\s*\(\)\s*=>\s*_?future\s*=');
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final text = e.readAsStringSync();
        if (pattern.hasMatch(text)) offenders.add(e.path);
        // dạng gán Future qua mũi tên: setState(() => _x = something())
        for (final m in RegExp(
          r'setState\(\s*\(\)\s*=>\s*_\w+\s*=\s*[\w.]*(?:_load|get[A-Z]\w*)\(',
        ).allMatches(text)) {
          offenders.add('${e.path}: ${m.group(0)}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Sẽ ném lỗi "setState returned a Future"',
      );
    },
  );
}
