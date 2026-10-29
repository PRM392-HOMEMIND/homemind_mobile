import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/notifications_sheet.dart';

AppNotification _n(String id, String title, {bool read = false}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'Hết hạn 2026-09-30',
      context: 'Dữ liệu tồn kho hiện tại',
      type: 'expiry',
      read: read,
    );

void main() {
  late List<String> markedRead;
  var markedAll = false;
  var failWrites = false;
  late List<int> unreadCounts;

  setUp(() {
    markedRead = [];
    markedAll = false;
    failWrites = false;
    unreadCounts = [];
  });

  Future<void> open(WidgetTester tester, List<AppNotification> items) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => NotificationsSheet.show(
                  context,
                  notifications: items,
                  onMarkRead: (id) async {
                    if (failWrites) throw Exception('server');
                    markedRead.add(id);
                  },
                  onMarkAllRead: () async {
                    if (failWrites) throw Exception('server');
                    markedAll = true;
                    final batch = items
                        .where((e) => !e.read)
                        .take(50)
                        .map((e) => e.id)
                        .toSet();
                    final rows = items
                        .map(
                          (e) =>
                              batch.contains(e.id) ? e.copyWith(read: true) : e,
                        )
                        .toList();
                    return (
                      items: rows,
                      unreadCount: rows.where((e) => !e.read).length,
                    );
                  },
                  onUnreadCountChanged: unreadCounts.add,
                ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
  }

  final readButtons = find.descendant(
    of: find.byType(TextButton),
    matching: find.text('Đã đọc'),
  );

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('chưa đọc nằm trên, đã đọc nằm dưới, có tiêu đề từng nhóm', (
    tester,
  ) async {
    await open(tester, [
      _n('a', 'Đã đọc A', read: true),
      _n('b', 'Chưa đọc B'),
      _n('c', 'Đã đọc C', read: true),
      _n('d', 'Chưa đọc D'),
    ]);

    expect(top(tester, 'Chưa đọc B'), lessThan(top(tester, 'Chưa đọc D')));
    expect(top(tester, 'Chưa đọc D'), lessThan(top(tester, 'Đã đọc A')));
    expect(top(tester, 'Đã đọc A'), lessThan(top(tester, 'Đã đọc C')));
    // Tiêu đề nhóm.
    expect(find.text('Chưa đọc'), findsOneWidget);
    // 1 tiêu đề nhóm "Đã đọc" (ngoài các nút Đã đọc ở từng thông báo).
    expect(
      find.text('Đã đọc').evaluate().length - readButtons.evaluate().length,
      1,
    );
  });

  testWidgets(
    'mỗi thông báo chưa đọc có nút Đánh dấu đã đọc, bấm là chuyển xuống',
    (tester) async {
      await open(tester, [_n('b', 'Chưa đọc B'), _n('d', 'Chưa đọc D')]);
      expect(readButtons, findsNWidgets(2));

      await tester.tap(readButtons.first);
      await tester.pumpAndSettle();

      expect(markedRead, ['b']);
      expect(unreadCounts.last, 1);
      expect(readButtons, findsOneWidget);
      // B đã xuống dưới D.
      expect(top(tester, 'Chưa đọc D'), lessThan(top(tester, 'Chưa đọc B')));
    },
  );

  testWidgets('chạm vào thông báo cũng đánh dấu đã đọc', (tester) async {
    await open(tester, [_n('b', 'Chưa đọc B')]);
    await tester.tap(find.text('Chưa đọc B'));
    await tester.pumpAndSettle();
    expect(markedRead, ['b']);
  });

  testWidgets('Đánh dấu tối đa 50 thông báo', (tester) async {
    await open(tester, [_n('b', 'B'), _n('d', 'D')]);
    await tester.tap(find.text('Đánh dấu tối đa 50 thông báo'));
    await tester.pumpAndSettle();
    expect(markedAll, isTrue);
    expect(unreadCounts.last, 0);
    expect(readButtons, findsNothing);
    expect(find.text('Đánh dấu tối đa 50 thông báo'), findsNothing);
  });

  testWidgets('bounded batch preserves the51st unread notification', (
    tester,
  ) async {
    await open(tester, List.generate(51, (i) => _n('$i', 'Thông báo $i')));
    await tester.tap(find.byKey(const Key('notifications_read_all')));
    await tester.pumpAndSettle();
    expect(unreadCounts.last, 1);
    expect(find.text('Thông báo 50'), findsOneWidget);
    expect(find.byKey(const Key('notifications_read_all')), findsOneWidget);
  });

  testWidgets('ngày yyyy-MM-dd hiện dạng dd/MM/yyyy và không lộ chữ kỹ thuật', (
    tester,
  ) async {
    await open(tester, [_n('b', 'B')]);
    expect(find.text('Hết hạn 30/09/2026'), findsOneWidget);
    expect(find.text('Dữ liệu tồn kho hiện tại'), findsNothing);
  });

  testWidgets('lưu lỗi thì báo dễ hiểu và vẫn giữ chưa đọc', (tester) async {
    failWrites = true;
    await open(tester, [_n('b', 'B')]);
    await tester.tap(readButtons);
    await tester.pumpAndSettle();
    expect(find.text('Chưa lưu được. Bạn thử lại nhé.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(readButtons, findsOneWidget);
  });

  testWidgets('bộ lọc Chưa đọc chỉ hiện món chưa đọc', (tester) async {
    await open(tester, [
      _n('a', 'Đã đọc A', read: true),
      _n('b', 'Chưa đọc B'),
    ]);
    await tester.tap(find.text('Chưa đọc (1)').first);
    await tester.pumpAndSettle();
    expect(find.text('Đã đọc A'), findsNothing);
    expect(find.text('Chưa đọc B'), findsOneWidget);
  });
}
