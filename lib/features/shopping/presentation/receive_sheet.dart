import 'package:flutter/material.dart';

import '../../../core/quantity.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../../core/product_groups.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../spending/presentation/price_location_fields.dart';

/// Kết quả người dùng xác nhận khi nhận hàng về.
class ReceiveResult {
  const ReceiveResult({
    this.quantity,
    this.unit,
    this.expiryDate,
    this.priceVnd,
    this.storageLocation,
  });

  /// Cả hai đều tùy chọn: để trống thì chỉ ghi nhận là đã có hàng.
  final double? quantity;
  final String? unit;

  /// Tổng tiền đã mua (VND) và nơi cất; cả hai tùy chọn.
  final int? priceVnd;
  final String? storageLocation;

  /// Định dạng yyyy-MM-dd, hoặc null nếu không có hạn.
  final String? expiryDate;
}

/// Khung hỏi nhanh khi món trong danh sách mua đã về: số lượng thực nhận,
/// đơn vị, hạn dùng. Xác nhận xong món được cất vào kho/tủ đồ.
class ReceiveSheet extends StatefulWidget {
  const ReceiveSheet({
    required this.item,
    required this.merchant,
    this.initialLocation,
    super.key,
  });

  final ShoppingItem item;
  final bool merchant;

  /// Nơi cất gần nhất của món này (nếu đã có trong kho) để điền sẵn.
  final String? initialLocation;

  static Future<ReceiveResult?> show(
    BuildContext context, {
    required ShoppingItem item,
    required bool merchant,
    String? initialLocation,
  }) {
    return showModalBottomSheet<ReceiveResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceiveSheet(
        item: item,
        merchant: merchant,
        initialLocation: initialLocation,
      ),
    );
  }

  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<ReceiveSheet> {
  late final TextEditingController _qty;
  late final TextEditingController _unit;
  late final PriceLocationController _details;
  DateTime? _expiry;
  String? _error;

  @override
  void initState() {
    super.initState();
    final q = widget.item.quantity;
    _qty = TextEditingController(
      text: q == null ? '' : (q == q.roundToDouble() ? '${q.toInt()}' : '$q'),
    );
    _unit = TextEditingController(text: widget.item.unit ?? '');
    _details = PriceLocationController(location: widget.initialLocation);
  }

  @override
  void dispose() {
    _qty.dispose();
    _unit.dispose();
    _details.dispose();
    super.dispose();
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: tr('Chọn hạn sử dụng'),
      cancelText: tr('Đóng'),
      confirmText: tr('Chọn'),
    );
    if (picked != null && mounted) setState(() => _expiry = picked);
  }

  void _save() {
    final qtyText = _qty.text.trim();
    final qty = qtyText.isEmpty ? null : parseQuantity(qtyText);
    if (qtyText.isNotEmpty && (qty == null || qty <= 0)) {
      setState(
        () => _error = tr(
          'Số lượng chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).',
        ),
      );
      return;
    }
    final unit = _unit.text.trim().isEmpty ? null : _unit.text.trim();
    if (_details.priceInvalid) {
      setState(
        () => _error = tr(
          'Chưa đọc được số tiền. Bạn nhập lại hoặc để trống nhé.',
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      ReceiveResult(
        quantity: qty,
        unit: unit,
        expiryDate: _expiry == null ? null : _iso(_expiry!),
        priceVnd: _details.priceVnd,
        storageLocation: _details.location,
      ),
    );
  }

  InputDecoration _input(String label) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 14, color: HomeMindTheme.textMuted),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        color: HomeMindTheme.primaryDark,
        fontWeight: FontWeight.w700,
      ),
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

  @override
  Widget build(BuildContext context) {
    final has = _expiry != null;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: HomeMindTheme.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: HomeMindTheme.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        groupOf(name: widget.item.name).emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.merchant ? tr('Đã nhập hàng') : tr('Đã mua'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: HomeMindTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.item.name,
                            style: const TextStyle(
                              fontSize: 13,
                              color: HomeMindTheme.textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Text(
                    widget.merchant
                        ? tr(
                            'Nhập số lượng thực tế đã nhập. HomeMind tự cập nhật vào kho cho bạn.',
                          )
                        : tr(
                            'Nhập số lượng thực tế đã mua. HomeMind tự cập nhật vào tủ đồ cho bạn.',
                          ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HomeMindTheme.textMuted,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('receive_quantity'),
                        controller: _qty,
                        style: _fieldStyle,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() => _error = null),
                        decoration: _input(
                          widget.merchant
                              ? tr('Số lượng đã nhập (tuỳ chọn)')
                              : tr('Số lượng đã mua (tuỳ chọn)'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('receive_unit'),
                        controller: _unit,
                        style: _fieldStyle,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: _input(tr('Đơn vị (tuỳ chọn)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: HomeMindTheme.background,
                      borderRadius: BorderRadius.circular(
                        HomeMindTheme.radiusMd,
                      ),
                      border: Border.all(color: HomeMindTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Text('📅', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Hạn sử dụng (nếu có)'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: HomeMindTheme.textMuted,
                                ),
                              ),
                              Text(
                                has
                                    ? _fmtDate(_expiry!)
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
                            onPressed: () => setState(() => _expiry = null),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                PriceLocationFields(
                  controller: _details,
                  merchant: widget.merchant,
                  initiallyExpanded: true,
                  quantity: double.tryParse(
                    _qty.text.trim().replaceAll(',', '.'),
                  ),
                  unit: _unit.text,
                  onChanged: () => setState(() => _error = null),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: HomeMindTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
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
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          key: const Key('receive_submit'),
                          onPressed: _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HomeMindTheme.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          child: Text(
                            widget.merchant
                                ? tr('Xác nhận đã nhập')
                                : tr('Xác nhận đã mua'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
