import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/l10n/app_text.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import '../../billing/billing_widgets.dart';

class VoiceQuotaPanel extends StatefulWidget {
  const VoiceQuotaPanel({
    required this.service,
    this.billingPresentation = false,
    super.key,
  });
  final AssistantService service;
  final bool billingPresentation;
  @override
  State<VoiceQuotaPanel> createState() => _VoiceQuotaPanelState();
}

class _VoiceQuotaPanelState extends State<VoiceQuotaPanel>
    with WidgetsBindingObserver {
  VoiceQuota? _quota;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.dataChanges.addListener(_changed);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void didUpdateWidget(covariant VoiceQuotaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.dataChanges.removeListener(_changed);
      widget.service.dataChanges.addListener(_changed);
      _quota = null;
      _load();
    }
  }

  void _changed() {
    // Consume the existing committed cache; don't recursively refresh on every notification.
    final generation = ++_generation;
    widget.service.getMe().then((profile) {
      if (mounted && generation == _generation) {
        setState(() {
          _quota = profile.voiceQuota;
          _failed = profile.voiceQuota == null;
        });
      }
    }, onError: (Object _) {});
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final service = widget.service;
      final quota = service is VoiceQuotaSource
          ? await (service as VoiceQuotaSource).getVoiceQuota()
          : (await service.getMe()).voiceQuota;
      if (mounted && generation == _generation) {
        setState(() {
          _quota = quota;
          _failed = quota == null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    widget.service.dataChanges.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    if (widget.billingPresentation && quota != null) {
      return BillingUsageCard(
        plan: quota.plan,
        used: quota.used,
        total: quota.total,
        remaining: quota.remaining,
        expiresAt: quota.expiresAt,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              PlanBillingVisibility.of(context)
                  ? 'Lượt trợ lý của gói đang dùng'
                  : 'Lượt trợ lý trong kỳ',
            ),
          ),
          if (_failed)
            TextButton(
              onPressed: _load,
              child: Text(tr('Chưa tải được hạn mức trợ lý. Hãy thử lại.')),
            )
          else if (quota == null)
            const LinearProgressIndicator()
          else ...[
            Text(
              '${quota.used}/${quota.total}',
              key: const Key('voice_quota_used_total'),
            ),
            LinearProgressIndicator(
              value: quota.used / quota.total,
              minHeight: 8,
            ),
            Text(tr('Còn {0} lượt trong kỳ', [quota.remaining])),
            Text(
              tr('Lượt dùng làm mới lúc: {0}', [
                quota.expiresAt.toLocal().toString().split('.').first,
              ]),
            ),
            Text(
              tr(
                'Lượt dùng chung trong workspace. Kết quả trợ lý hợp lệ, gồm câu gõ, tính một lượt; xác nhận hoặc hủy không tính thêm.',
              ),
            ),
            if (quota.remaining == 0)
              Text(
                tr(
                  PlanBillingVisibility.of(context)
                      ? 'Gói đang dùng đã hết lượt trợ lý trong kỳ này.'
                      : 'Đã hết lượt trợ lý trong kỳ này.',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
