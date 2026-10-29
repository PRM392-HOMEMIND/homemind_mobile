import 'package:flutter/material.dart';

import '../../../core/l10n/app_text.dart';
import '../../../core/money.dart';
import '../../../core/widgets/page_skeleton.dart';
import '../../../app/homemind_theme.dart';
import '../domain/home_hub_gateway.dart';

/// Resolves an actual authorized entity, including rows outside the home cache.
class HubEntityPage extends StatefulWidget {
  const HubEntityPage({required this.gateway, required this.target, super.key});
  final HomeHubGateway gateway;
  final HubTarget target;
  @override
  State<HubEntityPage> createState() => _HubEntityPageState();
}

class _HubEntityPageState extends State<HubEntityPage> {
  late var _data = widget.gateway.entity(widget.target);
  void _retry() => setState(() {
    _data = widget.gateway.entity(widget.target);
  });
  @override
  void didUpdateWidget(covariant HubEntityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway.scope != widget.gateway.scope ||
        oldWidget.target.id != widget.target.id ||
        oldWidget.target.type != widget.target.type) {
      _data = widget.gateway.entity(widget.target);
    }
  }

  String _quantity(Map value) {
    final quantity = value['quantity'], unit = value['unit'];
    return quantity == null
        ? tr('Chưa ghi số lượng')
        : '$quantity${unit is String && unit.isNotEmpty ? ' $unit' : ''}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        tr(widget.target.type == 'inventory' ? 'Sản phẩm' : 'Món cần mua'),
      ),
    ),
    body: FutureBuilder(
      key: ValueKey(
        '${widget.gateway.scope}:${widget.target.type}:${widget.target.id}',
      ),
      future: _data,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Dữ liệu không còn được phép mở hoặc chưa tải được.'),
                  textAlign: TextAlign.center,
                ),
                TextButton(onPressed: _retry, child: Text(tr('Tải lại'))),
              ],
            ),
          );
        }
        if (!s.hasData) {
          return const SingleChildScrollView(
            child: PageSkeleton(SkeletonPage.inventoryDetail),
          );
        }
        final data = s.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              data['name'] as String,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Text(
              tr('Trạng thái: {0}', [
                tr(switch (data['status']) {
                  'in_stock' => 'Còn hàng',
                  'out' => 'Đã hết hàng',
                  'needed' => 'Cần mua',
                  'bought' => 'Đã mua',
                  'skipped' => 'Bỏ qua',
                  _ => 'Chưa rõ',
                }),
              ]),
            ),
            if (data['quantity'] != null) Text(_quantity(data)),
            if (data['category'] != null)
              Text(tr('Danh mục: {0}', [data['category']])),
            if (s.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            for (final lot in (data['lots'] as List?) ?? []) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HomeMindTheme.card,
                  border: Border.all(color: HomeMindTheme.border),
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _quantity(lot as Map),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Hạn sử dụng: {0}', [
                        lot['expiryDate'] ?? tr('Chưa ghi hạn sử dụng'),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Giá mua: {0}', [
                        lot['priceVnd'] is num
                            ? formatVnd((lot['priceVnd'] as num).toInt())
                            : tr('Chưa ghi giá mua'),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Nơi cất: {0}', [
                        lot['storageLocation'] ?? tr('Chưa ghi nơi cất'),
                      ]),
                    ),
                    if (lot['purchasedAt'] is String) ...[
                      const SizedBox(height: 8),
                      Text(tr('Ngày nhập: {0}', [lot['purchasedAt']])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
