import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/widgets/page_skeleton.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../domain/home_hub_gateway.dart';
import 'home_surface.dart';

class GlobalSearchSurface extends StatefulWidget {
  const GlobalSearchSurface({required this.gateway, super.key});
  final HomeHubGateway gateway;
  @override
  State<GlobalSearchSurface> createState() => _GlobalSearchSurfaceState();
}

class _GlobalSearchSurfaceState extends State<GlobalSearchSurface> {
  final _input = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _busy = false;
  String? _error, _cursor;
  String _filter = 'all';
  List<Map> _rows = [], _shortcuts = [];
  final _notificationMetadata = <String, Future<Map<String, Object?>?>>{};
  Future<void> _classification = Future.value();
  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  bool _valid(int g) => mounted && g == _generation;
  @override
  void didUpdateWidget(covariant GlobalSearchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway.scope != widget.gateway.scope) {
      ++_generation;
      _input.clear();
      _rows = [];
      _shortcuts = [];
      _notificationMetadata.clear();
      _cursor = null;
      _fetch('');
    }
  }

  Future<Map<String, Object?>?> _noticeMetadata(
    HomeHubGateway gateway,
    String id,
  ) {
    final cached = _notificationMetadata[id];
    if (cached != null) return cached;
    // Bound this surface's metadata-only cache. It is discarded on actor or
    // workspace change; no notification text or read state is cached here.
    if (_notificationMetadata.length >= 100) {
      _notificationMetadata.remove(_notificationMetadata.keys.first);
    }
    late final Future<Map<String, Object?>?> lookup;
    lookup = () async {
      try {
        final detail = await gateway
            .notification(id)
            .timeout(const Duration(seconds: 3));
        if (detail['id'] != id ||
            detail['type'] is! String ||
            (detail['type'] as String).isEmpty ||
            detail['targetType'] is! String ||
            (detail['targetId'] != null && detail['targetId'] is! String)) {
          return null;
        }
        return <String, Object?>{
          'notificationType': detail['type'],
          'targetType': detail['targetType'],
          'targetId': detail['targetId'],
        };
      } catch (_) {
        return null;
      }
    }();
    _notificationMetadata[id] = lookup;
    unawaited(
      lookup.then((metadata) {
        if (metadata == null && identical(_notificationMetadata[id], lookup)) {
          _notificationMetadata.remove(id);
        }
      }),
    );
    return lookup;
  }

  Future<List<Map>> _visibleRows(List<Map> rows, int generation) async {
    if (PlanBillingVisibility.of(context)) return rows;
    // Serialize classification batches across overlapping searches as well,
    // so replacing a query cannot multiply the four-read concurrency bound.
    final previous = _classification;
    final completed = Completer<void>();
    _classification = completed.future;
    try {
      await previous;
      if (!_valid(generation)) return [];
      return await _classifyRows(rows, generation);
    } finally {
      completed.complete();
    }
  }

  Future<List<Map>> _classifyRows(List<Map> rows, int generation) async {
    final gateway = widget.gateway;
    final visible = <Map>[];
    // Search returns at most 20 hits, without notification kind/target. Use the
    // existing read-only detail API to distinguish product labels from billing
    // notices. Four concurrent reads maximum, never mark a search hit as read.
    for (var offset = 0; offset < rows.length; offset += 4) {
      if (!_valid(generation)) return [];
      final chunk = rows.skip(offset).take(4);
      final classified = await Future.wait(
        chunk.map((row) async {
          if (row['type'] != 'notification') return row;
          final id = row['id'];
          if (id is! String || id.isEmpty) return null;
          final metadata = await _noticeMetadata(gateway, id);
          // Unverifiable notification copy stays hidden; failed reads are not
          // cached so the normal Retry/query action can attempt them again.
          return metadata == null
              ? null
              : <Object?, Object?>{...row, ...metadata};
        }),
      );
      if (!_valid(generation)) return [];
      visible.addAll(
        classified.whereType<Map>().where(
          (row) => PlanBillingVisibility.showsRecord(context, row),
        ),
      );
    }
    return visible;
  }

  void _changed(String q) {
    _debounce?.cancel();
    ++_generation;
    setState(() {
      _busy = false;
      _error = null;
      _cursor = null;
      _rows = q.trim().isEmpty ? _shortcuts : [];
    });
    if (q.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').runes.length <
        2) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q, {String? cursor}) async {
    _debounce?.cancel();
    final g = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.gateway
          .search(q, cursor: cursor, filter: _filter)
          .timeout(const Duration(seconds: 15));
      if (!_valid(g)) return;
      final rows = await _visibleRows((data['items'] as List).cast<Map>(), g);
      if (!_valid(g)) return;
      setState(() {
        _rows = rows;
        _cursor = data['nextCursor'] as String?;
        if (q.isEmpty) _shortcuts = rows;
      });
    } catch (_) {
      if (_valid(g)) {
        setState(() => _error = tr('Chưa tìm kiếm được. Hãy thử lại.'));
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _select(Map item) async {
    if (_busy) return;
    if (!PlanBillingVisibility.of(context) &&
        PlanBillingVisibility.isPlanTarget(
          item['type'] as String,
          item['id'] as String,
        )) {
      return;
    }
    final g = ++_generation;
    setState(() => _busy = true);
    try {
      final target = await widget.gateway.resolve(HubTarget.fromJson(item));
      if (mounted && g == _generation) {
        if (!PlanBillingVisibility.of(context) &&
            PlanBillingVisibility.isPlanTarget(target.type, target.id)) {
          return;
        }
        Navigator.pop(context, target);
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
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SurfaceHeader(title: tr('Tìm kiếm HomeMind')),
      Expanded(
        child: CustomScrollView(
          key: const Key('search_scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      key: const Key('global_search_input'),
                      controller: _input,
                      maxLength: 120,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: tr('Tìm sản phẩm, món cần mua, thông báo...'),
                        hintMaxLines: 2,
                        counterText: '',
                        filled: true,
                        fillColor: HomeMindTheme.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            HomeMindTheme.radiusMd,
                          ),
                          borderSide: const BorderSide(
                            color: HomeMindTheme.sectionBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            HomeMindTheme.radiusMd,
                          ),
                          borderSide: const BorderSide(
                            color: HomeMindTheme.sectionBorder,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _input.text.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('search_clear'),
                                tooltip: tr('Xóa từ khóa'),
                                onPressed: () {
                                  _input.clear();
                                  _changed('');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: _changed,
                      onSubmitted: (q) {
                        if (q.trim().runes.length >= 2) _fetch(q);
                      },
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(14) + 38,
                    child: ListView(
                      key: const Key('search_filters'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final entry
                            in const {
                              'all': 'Tất cả',
                              'inventory': 'Kho hàng',
                              'shopping': 'Đi chợ',
                              'profile': 'Hồ sơ',
                              'plan': 'Gói',
                              'feature': 'Chức năng',
                              'billing': 'Thanh toán',
                              'notification': 'Thông báo',
                            }.entries.where(
                              (entry) =>
                                  PlanBillingVisibility.of(context) ||
                                  !{'plan', 'billing'}.contains(entry.key),
                            ))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: Key('search_filter_${entry.key}'),
                              label: Text(
                                tr(entry.value),
                                style: const TextStyle(fontSize: 14),
                              ),
                              selectedColor: HomeMindTheme.mintSurface,
                              backgroundColor: HomeMindTheme.card,
                              labelStyle: const TextStyle(
                                color: HomeMindTheme.primaryStrong,
                              ),
                              side: BorderSide(
                                color: _filter == entry.key
                                    ? HomeMindTheme.mintBorder
                                    : HomeMindTheme.sectionBorder,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              selected: _filter == entry.key,
                              onSelected: (_) {
                                setState(() => _filter = entry.key);
                                _fetch(_input.text);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_busy && _rows.isEmpty)
                    const PageSkeleton(SkeletonPage.search, sectionOnly: true)
                  else if (_busy)
                    const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: HomeMindTheme.textSub,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => _fetch(_input.text),
                            child: Text(tr('Thử lại')),
                          ),
                        ],
                      ),
                    ),
                  if (_input.text.trim().isEmpty && !_busy && _error == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr('Truy cập nhanh'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: HomeMindTheme.textSub,
                          ),
                        ),
                      ),
                    ),
                  if (_rows.isEmpty && !_busy && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.search_rounded,
                              color: HomeMindTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tr(
                                _input.text.trim().isEmpty
                                    ? 'Nhập từ khóa để tìm trong HomeMind'
                                    : 'Không tìm thấy kết quả phù hợp',
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: HomeMindTheme.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SliverList.builder(
              key: ValueKey('search_${_input.text}_$_filter'),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final item = _rows[i];
                return ListTile(
                  key: Key('search_result_${item['type']}_${item['id']}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    _title(item),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    _summary(item),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: HomeMindTheme.textSub,
                    ),
                  ),
                  leading: ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: HomeMindTheme.mintSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _icon(item),
                        size: 22,
                        color: HomeMindTheme.primaryStrong,
                      ),
                    ),
                  ),
                  trailing: const ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: HomeMindTheme.textMuted,
                    ),
                  ),
                  onTap: _busy ? null : () => _select(item),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    if (_cursor != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _fetch(_input.text, cursor: _cursor),
                        child: Text(tr('Trang tiếp')),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => _fetch(_input.text),
                      child: Text(tr('Làm mới kết quả')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// These identities describe destinations, never authorization or billing rules.
const _featureVisuals = {
  'home': (label: 'Trang chủ', icon: Icons.home_outlined),
  'inventory': (label: 'Tủ đồ', icon: Icons.kitchen_outlined),
  'shopping': (label: 'Đi chợ', icon: Icons.shopping_basket_outlined),
  'profile': (label: 'Hồ sơ & Tài khoản', icon: Icons.person_outline_rounded),
  'security': (label: 'Bảo mật tài khoản', icon: Icons.shield_outlined),
  'billing': (
    label: 'Gói & thanh toán',
    icon: Icons.account_balance_wallet_outlined,
  ),
  'history': (label: 'Lịch sử thanh toán', icon: Icons.receipt_long_outlined),
  'notifications': (label: 'Thông báo', icon: Icons.notifications_none_rounded),
  'help': (label: 'Trợ giúp', icon: Icons.support_agent_rounded),
};

IconData _icon(Map item) {
  if (item['type'] == 'feature') {
    return _featureVisuals[item['id']]?.icon ?? Icons.apps_rounded;
  }
  return switch (item['type']) {
    'inventory' => Icons.kitchen_outlined,
    'shopping' => Icons.shopping_basket_outlined,
    'notification' => Icons.notifications_none_rounded,
    'billing' || 'plan' => Icons.account_balance_wallet_outlined,
    'profile' => Icons.person_outline_rounded,
    _ => Icons.apps_rounded,
  };
}

// Localize known system labels only; user-generated titles pass through intact.
String _title(Map item) {
  if (item['type'] == 'feature') {
    final label = _featureVisuals[item['id']]?.label;
    if (label != null) return tr(label);
  }
  if (item['type'] == 'plan') {
    return switch (item['title']) {
      'Cá nhân Personal' => tr('Gói Cá nhân'),
      'Gia đình Family' => tr('Gia đình'),
      'Micro-POS Tạp hóa' => 'Micro-POS',
      _ => item['title'] as String,
    };
  }
  return item['title'] as String;
}

String _summary(Map item) {
  if (item['type'] == 'feature') return tr('Mở chức năng');
  final category = switch (item['type']) {
    'inventory' => tr('Tủ đồ'),
    'shopping' => tr('Đi chợ'),
    'notification' => tr('Thông báo'),
    'billing' => tr('Thanh toán'),
    'plan' => tr('Gói'),
    'profile' => tr('Hồ sơ'),
    _ => '',
  };
  var summary = item['summary'] as String;
  if (item['type'] == 'inventory' || item['type'] == 'shopping') {
    // The documented search projection puts status last; preceding category/unit
    // are user data and must not be translated or rewritten.
    final parts = summary.split(' · ');
    parts[parts.length - 1] = switch (parts.last) {
      'in_stock' => tr('Còn hàng'),
      'out' => tr('Đã hết hàng'),
      'needed' => tr('Cần mua'),
      'received' => tr('Đã nhận hàng'),
      _ => parts.last,
    };
    summary = parts.join(' · ');
  } else if (item['type'] == 'profile') {
    summary = switch (summary) {
      'Hồ sơ · Profile' => '',
      'Không gian · Workspace' => tr('Không gian'),
      _ => summary,
    };
  } else if (item['type'] == 'plan' && summary == 'Gói thanh toán') {
    summary = '';
  }
  return category.isEmpty || summary.isEmpty
      ? '$category$summary'
      : '$category · $summary';
}
