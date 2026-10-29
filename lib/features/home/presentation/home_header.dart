import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';

/// Thanh đầu trang chủ: một ô tìm kiếm và chuông thông báo, không có gì khác.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.onSearch,
    required this.onNotifications,
    this.searchHint,
    this.unread,
    this.notificationAnchor,
    super.key,
  });
  final String? searchHint;
  final int? unread;
  final GlobalKey? notificationAnchor;
  final VoidCallback onSearch, onNotifications;

  @override
  Widget build(BuildContext context) {
    final hasUnread = unread != null && unread! > 0;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: tr('Tìm kiếm'),
            child: InkWell(
              key: const Key('home_search'),
              onTap: onSearch,
              borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  border: Border.all(color: HomeMindTheme.border),
                ),
                child: Row(
                  children: [
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.search_rounded,
                        color: HomeMindTheme.textMuted,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        searchHint ?? tr('Tìm đồ dùng, thực phẩm...'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: HomeMindTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          key: notificationAnchor,
          child: Badge(
            isLabelVisible: hasUnread,
            backgroundColor: HomeMindTheme.danger,
            offset: const Offset(-2, 2),
            label: ExcludeSemantics(
              child: Text(
                unread != null && unread! >= 100 ? '99+' : '${unread ?? ''}',
                textScaler: TextScaler.noScaling,
              ),
            ),
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                key: const Key('home_notifications'),
                tooltip: hasUnread
                    ? tr('Thông báo, {0} chưa đọc', [unread])
                    : tr('Thông báo'),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: HomeMindTheme.textMain,
                  shape: const CircleBorder(
                    side: BorderSide(color: HomeMindTheme.border),
                  ),
                ),
                onPressed: onNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
