import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';

/// Hộp thoại sau khi bấm báo hết hàng: có thêm món vào danh sách mua/nhập không?
///
/// Trả về `true` (thêm vào danh sách), `false` (chỉ báo hết) hoặc `null`
/// (huỷ, không làm gì).
class RepurchaseDialog extends StatelessWidget {
  const RepurchaseDialog({
    required this.itemName,
    this.merchant = false,
    super.key,
  });

  final String itemName;

  /// Cửa hàng dùng chữ "cần nhập", gia đình dùng "đi chợ".
  final bool merchant;

  static Future<bool?> show(
    BuildContext context,
    String itemName, {
    bool merchant = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) =>
          RepurchaseDialog(itemName: itemName, merchant: merchant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listName = merchant
        ? tr('danh sách cần nhập')
        : tr('danh sách đi chợ');

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusXl),
      ),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: HomeMindTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🛒', style: TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Bạn đã dùng hết {0}', [itemName]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: HomeMindTheme.textMain,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Bạn có muốn thêm món này vào {0} không?', [listName]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: HomeMindTheme.textSub,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // Các nút xếp dọc, rộng đầy để chữ không bao giờ bị che.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HomeMindTheme.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  tr('Thêm vào {0}', [listName]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: HomeMindTheme.border),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  tr('Không, chỉ báo hết'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: HomeMindTheme.textSub,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                tr('Huỷ'),
                style: const TextStyle(
                  fontSize: 14,
                  color: HomeMindTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
