import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/widgets/page_skeleton.dart';

import 'package:flutter/foundation.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../billing/billing_widgets.dart' show billingDate;
import '../domain/home_hub_gateway.dart';
import 'home_surface.dart';

enum _Mode { preview, all, detail }

class DurableNotificationsSurface extends StatefulWidget {
  const DurableNotificationsSurface({
    required this.gateway,
    this.initialId,
    this.onUnread,
    this.changes,
    super.key,
  });
  final HomeHubGateway gateway;
  final String? initialId;
  final ValueChanged<int>? onUnread;
  final ValueListenable<int>? changes;
  @override
  State<DurableNotificationsSurface> createState() =>
      _DurableNotificationsSurfaceState();
}

class _DurableNotificationsSurfaceState
    extends State<DurableNotificationsSurface> {
  _Mode _mode = _Mode.preview, _returnMode = _Mode.preview;
  final _scroll = ScrollController();
  double _savedOffset = 0;
  List<Map> _rows = [];
  Map? _detail;
  String? _cursor, _error;
  bool _hasMore = false,
      _busy = false,
      _readBusy = false,
      _readFailed = false,
      _newNotice = false;
  int _generation = 0;
  final List<String?> _previous = [];
  String? _pageCursor;
  String? _batchCutoff;
  int? _batchRemaining;
  bool _valid(int g) => mounted && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_changed);
    if (widget.initialId != null) {
      _open(widget.initialId!);
    } else {
      _load();
    }
  }

  void _changed() {
    if (mounted) setState(() => _newNotice = true);
  }

  @override
  void didUpdateWidget(covariant DurableNotificationsSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_changed);
      widget.changes?.addListener(_changed);
    }
    if (oldWidget.gateway.scope != widget.gateway.scope) {
      ++_generation;
      _rows = [];
      _detail = null;
      _previous.clear();
      _mode = _Mode.preview;
      _cursor = null;
      _batchCutoff = null;
      _batchRemaining = null;
      _load();
    }
  }

  Future<void> _load({String? cursor}) async {
    final g = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.gateway
          .notifications(limit: _mode == _Mode.preview ? 5 : 20, cursor: cursor)
          .timeout(const Duration(seconds: 15));
      if (!_valid(g)) return;
      setState(() {
        _rows = (data['items'] as List).cast<Map>();
        _cursor = data['nextCursor'] as String?;
        _hasMore = data['hasMore'] == true;
        _pageCursor = cursor;
        _newNotice = false;
      });
      widget.onUnread?.call(data['unreadCount'] as int);
    } catch (_) {
      if (_valid(g)) {
        setState(() => _error = tr('Chưa tải được thông báo. Hãy thử lại.'));
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _readBatch() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final result = await widget.gateway
          .readBatch(cutoff: _batchCutoff)
          .timeout(const Duration(seconds: 15));
      if (!_valid(generation)) return;
      _batchCutoff = result['hasMore'] == true
          ? result['cutoff'] as String?
          : null;
      _batchRemaining = (result['remainingCount'] as num).toInt();
      await _load(cursor: _pageCursor);
    } catch (_) {
      if (_valid(generation)) {
        setState(
          () => _error = tr('Chưa lưu được trạng thái đã đọc. Hãy thử lại.'),
        );
      }
    } finally {
      if (_valid(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _open(String id) async {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SurfaceExtent(true).dispatch(context);
      });
    }
    final g = ++_generation;
    _savedOffset = _scroll.hasClients ? _scroll.offset : 0;
    _returnMode = _mode;
    setState(() {
      _mode = _Mode.detail;
      _detail = null;
      _busy = true;
      _error = null;
      _readFailed = false;
      _readBusy = false;
    });
    try {
      final detail = await widget.gateway
          .notification(id)
          .timeout(const Duration(seconds: 15));
      if (!mounted || g != _generation) return;
      if (!PlanBillingVisibility.showsRecord(context, detail)) {
        // Silent fallback. Hidden content has not rendered, so do not mark it read.
        setState(() {
          _detail = null;
          _mode = _Mode.preview;
        });
        SurfaceExtent(false).dispatch(context);
        await _load();
        return;
      }
      setState(() => _detail = detail);
      // Acknowledge only after the detail content has actually rendered.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_valid(g) && _detail?['id'] == id) _read(id, g);
      });
    } catch (_) {
      if (_valid(g)) {
        setState(
          () => _error = tr(
            'Thông báo không còn được phép mở hoặc chưa tải được.',
          ),
        );
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _read(String id, int g) async {
    if (_readBusy || _detail?['read'] == true) return;
    setState(() => _readBusy = true);
    try {
      final data = await widget.gateway
          .read(id)
          .timeout(const Duration(seconds: 15));
      if (!_valid(g) || _detail?['id'] != id) return;
      setState(() {
        _detail = {..._detail!, 'read': true, 'readAt': data['readAt']};
        _readFailed = false;
        _rows = [
          for (final row in _rows)
            if (row['id'] == id) {...row, 'read': true} else row,
        ];
      });
      widget.onUnread?.call(data['unreadCount'] as int);
    } catch (_) {
      if (_valid(g)) setState(() => _readFailed = true);
    } finally {
      if (_valid(g)) setState(() => _readBusy = false);
    }
  }

  void _back() {
    ++_generation;
    _busy = false;
    _readBusy = false;
    _error = null;
    if (_mode == _Mode.detail) {
      setState(() => _mode = _returnMode);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            _savedOffset.clamp(0, _scroll.position.maxScrollExtent),
          );
        }
      });
    } else {
      setState(() => _mode = _Mode.preview);
      _previous.clear();
      _load();
    }
    SurfaceExtent(_mode != _Mode.preview).dispatch(context);
  }

  void _all() {
    setState(() => _mode = _Mode.all);
    SurfaceExtent(true).dispatch(context);
    _previous.clear();
    _load();
  }

  Future<void> _related() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final type = detail['targetType'];
    final target = HubTarget(
      {'home', 'security', 'profile'}.contains(type)
          ? 'feature'
          : type as String,
      detail['targetId'] as String? ??
          (type == 'family' ? widget.gateway.workspaceId : type as String),
    );
    if (!PlanBillingVisibility.of(context) &&
        PlanBillingVisibility.isPlanTarget(target.type, target.id)) {
      return;
    }
    final g = ++_generation;
    setState(() => _busy = true);
    try {
      final resolved = await widget.gateway.resolve(target);
      if (mounted && g == _generation) {
        if (!PlanBillingVisibility.of(context) &&
            PlanBillingVisibility.isPlanTarget(resolved.type, resolved.id)) {
          return;
        }
        Navigator.pop(context, resolved);
      }
    } catch (_) {
      if (_valid(g)) {
        setState(
          () => _error = tr('Kết quả không còn được phép mở. Hãy tải lại.'),
        );
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.changes?.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _mode == _Mode.preview,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Column(
      children: [
        SurfaceHeader(
          title: tr(
            _mode == _Mode.detail
                ? 'Chi tiết thông báo'
                : _mode == _Mode.all
                ? 'Tất cả thông báo'
                : 'Thông báo gần đây',
          ),
          onBack: _mode == _Mode.preview ? null : _back,
        ),
        if (_busy) const LinearProgressIndicator(),
        if (widget.gateway.write != null && _mode != _Mode.detail)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextButton(
                  key: const Key('notifications_read_batch'),
                  onPressed: _busy ? null : _readBatch,
                  child: Text(
                    tr(
                      _batchCutoff == null
                          ? 'Đánh dấu tối đa 50 thông báo đã đọc'
                          : 'Tiếp tục đánh dấu batch tiếp theo',
                    ),
                  ),
                ),
                if (_batchRemaining != null)
                  Text(
                    tr('Còn {0} thông báo trước mốc đã chọn chưa đọc', [
                      _batchRemaining!,
                    ]),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 40,
                  color: HomeMindTheme.textMuted,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('notifications_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HomeMindTheme.textSub),
                ),
                if (_mode != _Mode.detail)
                  TextButton(
                    key: const Key('notifications_retry'),
                    onPressed: _busy ? null : () => _load(cursor: _pageCursor),
                    child: Text(tr('Thử lại')),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _mode == _Mode.detail
              ? _detailBody()
              : CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    if (_busy && _rows.isEmpty)
                      const SliverToBoxAdapter(
                        child: PageSkeleton(SkeletonPage.notifications),
                      )
                    else
                      _listBody(),
                    SliverToBoxAdapter(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          if (_newNotice)
                            Text(tr('Có thông báo mới. Tải lại để xem.')),
                          if (_mode == _Mode.preview && _hasMore)
                            TextButton(
                              key: const Key('notifications_view_all'),
                              onPressed: _busy ? null : _all,
                              child: Text(tr('Xem tất cả')),
                            ),
                          if (_mode == _Mode.all)
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                if (_previous.isNotEmpty)
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            final c = _previous.removeLast();
                                            _load(cursor: c);
                                          },
                                    child: Text(tr('Trang trước')),
                                  ),
                                if (_cursor != null)
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            if (_previous.length == 10) {
                                              _previous.removeAt(0);
                                            }
                                            _previous.add(_pageCursor);
                                            _load(cursor: _cursor);
                                          },
                                    child: Text(tr('Trang tiếp')),
                                  ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          _previous.clear();
                                          _load();
                                        },
                                  child: Text(tr('Về đầu')),
                                ),
                              ],
                            ),
                          if (_mode != _Mode.detail)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _load(cursor: _pageCursor),
                              child: Text(tr('Tải lại')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
  List<Map> get _shownRows => _rows
      .where((row) => PlanBillingVisibility.showsRecord(context, row))
      .toList();

  Widget _listBody() => _shownRows.isEmpty && !_busy
      ? SliverToBoxAdapter(
          child: _error != null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 48,
                        color: HomeMindTheme.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('Không có thông báo nào.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: HomeMindTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
        )
      : SliverList.builder(
          itemCount: _shownRows.length,
          itemBuilder: (context, i) {
            final row = _shownRows[i], unread = row['read'] != true;
            final cancelled = row['type'] == 'billing.cancelled';
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Material(
                color: unread ? HomeMindTheme.primaryTint : Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  key: Key('durable_notification_${row['id']}'),
                  leading: Icon(
                    cancelled
                        ? Icons.cancel_outlined
                        : Icons.notifications_none_rounded,
                    color: cancelled
                        ? HomeMindTheme.danger
                        : HomeMindTheme.primaryStrong,
                  ),
                  title: Text(
                    tr(row['title'] as String),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${tr(row['body'] as String)}\n${billingDate(row['receivedAt'])}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread
                      ? const ExcludeSemantics(
                          child: Icon(
                            Icons.circle,
                            color: HomeMindTheme.primary,
                            size: 8,
                          ),
                        )
                      : null,
                  onTap: () => _open(row['id'] as String),
                ),
              ),
            );
          },
        );
  Widget _detailBody() {
    final d = _detail;
    if (d == null) {
      return _busy
          ? const SingleChildScrollView(
              child: PageSkeleton(SkeletonPage.notifications),
            )
          : const SizedBox();
    }
    if (!PlanBillingVisibility.showsRecord(context, d)) {
      return const SizedBox.shrink();
    }
    return ListView(
      key: const Key('notification_detail'),
      padding: const EdgeInsets.all(16),
      children: [
        if (_newNotice)
          Text(tr('Có thông báo mới. Quay lại để tải lại danh sách.')),
        Text(
          tr(d['title'] as String),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(tr(d['detail'] as String)),
        const SizedBox(height: 12),
        Text(tr('Xảy ra lúc: {0}', [billingDate(d['occurredAt'])])),
        Text(tr('Nhận lúc: {0}', [billingDate(d['receivedAt'])])),
        if (d['readAt'] != null)
          Text(tr('Đọc lần đầu: {0}', [billingDate(d['readAt'])])),
        if (_readBusy) Text(tr('Đang ghi nhận đã đọc...')),
        if (_readFailed)
          TextButton(
            onPressed: () => _read(d['id'] as String, _generation),
            child: Text(tr('Chưa ghi nhận đã đọc. Thử lại')),
          ),
        if (PlanBillingVisibility.of(context) ||
            !PlanBillingVisibility.isPlanTarget(
              d['targetType'] as String,
              d['targetId'] as String? ?? '',
            )) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _related,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(tr('Mở nội dung liên quan')),
          ),
        ],
      ],
    );
  }
}
