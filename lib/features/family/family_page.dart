import 'package:flutter/material.dart';

import '../../core/config/plan_billing_visibility.dart';

import '../../core/l10n/app_text.dart';
import '../../core/widgets/page_skeleton.dart';
import '../assistant/domain/assistant_models.dart';
import 'family_gateway.dart';

String _s(Object? value) => value is String ? value : '';
String _date(Object? value) {
  final date = DateTime.tryParse(_s(value))?.toLocal();
  return date == null
      ? tr('Chưa có')
      : '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _state(Object? value) => tr(switch (value) {
  'PENDING' => 'Đang chờ',
  'ACCEPTED' => 'Đã chấp nhận',
  'DECLINED' => 'Đã từ chối',
  'CANCELLED' => 'Đã hủy',
  'EXPIRED' => 'Đã hết hạn',
  _ => 'Không còn hiệu lực',
});
Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(title)),
        content: Text(tr(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Quay lại')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    ) ??
    false;
Widget _error(Object error, VoidCallback retry) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Text(
          PlanBillingVisibility.message(
            context,
            error.toString(),
            fallback: tr('Chưa thực hiện được thao tác này. Hãy thử lại.'),
          ),
          key: const Key('family_error'),
        ),
        TextButton(onPressed: retry, child: Text(tr('Thử lại'))),
      ],
    ),
  ),
);
Widget _card(List<Widget> children) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

class FamilyPage extends StatefulWidget {
  const FamilyPage({required this.gateway, super.key});
  final FamilyGateway gateway;
  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  Map<String, Object?>? _data;
  List<Map<String, Object?>> _workspaces = [];
  Object? _failure;
  bool _loading = true, _busy = false;
  int _generation = 0, _scopeGeneration = 0;
  final Map<String, String> _keys = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FamilyPage old) {
    super.didUpdateWidget(old);
    if (old.gateway.userId != widget.gateway.userId ||
        old.gateway.workspaceId != widget.gateway.workspaceId) {
      ++_scopeGeneration;
      _data = null;
      _workspaces = [];
      _keys.clear();
      _busy = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final data = await Future.wait([
        widget.gateway.overview(),
        widget.gateway.workspaces(),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data[0];
        _workspaces = familyRows(data[1]['items']);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _data = null;
          _workspaces = [];
          _failure = error;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _action(String name, Future<void> Function(String) run) async {
    if (_busy) return;
    setState(() => _busy = true);
    final generation = _generation, scope = _scopeGeneration;
    try {
      await run(_keys.putIfAbsent(name, widget.gateway.newKey));
      if (!mounted || generation != _generation) return;
      _keys.remove(name);
      await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failure = error;
          _data = null;
        });
      }
    } finally {
      if (mounted && scope == _scopeGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _invitations(bool outgoing) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            FamilyInvitationsPage(gateway: widget.gateway, outgoing: outgoing),
      ),
    );
    if (mounted) _load();
  }

  Future<bool> _confirmCurrent(String title, String message) async {
    final scope = _scopeGeneration;
    final accepted = await _confirm(context, title, message);
    return mounted && scope == _scopeGeneration && accepted;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final owner = data?['role'] == 'owner';
    final eligible = data?['eligible'] == true;
    final members = familyRows(data?['members']);
    final quota = data?['quota'] is Map
        ? VoiceQuota.fromJson(Map<String, Object?>.from(data!['quota'] as Map))
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Thành viên gia đình'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading && data == null)
                const PageSkeleton(SkeletonPage.family, sectionOnly: true),
              if (_loading && data != null) const LinearProgressIndicator(),
              if (_failure != null) _error(_failure!, _load),
              OutlinedButton.icon(
                key: const Key('family_inbox'),
                onPressed: _busy ? null : () => _invitations(false),
                icon: const Icon(Icons.mail_outline),
                label: Text(tr('Lời mời đã nhận')),
              ),
              if (data != null) ...[
                _card([
                  Text(
                    _s(data['name']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${tr('Người thân')}: ${data['relativeCount']}/5 · ${tr('Đang chờ')}: ${data['pendingCount']} · ${tr('Còn chỗ')}: ${data['availableSeats']}',
                  ),
                  const SizedBox(height: 12),
                  if (quota != null) ...[
                    Text(
                      '${tr('AI đã dùng')}: ${quota.used}/${quota.total} · ${tr('Còn lại')}: ${quota.remaining}',
                      key: const Key('family_shared_quota'),
                    ),
                    Text(
                      '${tr('Chu kỳ')}: ${_date(quota.startsAt.toIso8601String())} – ${_date(quota.expiresAt.toIso8601String())}',
                    ),
                    Text(
                      tr(
                        'Các thành viên Family dùng chung một hạn mức AI, kể cả khi chuyển về workspace riêng.',
                      ),
                    ),
                  ],
                  if (!eligible)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr(
                          PlanBillingVisibility.of(context)
                              ? 'Workspace cần quyền Family còn hiệu lực để mời người thân. Thanh toán hiện chưa được hỗ trợ.'
                              : 'Không gian hiện tại chưa có quyền mời thêm người thân.',
                        ),
                      ),
                    ),
                ]),
                if (_workspaces.length > 1)
                  _card([
                    Text(
                      tr('Không gian làm việc'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final workspace in _workspaces)
                      ListTile(
                        selected: workspace['id'] == widget.gateway.workspaceId,
                        trailing: workspace['id'] == widget.gateway.workspaceId
                            ? const Icon(Icons.check)
                            : null,
                        title: Text(_s(workspace['name'])),
                        subtitle: Text(
                          workspace['role'] == 'owner'
                              ? tr('Workspace riêng / sở hữu')
                              : tr('Workspace được chia sẻ'),
                        ),
                        onTap: _busy
                            ? null
                            : () {
                                final id = _s(workspace['id']);
                                if (id != widget.gateway.workspaceId) {
                                  _action(
                                    'select',
                                    (_) => widget.gateway.select(id),
                                  );
                                }
                              },
                      ),
                  ]),
                if (owner && eligible) ...[
                  FilledButton.icon(
                    key: const Key('family_invite'),
                    onPressed: _busy
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    FamilyInvitePage(gateway: widget.gateway),
                              ),
                            );
                            if (mounted) _load();
                          },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(tr('Mời người thân')),
                  ),
                ],
                if (owner)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _invitations(true),
                    child: Text(tr('Lời mời đã gửi')),
                  ),
                const SizedBox(height: 16),
                Text(
                  tr('Thành viên và sử dụng'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final member in members)
                  _card([
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(_s(member['displayName'])),
                      subtitle: Text(
                        member['role'] == 'owner'
                            ? tr('Chủ nhóm')
                            : tr('Thành viên'),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => FamilyMemberPage(member: member),
                        ),
                      ),
                    ),
                    Text(
                      '${tr('Lượt AI trong chu kỳ')}: ${member['usage']} · ${tr('Lần mua đã ghi')}: ${member['recordedPurchases']}',
                    ),
                    if (owner && eligible && member['role'] != 'owner')
                      TextButton(
                        key: ValueKey('family_remove_${member['userId']}'),
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _confirmCurrent(
                                  'Xóa khỏi nhóm?',
                                  PlanBillingVisibility.of(context)
                                      ? 'Người thân sẽ mất quyền truy cập nhóm và trở về Free. Dữ liệu đã ghi trong nhóm được giữ nguyên.'
                                      : 'Người thân sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành. Dữ liệu đã ghi trong nhóm được giữ nguyên.',
                                )) {
                                  if (mounted) {
                                    await _action(
                                      'remove_${member['userId']}',
                                      (key) => widget.gateway.remove(
                                        _s(member['userId']),
                                        key,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Text(tr('Xóa khỏi nhóm')),
                      ),
                  ]),
                if (!owner)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirmCurrent(
                              'Rời nhóm Family?',
                              PlanBillingVisibility.of(context)
                                  ? 'Bạn sẽ mất quyền truy cập nhóm và trở về gói Free, không khôi phục gói cá nhân trước khi tham gia. Dữ liệu và lịch sử thanh toán được giữ nguyên.'
                                  : 'Bạn sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành; quyền sử dụng trước khi tham gia không được khôi phục. Dữ liệu đã ghi được giữ nguyên.',
                            )) {
                              if (mounted) {
                                await _action('leave', widget.gateway.leave);
                              }
                            }
                          },
                    child: Text(tr('Rời nhóm')),
                  ),
                if (owner && data['sharingEnabled'] == true)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                              context,
                              'Dừng chia sẻ Family?',
                              PlanBillingVisibility.of(context)
                                  ? 'Mọi người thân sẽ mất quyền truy cập và trở về Free. Lời mời đang chờ không còn hiệu lực. Dữ liệu và gói hiện tại của chủ nhóm được giữ nguyên.'
                                  : 'Mọi người thân sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành. Lời mời đang chờ không còn hiệu lực. Dữ liệu và quyền sử dụng của chủ nhóm được giữ nguyên.',
                            )) {
                              if (mounted) {
                                await _action('end', widget.gateway.end);
                              }
                            }
                          },
                    child: Text(tr('Dừng chia sẻ')),
                  ),
              ],
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class FamilyInvitePage extends StatefulWidget {
  const FamilyInvitePage({required this.gateway, super.key});
  final FamilyGateway gateway;
  @override
  State<FamilyInvitePage> createState() => _FamilyInvitePageState();
}

class _FamilyInvitePageState extends State<FamilyInvitePage> {
  final _emails = TextEditingController();
  Map<String, Object?>? _preview;
  Object? _failure;
  bool _busy = false;
  String? _key;
  int _generation = 0;
  @override
  void didUpdateWidget(FamilyInvitePage old) {
    super.didUpdateWidget(old);
    if (old.gateway.userId != widget.gateway.userId ||
        old.gateway.workspaceId != widget.gateway.workspaceId) {
      ++_generation;
      _emails.clear();
      _preview = null;
      _failure = null;
      _key = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _emails.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failure = null;
      _preview = null;
      _key = null;
    });
    try {
      final preview = await widget.gateway.validate(_emails.text);
      if (mounted && generation == _generation) {
        setState(() => _preview = preview);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _failure = error);
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        _preview?['canSubmit'] != true ||
        _preview?['validationToken'] is! String) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.gateway.invite(
        _emails.text,
        _preview!['validationToken'] as String,
        _key ??= widget.gateway.newKey(),
      );
      if (mounted && generation == _generation) Navigator.pop(context);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failure = error;
          _preview = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Mời người thân'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('family_emails'),
            controller: _emails,
            enabled: !_busy,
            maxLength: 1280,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: tr('Email tài khoản HomeMind'),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {
              _preview = null;
              _key = null;
              _failure = null;
            }),
          ),
          Text(
            tr(
              'Nhập một hoặc nhiều email, mỗi email cách nhau bằng dấu phẩy (,). Tối đa 5 người thân trong Workspace.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Lời mời được gửi trong ứng dụng. Không gửi email. Lời mời đang chờ cũng giữ chỗ trong nhóm.',
            ),
          ),
          if (_failure != null) _error(_failure!, _validate),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('family_validate'),
            onPressed: _busy ? null : _validate,
            child: Text(tr('Kiểm tra danh sách')),
          ),
          if (_busy) const LinearProgressIndicator(),
          for (final result in familyRows(_preview?['results']))
            _card([
              Text(
                _s(result['email']),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                PlanBillingVisibility.message(
                  context,
                  _s(result['message']),
                  fallback: tr(
                    'Chưa thực hiện được thao tác này. Hãy thử lại.',
                  ),
                ),
              ),
              if (result['blockedUntil'] != null)
                Text(
                  '${tr('Có thể mời lại sau')}: ${_date(result['blockedUntil'])}',
                ),
            ]),
          FilledButton(
            key: const Key('family_send_batch'),
            onPressed: !_busy && _preview?['canSubmit'] == true
                ? _submit
                : null,
            child: Text(tr('Gửi lời mời')),
          ),
        ],
      ),
    ),
  );
}

class FamilyInvitationsPage extends StatefulWidget {
  const FamilyInvitationsPage({
    required this.gateway,
    this.outgoing = false,
    this.invitationId,
    super.key,
  });
  final FamilyGateway gateway;
  final bool outgoing;
  final String? invitationId;
  @override
  State<FamilyInvitationsPage> createState() => _FamilyInvitationsPageState();
}

class _FamilyInvitationsPageState extends State<FamilyInvitationsPage> {
  List<Map<String, Object?>> _items = [];
  bool _loading = true, _busy = false;
  String? _cursor;
  Object? _failure;
  int _generation = 0;
  final Map<String, String> _keys = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FamilyInvitationsPage old) {
    super.didUpdateWidget(old);
    if (old.gateway.userId != widget.gateway.userId ||
        old.gateway.workspaceId != widget.gateway.workspaceId ||
        old.outgoing != widget.outgoing ||
        old.invitationId != widget.invitationId) {
      _items = [];
      _cursor = null;
      _keys.clear();
      _busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _cursor == null)) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final id = widget.invitationId;
      final response = id == null
          ? await widget.gateway.invitations(
              outgoing: widget.outgoing,
              cursor: more ? _cursor : null,
            )
          : {
              'items': [await widget.gateway.invitation(id)],
            };
      if (!mounted || generation != _generation) return;
      final rows = familyRows(response['items']);
      setState(() {
        final merged = more ? [..._items, ...rows] : rows;
        _items = {for (final row in merged) _s(row['id']): row}.values.toList();
        _cursor = response['hasMore'] == true
            ? response['nextCursor'] as String?
            : null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failure = error;
          _items = [];
          _cursor = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _act(Map<String, Object?> row, String action) async {
    if (_busy) return;
    final generation = _generation;
    final gateway = widget.gateway;
    final message = action == 'accept'
        ? PlanBillingVisibility.of(context)
              ? 'Tham gia sẽ chuyển sang workspace Family và dùng chung hạn mức AI. Dữ liệu riêng không được nhập vào nhóm. Khi rời nhóm, gói cá nhân trở về Free.'
              : 'Tham gia sẽ chuyển sang không gian gia đình và dùng chung hạn mức AI. Dữ liệu riêng không được nhập vào nhóm. Khi rời nhóm, bạn sử dụng hạn mức cá nhân hiện hành.'
        : action == 'decline'
        ? 'Sau ba lần từ chối, chủ nhóm phải chờ đủ 24 giờ mới được mời lại.'
        : 'Lời mời sẽ hết hiệu lực và trả lại chỗ trống.';
    if (!await _confirm(
          context,
          action == 'accept'
              ? 'Tham gia Family?'
              : action == 'decline'
              ? 'Từ chối lời mời?'
              : 'Hủy lời mời?',
          message,
        ) ||
        !mounted ||
        generation != _generation) {
      return;
    }
    setState(() => _busy = true);
    final id = _s(row['id']), operation = '$action:${row['id']}';
    try {
      final key = _keys.putIfAbsent(operation, gateway.newKey);
      if (action == 'cancel') {
        await gateway.cancel(id, key);
      } else {
        await gateway.respond(id, accept: action == 'accept', key: key);
      }
      if (!mounted || generation != _generation) return;
      _keys.remove(operation);
      await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        await _load();
        if (mounted) setState(() => _failure = error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(widget.outgoing ? 'Lời mời đã gửi' : 'Lời mời đã nhận')),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading && _items.isEmpty)
              const PageSkeleton(SkeletonPage.invitations, sectionOnly: true),
            if ((_loading && _items.isNotEmpty) || _busy)
              const LinearProgressIndicator(),
            if (_failure != null) _error(_failure!, _load),
            if (!_loading && _failure == null && _items.isEmpty)
              Text(tr('Chưa có lời mời.')),
            for (final row in _items)
              _card([
                Text(
                  _s(row['workspaceName']),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(_s(row[widget.outgoing ? 'inviteeName' : 'inviterName'])),
                Text(_state(row['state'])),
                Text('${tr('Hết hạn')}: ${_date(row['expiresAt'])}'),
                if (row['blockedUntil'] != null)
                  Text(
                    '${tr('Có thể mời lại sau')}: ${_date(row['blockedUntil'])}',
                  ),
                if (row['state'] == 'PENDING')
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.outgoing)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _act(row, 'cancel'),
                          child: Text(tr('Hủy lời mời')),
                        )
                      else if (row['isRecipient'] != false) ...[
                        FilledButton(
                          onPressed: _busy ? null : () => _act(row, 'accept'),
                          child: Text(tr('Chấp nhận')),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _act(row, 'decline'),
                          child: Text(tr('Từ chối')),
                        ),
                      ],
                    ],
                  ),
              ]),
            if (_cursor != null)
              TextButton(
                onPressed: _loading || _busy ? null : () => _load(more: true),
                child: Text(tr('Xem thêm')),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Directory projections only: no peer profile editor or private conversations.
class FamilyMemberPage extends StatelessWidget {
  const FamilyMemberPage({required this.member, super.key});
  final Map<String, Object?> member;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Thông tin thành viên'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card([
            const Icon(Icons.person_outline, size: 40),
            Text(
              _s(member['displayName']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(member['role'] == 'owner' ? tr('Chủ nhóm') : tr('Thành viên')),
            Text('${tr('Tham gia')}: ${_date(member['joinedAt'])}'),
            const SizedBox(height: 16),
            Text('${tr('Lượt AI trong chu kỳ')}: ${member['usage']}'),
            Text('${tr('Lần mua đã ghi')}: ${member['recordedPurchases']}'),
            Text(
              tr(
                'Chỉ hiển thị sử dụng trong workspace này. Không bao gồm hội thoại hay dữ liệu riêng.',
              ),
            ),
          ]),
        ],
      ),
    ),
  );
}

// Handled by Tran Gia Phu
