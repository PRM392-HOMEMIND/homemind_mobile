import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../assistant/domain/assistant_models.dart';
import 'price_location_fields.dart';

/// Kết quả nhập nhanh giá/nơi cất cho một lần mua đã lưu.
class PriceEntryResult {
  const PriceEntryResult({this.priceVnd, this.storageLocation});
  final int? priceVnd;
  final String? storageLocation;
}

/// Khung nhập giá cho một lần mua chưa có giá. Bắt buộc có số tiền hợp lệ
/// (nút Lưu tắt khi để trống); nơi cất vẫn tùy chọn.
class PriceEntrySheet extends StatefulWidget {
  const PriceEntrySheet({
    required this.purchase,
    required this.merchant,
    super.key,
  });

  final UnpricedPurchase purchase;
  final bool merchant;

  static Future<PriceEntryResult?> show(
    BuildContext context, {
    required UnpricedPurchase purchase,
    required bool merchant,
  }) {
    return showModalBottomSheet<PriceEntryResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PriceEntrySheet(purchase: purchase, merchant: merchant),
    );
  }

  @override
  State<PriceEntrySheet> createState() => _PriceEntrySheetState();
}

class _PriceEntrySheetState extends State<PriceEntrySheet> {
  late final PriceLocationController _details;

  @override
  void initState() {
    super.initState();
    _details = PriceLocationController(
      location: widget.purchase.storageLocation,
    );
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _canSave => _details.priceVnd != null;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      PriceEntryResult(
        priceVnd: _details.priceVnd,
        // Chỉ gửi khi người dùng đổi so với giá trị đang có.
        storageLocation: _details.location == widget.purchase.storageLocation
            ? null
            : _details.location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.purchase;
    final d = p.purchasedAt;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
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
                Text(
                  tr('Nhập giá cho "{0}"', [p.name]),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: HomeMindTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('Lần mua ngày {0}', [when]),
                  style: const TextStyle(
                    fontSize: 13,
                    color: HomeMindTheme.textSub,
                  ),
                ),
                const SizedBox(height: 14),
                PriceLocationFields(
                  controller: _details,
                  merchant: widget.merchant,
                  collapsible: false,
                  onChanged: () => setState(() {}),
                ),
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
                            tr('Để sau'),
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
                          key: const Key('price_entry_save'),
                          onPressed: _canSave ? _save : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HomeMindTheme.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          child: Text(
                            tr('Lưu giá'),
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
