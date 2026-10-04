import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../../assistant/domain/assistant_models.dart';

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({
    required this.initialNotifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
    this.onUnreadCountChanged,
    super.key,
  });

  final List<AppNotification> initialNotifications;
  final Future<void> Function(String notificationId) onMarkRead;
  final Future<({List<AppNotification> items, int unreadCount})> Function()
  onMarkAllRead;
  final ValueChanged<int>? onUnreadCountChanged;

  static void show(
    BuildContext context, {
    required List<AppNotification> notifications,
    required Future<void> Function(String notificationId) onMarkRead,
    required Future<({List<AppNotification> items, int unreadCount})> Function()
    onMarkAllRead,
    ValueChanged<int>? onUnreadCountChanged,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationsSheet(
        initialNotifications: notifications,
        onMarkRead: onMarkRead,
        onMarkAllRead: onMarkAllRead,
        onUnreadCountChanged: onUnreadCountChanged,
      ),
    );
  }

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  late List<AppNotification> _items;
  bool _batchBusy = false;
  String _filter = 'all'; // 'all' or 'unread'

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initialNotifications);
  }

  int get _unreadCount => _items.where((x) => !x.read).length;

  void _saveFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Chưa lưu được. Bạn thử lại nhé.')),
        backgroundColor: HomeMindTheme.danger,
      ),
    );
  }

  /// "Hết hạn 2026-09-30" -> "Hết hạn 30/09/2026" cho dễ đọc.
  String _niceBody(String body) => body.replaceAllMapped(
    RegExp(r'(\d{4})-(\d{2})-(\d{2})'),
    (m) => '${m[3]}/${m[2]}/${m[1]}',
  );

  /// Chưa đọc lên trên, đã đọc xuống dưới (giữ nguyên thứ tự từ server
  /// trong từng nhóm), kèm tiêu đề nhóm khi xem "Tất cả".
  List<Object> _rows() {
    final shown = _items.where(
      (x) => PlanBillingVisibility.showsRecord(context, {
        'type': x.type,
        'title': x.title,
        'body': x.body,
      }),
    );
    final unread = shown.where((x) => !x.read).toList();
    if (_filter == 'unread') return unread;
    final read = shown.where((x) => x.read).toList();
    return [
      if (unread.isNotEmpty) tr('Chưa đọc'),
      ...unread,
      if (read.isNotEmpty) tr('Đã đọc'),
      ...read,
    ];
  }

  /// One bounded batch; only server-confirmed rows/counts replace the display.
  Future<void> _markAllRead() async {
    if (_batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      final result = await widget.onMarkAllRead();
      if (!mounted) return;
      setState(() => _items = List.of(result.items));
      widget.onUnreadCountChanged?.call(result.unreadCount);
    } catch (_) {
      _saveFailed();
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _markRead(String id) async {
    if (_batchBusy) return;
    final index = _items.indexWhere((x) => x.id == id);
    if (index == -1 || _items[index].read) {
      // Đã đọc rồi: vẫn báo cho nơi chứa như trước đây.
      try {
        await widget.onMarkRead(id);
      } catch (_) {
        _saveFailed();
      }
      return;
    }
    final before = _items[index];
    setState(() => _items[index] = before.copyWith(read: true));
    widget.onUnreadCountChanged?.call(_unreadCount);
    try {
      await widget.onMarkRead(id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == id);
        if (i != -1) _items[i] = before;
      });
      widget.onUnreadCountChanged?.call(_unreadCount);
      _saveFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: HomeMindTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    tr('Thông báo'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                ),
                if (_unreadCount > 0)
                  Flexible(
                    child: TextButton(
                      key: const Key('notifications_read_all'),
                      onPressed: _batchBusy ? null : _markAllRead,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        tr('Đánh dấu tối đa 50 thông báo'),
                        style: TextStyle(
                          color: HomeMindTheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(tr('Tất cả')),
                  selected: _filter == 'all',
                  onSelected: (val) => setState(() => _filter = 'all'),
                  selectedColor: HomeMindTheme.primary,
                  labelStyle: TextStyle(
                    color: _filter == 'all'
                        ? Colors.white
                        : HomeMindTheme.textSub,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: _filter == 'all'
                        ? HomeMindTheme.primary
                        : HomeMindTheme.border,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(tr('Chưa đọc ({0})', [_unreadCount])),
                  selected: _filter == 'unread',
                  onSelected: (val) => setState(() => _filter = 'unread'),
                  selectedColor: HomeMindTheme.primary,
                  labelStyle: TextStyle(
                    color: _filter == 'unread'
                        ? Colors.white
                        : HomeMindTheme.textSub,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: _filter == 'unread'
                        ? HomeMindTheme.primary
                        : HomeMindTheme.border,
                  ),
                ),
              ],
            ),
          ),
          if (_unreadCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(
                    'Chạm vào thông báo hoặc bấm "Đã đọc" để chuyển xuống mục Đã đọc.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: HomeMindTheme.textMuted,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          const Divider(color: HomeMindTheme.border, height: 12),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      tr('Không có thông báo nào.'),
                      style: TextStyle(color: HomeMindTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row is String) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            row,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: HomeMindTheme.textSub,
                            ),
                          ),
                        );
                      }
                      final item = row as AppNotification;
                      return InkWell(
                        key: Key('notification_${item.id}'),
                        onTap: () => _markRead(item.id),
                        borderRadius: BorderRadius.circular(
                          HomeMindTheme.radiusMd,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.read
                                ? Colors.white
                                : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(
                              HomeMindTheme.radiusMd,
                            ),
                            border: Border.all(
                              color: item.read
                                  ? HomeMindTheme.border
                                  : HomeMindTheme.primary.withValues(
                                      alpha: 0.3,
                                    ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: item.type == 'expiry'
                                      ? HomeMindTheme.urgentBg
                                      : item.type == 'shopping'
                                      ? HomeMindTheme.soonBg
                                      : HomeMindTheme.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    item.type == 'expiry'
                                        ? '⚠️'
                                        : item.type == 'shopping'
                                        ? '🛒'
                                        : '💡',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: TextStyle(
                                              fontWeight: item.read
                                                  ? FontWeight.w600
                                                  : FontWeight.w700,
                                              fontSize: 13,
                                              color: HomeMindTheme.textMain,
                                            ),
                                          ),
                                        ),
                                        if (!item.read)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: HomeMindTheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _niceBody(item.body),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: HomeMindTheme.textSub,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        if (!item.read)
                                          TextButton.icon(
                                            onPressed: () => _markRead(item.id),
                                            icon: const Icon(
                                              Icons.done_rounded,
                                              size: 14,
                                            ),
                                            label: Text(tr('Đã đọc')),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  HomeMindTheme.primaryDark,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 0,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              textStyle: const TextStyle(
                                                fontFamily:
                                                    HomeMindTheme.fontFamily,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
