import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_assistant_service.dart';

import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/home_page.dart';

class _PersistentNotificationService extends FakeAssistantService {
  _PersistentNotificationService() : super(delay: Duration.zero);

  AppNotification notification = const AppNotification(
    id: 'expiry.product.2026-10-03',
    title: 'Sữa sắp hết hạn',
    body: 'Hết hạn 2026-10-03',
    context: 'Dữ liệu tồn kho hiện tại',
    type: 'expiry',
    read: false,
  );

  @override
  Future<({List<AppNotification> items, int unreadCount})>
  getNotifications() async =>
      (items: [notification], unreadCount: notification.read ? 0 : 1);

  @override
  Future<void> markNotificationRead(String notificationId) async {
    expect(notificationId, notification.id);
    notification = notification.copyWith(read: true);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    notification = notification.copyWith(read: true);
  }
}

Widget _home(_PersistentNotificationService service) => MaterialApp(
  home: Scaffold(
    body: HomePage(
      service: service,
      onOpenAssistant: () {},
      onOpenShopping: () {},
    ),
  ),
);

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

  testWidgets('read state survives reopening sheet and rebuilding app', (
    tester,
  ) async {
    final service = _PersistentNotificationService();
    await tester.pumpWidget(_home(service));
    await settleIo(tester);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đọc (1)'), findsOneWidget);

    await tester.tap(find.text('Sữa sắp hết hạn'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đọc (0)'), findsOneWidget);

    Navigator.of(tester.element(find.text('Thông báo'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đọc (0)'), findsOneWidget);

    Navigator.of(tester.element(find.text('Thông báo'))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_home(service));
    await settleIo(tester);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đọc (0)'), findsOneWidget);
  });
}
