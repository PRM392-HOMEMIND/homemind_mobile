import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../../core/money.dart';

/// Trạng thái giá + nơi cất (cả hai đều tùy chọn) của một lần nhập hàng.
class PriceLocationController extends ChangeNotifier {
  PriceLocationController({String? location}) {
    _location = location;
  }

  final TextEditingController price = TextEditingController();
  String? _location;

  String? get location => _location;
  set location(String? value) {
    final trimmed = value?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (next == _location) return;
    _location = next;
    notifyListeners();
  }

  /// Null khi để trống hoặc không đọc được (xem [priceInvalid]).
  int? get priceVnd => parseVnd(price.text);
  bool get priceInvalid => price.text.trim().isNotEmpty && priceVnd == null;

  /// Phần thêm vào payload: chỉ có khóa khi người dùng thực sự nhập.
  Map<String, Object?> toArguments() => {
    if (priceVnd != null) 'priceVnd': priceVnd,
    if (_location != null) 'storageLocation': _location,
  };

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }
}

const _householdPlaces = [
  'Tủ lạnh',
  'Ngăn đá',
  'Tủ bếp',
  'Kệ khô',
  'Phòng tắm',
];
const _merchantPlaces = ['Quầy kệ', 'Kho sau', 'Tủ mát', 'Tủ đông'];

/// Hai ô tùy chọn: tổng tiền đã mua và nơi cất. Thu gọn mặc định để màn xác
/// nhận nhiều món không bị dài; tự mở khi đã có dữ liệu hoặc [initiallyExpanded].
class PriceLocationFields extends StatefulWidget {
  const PriceLocationFields({
    required this.controller,
    this.quantity,
    this.unit,
    this.merchant = false,
    this.enabled = true,
    this.initiallyExpanded = false,
    this.collapsible = true,
    this.onChanged,
    super.key,
  });

  final PriceLocationController controller;

  /// Để gợi ý đơn giá ("≈ 22.500 ₫ / hộp") khi đã biết số lượng.
  final double? quantity;
  final String? unit;
  final bool merchant;
  final bool enabled;
  final bool initiallyExpanded;

  /// false: luôn mở, không có thanh tiêu đề (dùng trong hộp thoại chỉ để nhập giá).
  final bool collapsible;
  final VoidCallback? onChanged;

  @override
  State<PriceLocationFields> createState() => _PriceLocationFieldsState();
}

class _PriceLocationFieldsState extends State<PriceLocationFields> {
  late bool _open;
  bool _custom = false;
  final _customController = TextEditingController();

  PriceLocationController get _c => widget.controller;
  List<String> get _places =>
      widget.merchant ? _merchantPlaces : _householdPlaces;

  @override
  void initState() {
    super.initState();
    _open =
        !widget.collapsible ||
        widget.initiallyExpanded ||
        _c.price.text.trim().isNotEmpty ||
        _c.location != null;
    final location = _c.location;
    if (location != null && !_places.contains(location)) {
      _custom = true;
      _customController.text = location;
    }
    _c.addListener(_rebuild);
  }

  @override
  void dispose() {
    _c.removeListener(_rebuild);
    _customController.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _priceChanged() {
    setState(() {});
    widget.onChanged?.call();
  }

  String? get _summary {
    final parts = <String>[
      if (_c.priceVnd != null) formatVnd(_c.priceVnd!),
      if (_c.location != null) _c.location!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _unitPriceHint {
    final price = _c.priceVnd, qty = widget.quantity;
    if (price == null || qty == null || qty <= 0 || qty == 1) return null;
    final unit = (widget.unit ?? '').trim();
    final each = formatVnd((price / qty).round());
    return unit.isEmpty
        ? tr('≈ {0} mỗi đơn vị', [each])
        : tr('≈ {0} / {1}', [each, unit]);
  }

  OutlineInputBorder _border() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
    borderSide: const BorderSide(color: HomeMindTheme.border),
  );

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Container(
      decoration: BoxDecoration(
        color: HomeMindTheme.primaryTint,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        border: Border.all(color: HomeMindTheme.normalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.collapsible)
            Semantics(
              button: true,
              expanded: _open,
              child: InkWell(
                key: const Key('price_location_toggle'),
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                onTap: widget.enabled
                    ? () => setState(() => _open = !_open)
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text('🏷️', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                tr('Giá mua & nơi cất'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: HomeMindTheme.textMain,
                                ),
                              ),
                              Text(
                                summary ?? tr('Không bắt buộc'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: summary == null
                                      ? HomeMindTheme.textMuted
                                      : HomeMindTheme.primaryStrong,
                                  fontWeight: summary == null
                                      ? FontWeight.w400
                                      : FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _open
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: HomeMindTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('price_field'),
                    controller: _c.price,
                    enabled: widget.enabled,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HomeMindTheme.textMain,
                    ),
                    onChanged: (_) => _priceChanged(),
                    decoration: InputDecoration(
                      labelText: tr('Tổng tiền đã mua'),
                      hintText: tr('VD: 45000, 45k, 1,2tr'),
                      suffixText: '₫',
                      errorText: _c.priceInvalid
                          ? tr('Chưa đọc được số tiền')
                          : null,
                      helperText: _unitPriceHint,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: _border(),
                      enabledBorder: _border(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Nơi cất'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HomeMindTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final place in _places)
                        ChoiceChip(
                          label: Text(tr(place)),
                          selected: !_custom && _c.location == place,
                          showCheckmark: false,
                          selectedColor: HomeMindTheme.primaryLight,
                          onSelected: widget.enabled
                              ? (on) {
                                  setState(() => _custom = false);
                                  _c.location = on ? place : null;
                                  widget.onChanged?.call();
                                }
                              : null,
                        ),
                      ChoiceChip(
                        key: const Key('location_other'),
                        label: Text(tr('Khác…')),
                        selected: _custom,
                        showCheckmark: false,
                        selectedColor: HomeMindTheme.primaryLight,
                        onSelected: widget.enabled
                            ? (on) {
                                setState(() => _custom = on);
                                _c.location = on
                                    ? _customController.text
                                    : null;
                                widget.onChanged?.call();
                              }
                            : null,
                      ),
                    ],
                  ),
                  if (_custom) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('location_custom'),
                      controller: _customController,
                      enabled: widget.enabled,
                      maxLength: 60,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (value) {
                        _c.location = value;
                        widget.onChanged?.call();
                      },
                      decoration: InputDecoration(
                        hintText: tr('VD: Tủ gỗ phòng khách'),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: _border(),
                        enabledBorder: _border(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
