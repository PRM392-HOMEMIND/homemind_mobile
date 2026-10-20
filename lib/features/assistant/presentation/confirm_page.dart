import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/quantity.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/product_groups.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';
import '../../home/presentation/paywall_sheet.dart';
import '../data/backend_assistant_service.dart' show HomeMindApiException;
import '../data/cached_assistant_service.dart' show syncValue;
import '../../home/presentation/plan_catalog.dart';
import '../../spending/presentation/price_location_fields.dart';

/// Màn "Kiểm tra lại trước khi lưu": hiển thị bản nháp do trợ lý đề xuất,
/// cho người dùng sửa rồi bấm Lưu hoặc Huỷ. Hợp đồng gửi lên backend giữ
/// nguyên: đúng 1 tool với `toolId` và `arguments` theo dictionary.ts.
class ConfirmPage extends StatefulWidget {
  const ConfirmPage({
    required this.service,
    required this.draft,
    this.step,
    super.key,
  });

  final AssistantService service;
  final AssistantTurn draft;

  /// Có giá trị khi một câu nói gồm nhiều việc: "Việc 2/3".
  final ({int index, int total})? step;

  @override
  State<ConfirmPage> createState() => _ConfirmPageState();
}

class _ItemRow {
  _ItemRow({required String name, required String qty, required String unit})
    : name = TextEditingController(text: name),
      qty = TextEditingController(text: qty),
      unit = TextEditingController(text: unit);

  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController unit;

  /// Các trường gốc khác của món (giữ nguyên khi gửi lên).
  Map<String, Object?> extra = {};

  /// Hạn sử dụng riêng của món (inventory.add).
  DateTime? expiry;

  /// Giá mua và nơi cất (tùy chọn, inventory.add).
  final PriceLocationController details = PriceLocationController();

  /// Điền sẵn giá/nơi cất trợ lý nghe được từ lời nói (nếu có).
  _ItemRow withDetailsFrom(Map<Object?, Object?> source) {
    final price = source['priceVnd'];
    if (price is num && price >= 0) details.price.text = '${price.round()}';
    final place = source['storageLocation'];
    if (place is String) details.location = place;
    return this;
  }

  void dispose() {
    details.dispose();
    name.dispose();
    qty.dispose();
    unit.dispose();
  }
}

class _ConfirmPageState extends State<ConfirmPage> {
  late final ToolCall? _tool;
  late final Map<String, Object?> _args;
  final List<_ItemRow> _rows = [];
  // Hạn sử dụng nằm trên từng dòng; `_expiry` là dòng đầu (bản nháp một món).
  DateTime? get _expiry => _rows.isEmpty ? null : _rows.first.expiry;
  set _expiry(DateTime? value) {
    if (_rows.isNotEmpty) _rows.first.expiry = value;
  }

  bool get _batchAdd => _toolId == 'inventory.add' && _args['items'] is List;
  bool _serverBlockedBatch = false;
  bool _addToShopping = false;
  bool _partial =
      false; // mark_out: false = hết toàn bộ, true = chỉ trừ một phần
  double? _stock; // số đang còn trong kho (nếu tra được)
  String? _stockUnit;
  bool _busy = false;
  String? _error;
  String? _fieldError;

  bool get _merchant => widget.service.currentRole == AccountRole.merchant;

  /// Cửa hàng gọi là "kho" và "cần nhập"; gia đình gọi là "tủ đồ" và "đi chợ".
  String get _placeName => _merchant ? tr('kho') : tr('tủ đồ');
  String get _listName =>
      _merchant ? tr('danh sách cần nhập') : tr('danh sách đi chợ');

  String get _toolId => _tool?.toolId ?? '';
  bool get _isWrite => widget.draft.isWriteDraft && _tool != null;

  @override
  void initState() {
    super.initState();
    _tool = widget.draft.toolsProposed.isNotEmpty
        ? widget.draft.toolsProposed.first
        : null;
    _args = _tool?.arguments ?? <String, Object?>{};

    switch (_toolId) {
      case 'inventory.add':
        final batch = _args['items'];
        if (batch is List && batch.whereType<Map>().isNotEmpty) {
          for (final raw in batch.whereType<Map>()) {
            final item = raw.map((k, v) => MapEntry(k.toString(), v));
            _rows.add(
              _ItemRow(
                  name: _text(item['productName']),
                  qty: _fmtNum(item['quantity']),
                  unit: _text(item['unit']),
                )
                ..extra = item
                ..withDetailsFrom(item)
                ..expiry = DateTime.tryParse(_text(item['expiryDate'])),
            );
          }
        } else {
          _rows.add(
            _ItemRow(
              name: _text(_args['productName']),
              qty: _fmtNum(_args['quantity']),
              unit: _text(_args['unit']),
            ).withDetailsFrom(_args),
          );
          _expiry = DateTime.tryParse(_text(_args['expiryDate']));
        }
        _initGate();
      case 'inventory.set_expiry':
        _rows.add(
          _ItemRow(
            name: _text(_args['productName']),
            qty: _fmtNum(_args['quantity']),
            unit: '',
          )..expiry = DateTime.tryParse(_text(_args['expiryDate'])),
        );
        _loadStock();
      case 'inventory.mark_out':
        _rows.add(
          _ItemRow(
            name: _text(_args['productName']),
            qty: _fmtNum(_args['quantity']),
            unit: '',
          ),
        );
        _addToShopping = _args['addToShoppingList'] == true;
        _partial = _args['quantity'] != null;
        _loadStock();
      case 'shopping.skip':
        final skipItems = _args['items'];
        if (skipItems is List) {
          for (final raw in skipItems.whereType<Map>()) {
            final item = raw.map((k, v) => MapEntry(k.toString(), v));
            _rows.add(
              _ItemRow(name: _text(item['name']), qty: '', unit: '')
                ..extra = item,
            );
          }
        }
      case 'shopping.add':
        final items = _args['items'];
        if (items is List && items.isNotEmpty) {
          for (final raw in items.whereType<Map>()) {
            final item = raw.map((k, v) => MapEntry(k.toString(), v));
            _rows.add(
              _ItemRow(
                name: _text(item['name']),
                qty: _fmtNum(item['quantity']),
                unit: _text(item['unit']),
              )..extra = item,
            );
          }
        } else {
          _rows.add(
            _ItemRow(
              name: _text(_args['name']),
              qty: _fmtNum(_args['quantity']),
              unit: _text(_args['unit']),
            ),
          );
        }
    }
  }

  /// Tra số đang còn của món để người dùng biết mình đang trừ bao nhiêu.
  Future<void> _loadStock() async {
    final id = _text(_args['productId']);
    if (id.isEmpty) return;
    try {
      final items = await widget.service.getInventory();
      final item = items.where((i) => i.productId == id).firstOrNull;
      if (item != null && mounted) {
        setState(() {
          _stock = item.quantity;
          _stockUnit = item.unit;
        });
      }
    } catch (_) {
      // Không tra được thì bỏ qua: vẫn lưu được bình thường.
    }
  }

  // ── Chặn thêm sản phẩm mới khi gói đã đủ ──────────────────────────────

  HomeSummary? _home;
  List<InventoryItem> _inventory = const [];
  // Server từ chối PLAN_LIMIT cho tên này (khi chưa có HomeSummary cục bộ).
  String? _serverBlockedName;
  String _serverPlan = 'free';
  int _serverLimit = 30;

  void _initGate() {
    widget.service.dataChanges.addListener(_loadGateData);
    for (final row in _rows) {
      row.name.addListener(_onNameChanged);
    }
    _loadGateData();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  void _loadGateData() {
    try {
      final home = widget.service.getHomeSummary();
      final now = syncValue(home);
      if (now != null) {
        _home = now;
      } else {
        home.then((v) {
          if (mounted) setState(() => _home = v);
        }, onError: (Object _) {});
      }
    } catch (_) {}
    try {
      final inv = widget.service.getInventory();
      final now = syncValue(inv);
      if (now != null) {
        _inventory = now;
      } else {
        inv.then((v) {
          if (mounted) setState(() => _inventory = v);
        }, onError: (Object _) {});
      }
    } catch (_) {}
    if (mounted && _tool != null) setState(() {});
  }

  PlanGateResult get _gate {
    if (_toolId != 'inventory.add' || _rows.isEmpty) {
      return PlanGateResult.allowed;
    }
    final home = _home;
    for (final row in _rows) {
      final name = row.name.text;
      if (home != null) {
        final local = PlanGate.checkAddProduct(
          home: home,
          inventory: _inventory,
          productName: name,
        );
        if (local != PlanGateResult.allowed) return local;
      }
      if (_serverBlockedBatch ||
          (_serverBlockedName != null &&
              _serverBlockedName == PlanGate.normalize(name))) {
        return _serverPlan == 'free'
            ? PlanGateResult.blockedFree
            : PlanGateResult.blockedPaidLimit;
      }
    }
    return PlanGateResult.allowed;
  }

  void _openPaywall() => PaywallSheet.show(
    context,
    service: widget.service,
    source: 'limit_reached',
  );

  @override
  void dispose() {
    if (_toolId == 'inventory.add') {
      widget.service.dataChanges.removeListener(_loadGateData);
    }
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  static String _text(Object? v) => v == null ? '' : v.toString().trim();

  static String _fmtNum(Object? v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return '';
  }

  static double? _parseQty(String s) => parseQuantity(s);

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Câu tóm tắt dễ hiểu theo giá trị đang nhập.
  Iterable<String> get _entityLabels => [
    ..._rows.map((row) => row.name.text),
    ...PlanBillingVisibility.entityLabels([
      widget.draft.data,
      ...widget.draft.toolsProposed.map((tool) => tool.arguments),
    ]),
  ];

  String get _summary {
    if (!_isWrite) {
      return widget.draft.message.isNotEmpty
          ? widget.draft.message
          : tr('HomeMind đã xử lý câu lệnh của bạn.');
    }
    switch (_toolId) {
      case 'inventory.add':
        if (_batchAdd) {
          final names = _rows
              .map((r) => r.name.text.trim())
              .where((n) => n.isNotEmpty)
              .join(', ');
          return names.isEmpty
              ? tr('Thêm vào {0}', [_placeName])
              : tr('Thêm vào {0}: {1}', [_placeName, names]);
        }
        final r = _rows.first;
        final qty = _parseQty(r.qty.text);
        final what = [
          if (qty != null) _fmtNum(qty),
          if (r.unit.text.trim().isNotEmpty) r.unit.text.trim(),
          r.name.text.trim().isEmpty ? tr('món mới') : r.name.text.trim(),
        ].join(' ');
        final exp = _expiry != null
            ? tr(', hạn {0}', [_fmtDate(_expiry!)])
            : '';
        return tr('Thêm {0} vào {1}{2}', [what, _placeName, exp]);
      case 'inventory.set_expiry':
        final r = _rows.first;
        final name = r.name.text.trim().isEmpty
            ? tr('món này')
            : r.name.text.trim();
        final qty = _parseQty(r.qty.text);
        final what = qty == null ? name : '${_fmtNum(qty)} $name';
        return _expiry == null
            ? tr('Đặt hạn sử dụng cho {0}', [what])
            : tr('Đặt hạn {0} cho {1}', [_fmtDate(_expiry!), what]);
      case 'inventory.mark_out':
        final r = _rows.first;
        final name = r.name.text.trim().isEmpty
            ? tr('món này')
            : r.name.text.trim();
        final qty = _partial ? _parseQty(r.qty.text) : null;
        final base = qty == null
            ? tr('Đánh dấu hết {0}', [name])
            : tr('Trừ {0} {1}', [_fmtNum(qty), name]);
        return _addToShopping
            ? tr('{0} và thêm vào {1}', [base, _listName])
            : base;
      case 'shopping.skip':
        final skipped = _rows
            .map((r) => r.name.text.trim())
            .where((n) => n.isNotEmpty)
            .join(', ');
        return tr('Bỏ qua khỏi {0}: {1}', [_listName, skipped]);
      case 'shopping.add':
        final names = _rows
            .map((r) => r.name.text.trim())
            .where((n) => n.isNotEmpty)
            .join(', ');
        return names.isEmpty
            ? tr('Thêm vào {0}', [_listName])
            : tr('Thêm vào {0}: {1}', [_listName, names]);
      default:
        return widget.draft.message;
    }
  }

  Map<String, Object?>? _buildArguments() {
    final args = Map<String, Object?>.from(_args);
    switch (_toolId) {
      case 'inventory.add':
        if (_batchAdd) {
          final items = <Map<String, Object?>>[];
          for (final r in _rows) {
            final name = r.name.text.trim();
            final qty = _parseQty(r.qty.text);
            if (name.isEmpty) {
              _fieldError = tr('Có món chưa có tên. Hãy nhập tên món.');
              return null;
            }
            if (r.qty.text.trim().isNotEmpty && (qty == null || qty <= 0)) {
              _fieldError = tr(
                'Số lượng của "{0}" chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).',
                [name],
              );
              return null;
            }
            if (r.details.priceInvalid) {
              _fieldError = tr(
                'Chưa đọc được số tiền của "{0}". Bạn nhập lại hoặc để trống nhé.',
                [name],
              );
              return null;
            }
            items.add({
              ...r.extra
                ..remove('priceVnd')
                ..remove('storageLocation'),
              'productName': name,
              // Chỉ tên là bắt buộc: số lượng/đơn vị để trống thì gửi null.
              'quantity': qty,
              'unit': r.unit.text.trim().isEmpty ? null : r.unit.text.trim(),
              'expiryDate': r.expiry == null ? null : _isoDate(r.expiry!),
              ...r.details.toArguments(),
            });
          }
          args['items'] = items;
          return args;
        }
        final r = _rows.first;
        final qty = _parseQty(r.qty.text);
        if (r.name.text.trim().isEmpty) {
          _fieldError = tr('Bạn chưa nhập tên món.');
          return null;
        }
        if (r.qty.text.trim().isNotEmpty && (qty == null || qty <= 0)) {
          _fieldError = tr(
            'Số lượng chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).',
          );
          return null;
        }
        if (r.details.priceInvalid) {
          _fieldError = tr(
            'Chưa đọc được số tiền. Bạn nhập lại hoặc để trống nhé.',
          );
          return null;
        }
        args
          ..remove('priceVnd')
          ..remove('storageLocation');
        args['productName'] = r.name.text.trim();
        args['quantity'] = qty;
        args['unit'] = r.unit.text.trim().isEmpty ? null : r.unit.text.trim();
        args['expiryDate'] = _expiry == null ? null : _isoDate(_expiry!);
        args.addAll(r.details.toArguments());
      case 'inventory.set_expiry':
        final r = _rows.first;
        if (_expiry == null) {
          _fieldError = tr('Hãy chọn hạn sử dụng.');
          return null;
        }
        final qtyText = r.qty.text.trim();
        final qty = _parseQty(qtyText);
        if (qtyText.isNotEmpty && (qty == null || qty <= 0)) {
          _fieldError = tr(
            'Số lượng chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).',
          );
          return null;
        }
        if (qty != null && _stock != null && qty > _stock!) {
          _fieldError = tr('Trong kho chỉ còn {0}, ít hơn số bạn nhập.', [
            _fmtNum(_stock),
          ]);
          return null;
        }
        args['quantity'] = qty;
        args['expiryDate'] = _isoDate(_expiry!);
      case 'inventory.mark_out':
        final r = _rows.first;
        if (_partial) {
          final qty = _parseQty(r.qty.text);
          if (qty == null || qty <= 0) {
            _fieldError = tr('Hãy nhập số lượng đã trừ (lớn hơn 0).');
            return null;
          }
          if (_stock != null && qty > _stock!) {
            _fieldError = tr(
              'Trong kho chỉ còn {0}, không thể trừ nhiều hơn.',
              [_fmtNum(_stock)],
            );
            return null;
          }
          args['quantity'] = qty;
        } else {
          args['quantity'] = null; // hết toàn bộ
        }
        args['addToShoppingList'] = _addToShopping;
      case 'shopping.skip':
        if (_rows.isEmpty) {
          _fieldError = tr('Chưa có món nào để bỏ qua.');
          return null;
        }
        args['items'] = [
          for (final r in _rows) {...r.extra},
        ];
      case 'shopping.add':
        final items = <Map<String, Object?>>[];
        for (final r in _rows) {
          final name = r.name.text.trim();
          if (name.isEmpty) {
            _fieldError = tr('Có món chưa có tên. Hãy nhập tên món.');
            return null;
          }
          final qtyText = r.qty.text.trim();
          final qty = _parseQty(qtyText);
          if (qtyText.isNotEmpty && (qty == null || qty <= 0)) {
            _fieldError = tr('Số lượng của "{0}" chưa đúng.', [name]);
            return null;
          }
          final unit = r.unit.text.trim();
          items.add({
            ...r.extra,
            'name': name,
            'quantity': qtyText.isEmpty ? null : qty,
            'unit': unit.isEmpty ? null : unit,
          });
        }
        if (_args['items'] is List) {
          args['items'] = items;
        } else {
          final only = items.first;
          args['name'] = only['name'];
          args['quantity'] = only['quantity'];
          args['unit'] = only['unit'];
        }
    }
    return args;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (!_isWrite) {
      Navigator.of(context).pop();
      return;
    }
    final gate = _gate;
    if (gate != PlanGateResult.allowed) {
      if (gate == PlanGateResult.blockedFree &&
          PlanBillingVisibility.of(context)) {
        _openPaywall();
      }
      return;
    }
    setState(() => _fieldError = null);
    final args = _buildArguments();
    if (args == null) {
      setState(() {});
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.confirm(
        turnId: widget.draft.turnId,
        tools: [ToolCall(toolId: _toolId, arguments: args)],
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      if (e is HomeMindApiException && e.isPlanLimit) {
        final plan = e.details?['plan'];
        final limit = e.details?['limit'];
        setState(() {
          _busy = false;
          _error = null;
          _serverBlockedName = PlanGate.normalize(_rows.first.name.text);
          _serverBlockedBatch = _batchAdd;
          _serverPlan = plan is String ? plan : 'free';
          if (limit is num) _serverLimit = limit.toInt();
        });
        if (_gate == PlanGateResult.blockedFree &&
            PlanBillingVisibility.of(context)) {
          _openPaywall();
        }
        return;
      }
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_isWrite) {
      try {
        await widget.service.cancel(turnId: widget.draft.turnId);
      } catch (_) {
        // Huỷ không thành công cũng không ảnh hưởng: chưa có gì được lưu.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  static String _friendlyError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        raw.contains('Không thể kết nối')) {
      return tr('Không kết nối được mạng. Kiểm tra Wi-Fi rồi thử lại.');
    }
    return tr('Chưa lưu được. Bạn bấm Thử lại nhé.');
  }

  Future<void> _pickDate(_ItemRow row) async {
    final now = DateTime.now();
    final initial = row.expiry ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: tr('Chọn hạn sử dụng'),
      cancelText: tr('Đóng'),
      confirmText: tr('Chọn'),
    );
    if (picked != null && mounted) setState(() => row.expiry = picked);
  }

  // ───────────────────────── Giao diện ─────────────────────────
  // Cùng phong cách trang chủ: nền xám nhạt, thẻ trắng bo mềm có viền + bóng
  // nhẹ, ô icon nhạt, chữ gọn, nút bo tròn.

  InputDecoration _input(String label, {String? hint}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 14, color: HomeMindTheme.textMuted),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        color: HomeMindTheme.primaryDark,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(fontSize: 14, color: HomeMindTheme.textMuted),
      filled: true,
      fillColor: HomeMindTheme.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(HomeMindTheme.border),
      enabledBorder: border(HomeMindTheme.border),
      focusedBorder: border(HomeMindTheme.primary, 1.5),
    );
  }

  static const _fieldStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: HomeMindTheme.textMain,
  );

  Widget _nameField(_ItemRow r, {String? label}) => TextField(
    controller: r.name,
    enabled: !_busy,
    style: _fieldStyle,
    textCapitalization: TextCapitalization.sentences,
    onChanged: (_) => setState(() {}),
    decoration: _input(label ?? tr('Tên món')),
  );

  Widget _choice(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? HomeMindTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? HomeMindTheme.primary : HomeMindTheme.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : HomeMindTheme.textSub,
          ),
        ),
      ),
    );
  }

  Widget _qtyUnitFields(
    _ItemRow r, {
    bool showUnit = true,
    String? qtyHint,
    String? qtyLabel,
    String? unitLabel,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: r.qty,
            enabled: !_busy,
            style: _fieldStyle,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: _input(qtyLabel ?? tr('Số lượng'), hint: qtyHint),
          ),
        ),
        if (showUnit) ...[
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: r.unit,
              enabled: !_busy,
              style: _fieldStyle,
              onChanged: (_) => setState(() {}),
              decoration: _input(
                unitLabel ?? tr('Đơn vị'),
                hint: tr('hộp, kg…'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Ô icon nhạt như trên các thẻ ở trang chủ.
  Widget _iconTile(String emoji, {Color? color}) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color ?? HomeMindTheme.primaryLight,
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Text(emoji, style: const TextStyle(fontSize: 22)),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
      border: Border.all(color: HomeMindTheme.border),
      boxShadow: HomeMindTheme.softShadow,
    ),
    child: child,
  );

  /// Hàng "ô icon + trường nhập tên" ở đầu mỗi thẻ.
  Widget _nameRow(_ItemRow r) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _iconTile(groupOf(name: r.name.text).emoji),
      const SizedBox(width: 12),
      Expanded(child: _nameField(r)),
    ],
  );

  Widget _expiryField(_ItemRow row) {
    final has = row.expiry != null;
    return InkWell(
      onTap: _busy ? null : () => _pickDate(row),
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HomeMindTheme.background,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
          border: Border.all(color: HomeMindTheme.border),
        ),
        child: Row(
          children: [
            _iconTile('📅', color: HomeMindTheme.soonBg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Hạn sử dụng'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HomeMindTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    has
                        ? _fmtDate(row.expiry!)
                        : tr('Chưa chọn - bấm để chọn ngày'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: has
                          ? HomeMindTheme.textMain
                          : HomeMindTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (has)
              IconButton(
                tooltip: tr('Xoá hạn sử dụng'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: HomeMindTheme.textMuted,
                ),
                onPressed: _busy
                    ? null
                    : () => setState(() => row.expiry = null),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: HomeMindTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color bg,
    required String text,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  /// Gói đã đủ và tên này là sản phẩm MỚI: chặn lưu (đánh giá lại mỗi lần sửa).
  Widget _limitBanner() {
    final gate = _gate;
    if (gate == PlanGateResult.allowed) return const SizedBox.shrink();
    final home = _home;
    final plan = home?.plan ?? _serverPlan;
    final limit =
        home != null && home.productCountTowardLimit >= home.freePlanLimit
        ? home.freePlanLimit
        : _serverLimit;
    return KeyedSubtree(
      key: const Key('confirm_plan_banner'),
      child: _banner(
        icon: Icons.lock_outline_rounded,
        color: HomeMindTheme.danger,
        bg: HomeMindTheme.urgentBg,
        text: !PlanBillingVisibility.of(context)
            ? tr('Đã đủ {0} sản phẩm. Không thể thêm sản phẩm mới.', [limit])
            : PlanGate.message(gate, plan, limit)!,
      ),
    );
  }

  List<String> get _warnings {
    final out = <String>[...widget.draft.warnings];
    final sources = <Object?>[
      _args['warnings'],
      for (final row in _rows) row.extra['warnings'],
    ];
    for (final w in sources) {
      if (w is! List) continue;
      for (final s in w.whereType<String>()) {
        if (s.trim().isNotEmpty && !out.contains(s.trim())) out.add(s.trim());
      }
    }
    return out;
  }

  Widget _sectionHeader(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: HomeMindTheme.textMain,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: HomeMindTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  /// Bỏ một món khỏi bản nháp nhiều món; server chỉ nhận ít hơn hoặc bằng bản nháp.
  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index).dispose();
      _serverBlockedBatch = false;
    });
  }

  Widget _editor() {
    switch (_toolId) {
      case 'inventory.add':
        return Column(
          children: [
            for (var i = 0; i < _rows.length; i++)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_rows.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: HomeMindTheme.primaryLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                tr('Món {0}', [i + 1]),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: HomeMindTheme.primaryDark,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: tr('Bỏ món này'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: HomeMindTheme.textMuted,
                              ),
                              onPressed: _busy ? null : () => _removeRow(i),
                            ),
                          ],
                        ),
                      ),
                    _nameRow(_rows[i]),
                    const SizedBox(height: 10),
                    _qtyUnitFields(
                      _rows[i],
                      qtyLabel: tr('Số lượng (tuỳ chọn)'),
                      unitLabel: tr('Đơn vị (tuỳ chọn)'),
                    ),
                    const SizedBox(height: 10),
                    _expiryField(_rows[i]),
                    const SizedBox(height: 10),
                    PriceLocationFields(
                      controller: _rows[i].details,
                      merchant: _merchant,
                      enabled: !_busy,
                      quantity: _parseQty(_rows[i].qty.text),
                      unit: _rows[i].unit.text,
                      onChanged: () => setState(() => _fieldError = null),
                    ),
                  ],
                ),
              ),
          ],
        );
      case 'inventory.set_expiry':
        final r = _rows.first;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _nameRow(r),
              if (_stock != null) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Hiện còn {0}', [
                    '${_fmtNum(_stock)} ${_stockUnit ?? ''}'.trim(),
                  ]),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: HomeMindTheme.primaryDark,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _qtyUnitFields(
                r,
                showUnit: false,
                qtyLabel: tr('Số lượng có hạn này'),
                qtyHint: tr('Bỏ trống = tất cả'),
              ),
              const SizedBox(height: 10),
              _expiryField(r),
            ],
          ),
        );
      case 'inventory.mark_out':
        final r = _rows.first;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _nameRow(r),
              if (_stock != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: HomeMindTheme.primaryLight,
                    borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Text('📦', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        tr('Hiện còn {0}', [
                          '${_fmtNum(_stock)} ${_stockUnit ?? ''}'.trim(),
                        ]),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HomeMindTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _choice(
                      tr('Hết toàn bộ'),
                      selected: !_partial,
                      onTap: () => setState(() => _partial = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _choice(
                      tr('Chỉ trừ một phần'),
                      selected: _partial,
                      onTap: () => setState(() => _partial = true),
                    ),
                  ),
                ],
              ),
              if (_partial) ...[
                const SizedBox(height: 10),
                _qtyUnitFields(
                  r,
                  showUnit: false,
                  qtyLabel: tr('Số lượng đã trừ'),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                decoration: BoxDecoration(
                  color: HomeMindTheme.background,
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  border: Border.all(color: HomeMindTheme.border),
                ),
                child: Row(
                  children: [
                    _iconTile('🛒', color: HomeMindTheme.soonBg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('Thêm vào {0}', [_listName]),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                    ),
                    Switch(
                      value: _addToShopping,
                      activeThumbColor: Colors.white,
                      activeTrackColor: HomeMindTheme.primary,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _addToShopping = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'shopping.skip':
        return Column(
          children: [
            for (var i = 0; i < _rows.length; i++)
              _card(
                child: Row(
                  children: [
                    _iconTile(groupOf(name: _rows[i].name.text).emoji),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _rows[i].name.text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                    ),
                    if (_rows.length > 1)
                      IconButton(
                        tooltip: tr('Bỏ món này'),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: HomeMindTheme.textMuted,
                        ),
                        onPressed: _busy ? null : () => _removeRow(i),
                      ),
                  ],
                ),
              ),
          ],
        );
      case 'shopping.add':
        return Column(
          children: [
            for (var i = 0; i < _rows.length; i++)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_rows.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: HomeMindTheme.primaryLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tr('Món {0}', [i + 1]),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: HomeMindTheme.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    _nameRow(_rows[i]),
                    const SizedBox(height: 10),
                    _qtyUnitFields(_rows[i]),
                  ],
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Nút tròn trắng có viền như các nút ở đầu trang chủ.
  Widget _backButton() => Material(
    color: Colors.white,
    shape: const CircleBorder(side: BorderSide(color: HomeMindTheme.border)),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: _busy ? null : _cancel,
      child: Tooltip(
        message: tr('Quay lại'),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: HomeMindTheme.textMain,
          ),
        ),
      ),
    ),
  );

  Widget _summaryCard(String spoken) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [HomeMindTheme.primaryLight, HomeMindTheme.primaryTint],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusXl),
      border: Border.all(color: HomeMindTheme.normalBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.mic_rounded,
            color: HomeMindTheme.primaryDark,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PlanBillingVisibility.message(
                  context,
                  _summary,
                  fallback: tr('HomeMind đã xử lý câu lệnh của bạn.'),
                  preservedValues: _entityLabels,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: HomeMindTheme.textMain,
                  height: 1.3,
                ),
              ),
              if (spoken.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  tr('Bạn đã nói: “{0}”', [spoken]),
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: HomeMindTheme.textSub,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  /// Thanh nút cố định ở đáy, bo góc như thanh tab của app.
  Widget _bottomBar() {
    final gate = _gate;
    return _bottomBarFor(gate);
  }

  Widget _bottomBarFor(PlanGateResult gate) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: _isWrite
          ? Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: HomeMindTheme.border),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        tr('Huỷ'),
                        style: const TextStyle(
                          fontSize: 15,
                          color: HomeMindTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (gate != PlanGateResult.blockedFree ||
                    PlanBillingVisibility.of(context)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed:
                            _busy || gate == PlanGateResult.blockedPaidLimit
                            ? null
                            : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HomeMindTheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: HomeMindTheme.primary
                              .withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.6,
                                ),
                              )
                            : Text(
                                switch (gate) {
                                  PlanGateResult.blockedFree => tr(
                                    'Xem gói hiện tại',
                                  ),
                                  PlanGateResult.blockedPaidLimit => tr(
                                    'Đã đủ hạn mức',
                                  ),
                                  PlanGateResult.allowed =>
                                    _error != null ? tr('Thử lại') : tr('Lưu'),
                                },
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          : SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HomeMindTheme.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                child: Text(
                  tr('Đã hiểu'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final spoken = widget.draft.correctedInput?.trim() ?? '';
    final warnings = _warnings
        .where(
          (text) =>
              PlanBillingVisibility.of(context) ||
              !PlanBillingVisibility.isBillingText(
                text,
                preservedValues: _entityLabels,
              ),
        )
        .toList();

    return Scaffold(
      backgroundColor: HomeMindTheme.background,
      bottomNavigationBar: _bottomBar(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  _backButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isWrite
                          ? tr('Kiểm tra lại trước khi lưu')
                          : tr('Kết quả'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: HomeMindTheme.textMain,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.step != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  header: true,
                  child: Text(
                    tr('Việc {0}/{1} trong câu bạn vừa nói', [
                      widget.step!.index,
                      widget.step!.total,
                    ]),
                    key: const Key('confirm_step'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.primaryDark,
                    ),
                  ),
                ),
              ),
            _summaryCard(spoken),
            if (_isWrite) ...[
              _sectionHeader(
                tr('Chi tiết'),
                tr('Chạm vào ô để sửa nếu chưa đúng'),
              ),
              _editor(),
            ],
            if (_toolId == 'inventory.add') _limitBanner(),
            if (warnings.isNotEmpty)
              _banner(
                icon: Icons.info_outline_rounded,
                color: const Color(0xFF92400E),
                bg: HomeMindTheme.soonBg,
                text: warnings.join('\n'),
              ),
            if (_fieldError != null)
              _banner(
                icon: Icons.edit_note_rounded,
                color: HomeMindTheme.danger,
                bg: HomeMindTheme.urgentBg,
                text: _fieldError!,
              ),
            if (_error != null)
              _banner(
                icon: Icons.error_outline_rounded,
                color: HomeMindTheme.danger,
                bg: HomeMindTheme.urgentBg,
                text: PlanBillingVisibility.message(context, _error!),
              ),
          ],
        ),
      ),
    );
  }
}
