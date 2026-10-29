import 'support/restored_plan_billing_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';

import 'support/fake_assistant_service.dart';

import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

/// Fake service đọc file thật nên cần để IO chạy ngoài fake-async.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceSheet.enableInfiniteAnimation = false;
  });

  testWidgets(
    'Prototype UI: Home shell renders Header, Voice banner, and Tabs',
    (tester) async {
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: AppShell(
            assistantService: FakeAssistantService(delay: Duration.zero),
            speechService: const UnavailableSpeechRecognitionService(),
          ),
        ),
      );
      await settleIo(tester);

      // Verify Home actions and data sections
      expect(find.text('Trợ lý giọng nói HomeMind'), findsOneWidget);
      expect(find.text('Sắp hết hạn'), findsAtLeastNWidgets(1));

      // Verify Bottom Navigation Bar
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Tủ đồ'), findsOneWidget);
      expect(find.text('Đi chợ'), findsOneWidget);
      expect(find.text('Nói'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsWidgets);
      expect(find.text('Cá nhân'), findsOneWidget);

      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Prototype UI: Pushed ShoppingPage, InventoryPage, ProfilePage render back buttons and pop correctly',
    (tester) async {
      final service = _InMemoryAssistantService();

      // 1. Test ShoppingPage back button
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: SafeArea(
                        child: ShoppingPage(
                          service: service,
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open Shopping'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Shopping'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Danh sách cần mua'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Open Shopping'), findsOneWidget);

      // 2. Test InventoryPage back button when pushed
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: SafeArea(child: InventoryPage(service: service)),
                    ),
                  ),
                ),
                child: const Text('Open Inventory'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Inventory'));
      await tester.pumpAndSettle();

      expect(find.text('Tủ đồ của bạn'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Open Inventory'), findsOneWidget);

      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Prototype UI: Tapping Center Mic button opens VoiceSheet', (
    tester,
  ) async {
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => VoiceSheet.show(
                context,
                speechService: const UnavailableSpeechRecognitionService(),
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // VoiceSheet is opened
    expect(find.text('Không thể dùng microphone'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);
    expect(find.text('Xong'), findsOneWidget);

    // Close the sheet
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Prototype UI: InventoryPage shows Search, Categories and Mark Out',
    (tester) async {
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(
            body: InventoryPage(service: _InMemoryAssistantService()),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Tủ đồ của bạn'), findsOneWidget);
      expect(find.text('Tìm sản phẩm trong tủ nhà...'), findsOneWidget);
      expect(find.textContaining('Sắp hết hạn'), findsOneWidget);
      expect(find.text('Sữa tươi TH'), findsOneWidget);

      await tester.tap(find.text('Đánh dấu Hết'));
      await tester.pumpAndSettle();
      expect(find.text('Bạn đã dùng hết Sữa tươi TH'), findsOneWidget);
      await tester.tap(find.text('Thêm vào danh sách đi chợ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã báo hết'), findsOneWidget);

      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Prototype UI: ShoppingPage shows filter tabs and items', (
    tester,
  ) async {
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: Scaffold(
          body: ShoppingPage(service: _InMemoryAssistantService()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Danh sách cần mua'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.textContaining('Cần mua ('), findsOneWidget);
    // Không còn tab "Đã mua/Đã nhập": hàng về thì phải nằm trong kho/tủ đồ.
    expect(find.textContaining('Đã mua ('), findsNothing);
    expect(find.textContaining('Đã nhập ('), findsNothing);
    expect(find.textContaining('Đã bỏ qua ('), findsOneWidget);

    await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('Prototype UI: Role switching to Merchant updates Home & Tabs', (
    tester,
  ) async {
    final service = _InMemoryAssistantService();
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: AppShell(
          assistantService: service,
          speechService: const UnavailableSpeechRecognitionService(),
        ),
      ),
    );
    await settleIo(tester);

    // Consumer default state
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Cá nhân'), findsOneWidget);
    expect(find.text('Tủ đồ'), findsOneWidget);
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('Danh sách cần mua'), findsOneWidget);

    // Switch to merchant
    service.switchRole(AccountRole.merchant);
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: AppShell(
          assistantService: service,
          speechService: const UnavailableSpeechRecognitionService(),
        ),
      ),
    );
    await settleIo(tester);

    // Merchant state
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Cá nhân'), findsOneWidget);
    expect(find.text('Kho hàng'), findsOneWidget);
    expect(find.text('Cần nhập'), findsWidgets);
    expect(find.text('Hàng cần nhập thêm'), findsOneWidget);

    await tester.pumpRestoredPlanBillingWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class _InMemoryAssistantService implements AssistantService {
  AccountRole _role = AccountRole.consumer;

  @override
  AccountRole get currentRole => _role;

  @override
  Listenable get dataChanges => _dataChanges;
  final _dataChanges = ChangeNotifier();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  @override
  Future<void> requestUpgrade({
    required String plan,
    required String source,
  }) async {}

  @override
  void switchRole(AccountRole role) {
    _role = role;
  }

  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async => (await getMe()).copyWith(
    displayName: displayName,
    phone: phone,
    address: address,
    language: language,
  );

  @override
  Future<UserProfile> getMe() async => _role == AccountRole.merchant
      ? const UserProfile(
          userId: '2',
          email: 'lan@homemind.vn',
          displayName: 'Cô Lan',
          workspaceId: 'ws-2',
          workspaceName: 'Tiệm Tạp Hóa Lan Anh',
          workspaceType: 'grocery_store',
          role: 'merchant',
        )
      : const UserProfile(
          userId: '1',
          email: 'tuan@homemind.vn',
          displayName: 'Anh Tuấn',
          workspaceId: 'ws-1',
          workspaceName: 'Nhà riêng',
          workspaceType: 'family',
          role: 'consumer',
        );

  @override
  Future<HomeSummary> getHomeSummary() async => _role == AccountRole.merchant
      ? const HomeSummary(
          totalProducts: 100,
          inStockCount: 90,
          outCount: 10,
          expiredCount: 2,
          expiringSoonCount: 3,
          shoppingNeededCount: 5,
          freePlanLimit: 500,
          productCountTowardLimit: 100,
          expiringSoon: [],
          expired: [],
          alerts: [
            HomeAlert(
              type: 'expiry',
              severity: 'urgent',
              productId: '1',
              title: 'Hàng cận date cần xả gấp ⚠️',
              subtitle: 'Sữa chua cần xả hàng',
              cta: 'discount',
            ),
          ],
        )
      : const HomeSummary(
          totalProducts: 10,
          inStockCount: 8,
          outCount: 2,
          expiredCount: 1,
          expiringSoonCount: 2,
          shoppingNeededCount: 3,
          freePlanLimit: 30,
          productCountTowardLimit: 10,
          expiringSoon: [],
          expired: [],
          alerts: [],
        );

  @override
  Future<({List<AppNotification> items, int unreadCount})>
  getNotifications() async => (items: <AppNotification>[], unreadCount: 0);

  @override
  Future<void> markNotificationRead(String notificationId) async {}

  @override
  Future<void> markAllNotificationsRead() async {}

  @override
  Future<List<InventoryItem>> getInventory() async => const [
    InventoryItem(
      productId: '1',
      name: 'Sữa tươi TH',
      category: 'Thực phẩm',
      quantity: 1,
      unit: 'hộp',
      expiryDate: '2026-10-01',
      status: 'in_stock',
      expiryLevel: 'soon',
    ),
  ];

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async => (
    items: <ShoppingItem>[
      const ShoppingItem(
        id: '1',
        name: 'Rau cải xanh',
        quantity: 1,
        unit: 'bó',
        status: 'needed',
        source: 'manual',
      ),
    ],
    suggestions: <Map<String, Object?>>[],
  );

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) async {}

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) async {}

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) async {}

  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async => throw UnimplementedError();

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async => throw UnimplementedError();

  @override
  Future<AssistantTurn> cancel({required String turnId}) async =>
      throw UnimplementedError();
}
