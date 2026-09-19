import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/plan_billing_visibility.dart';

import '../core/l10n/app_text.dart';

import '../features/assistant/data/backend_assistant_service.dart';
import '../features/assistant/data/cached_assistant_service.dart';
import '../features/assistant/domain/assistant_models.dart';
import '../features/assistant/domain/assistant_service.dart';
import '../features/assistant/presentation/confirm_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/home/presentation/profile_page.dart';
import '../features/home/presentation/paywall_sheet.dart';
import '../features/auth/domain/auth_service.dart';
import '../features/auth/domain/account_auth_service.dart';
import '../features/auth/presentation/account_settings_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/shopping/presentation/shopping_page.dart';
import '../features/voice/data/native_speech_recognition_service.dart';
import '../features/voice/domain/speech_recognition_service.dart';
import '../features/voice/presentation/voice_sheet.dart';
import 'homemind_theme.dart';
import '../features/spending/presentation/spending_card.dart';
import '../features/spending/presentation/spending_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.assistantService,
    required this.speechService,
    this.profile,
    this.onLogout,
    this.authService,
    super.key,
  });

  final AssistantService assistantService;
  final SpeechRecognitionService speechService;
  final UserProfile? profile;
  final VoidCallback? onLogout;
  final AuthService? authService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0; // 0: Trang chủ, 1: Tủ đồ, 2: Đi chợ, 3: Cá nhân
  final Set<int> _visited = {0}; // tab đã mở thì giữ nguyên trạng thái
  int _inventoryGen = 0; // đổi khi cần dựng lại Tủ đồ với bộ lọc khác
  int _homeGen = 0;
  int _shoppingGen = 0;

  /// Rời một tab thì đặt lại giao diện của nó (bộ lọc, ô tìm kiếm, vị trí cuộn)
  /// về trạng thái ban đầu. Dữ liệu vẫn lấy ngay từ cache nên mở lại không chậm.
  void _resetLeftTab(int leaving) {
    switch (leaving) {
      case 0:
        _homeGen++;
      case 1:
        _inventoryExpiringFirst = false;
        _inventoryGen++;
      case 2:
        _shoppingGen++;
    }
  }

  HomeSummary? _summary; // số liệu cho tab Cá nhân (từ bộ nhớ đệm)
  UserProfile? _profile;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    WidgetsBinding.instance.addObserver(this);
    AppText.language.addListener(_onLanguageChanged);
    widget.assistantService.dataChanges.addListener(_loadSummary);
    _errorSub = widget.assistantService.backgroundErrors.listen(_showError);
    _loadSummary();
    unawaited(_refreshVoiceQuota());
  }

  int _quotaGeneration = 0;
  Future<void> _refreshVoiceQuota() async {
    final source = widget.assistantService;
    final generation = ++_quotaGeneration;
    if (source is! VoiceQuotaSource) return;
    try {
      final quota = await (source as VoiceQuotaSource).getVoiceQuota();
      if (mounted &&
          generation == _quotaGeneration &&
          identical(source, widget.assistantService) &&
          quota != null) {
        setState(() => _profile = _profile?.copyWith(voiceQuota: quota));
      }
    } catch (_) {
      // Opening the mic still requires a fresh authoritative quota response.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshVoiceQuota());
  }

  void _loadSummary() {
    final profileFuture = widget.assistantService.getMe();
    final cachedProfile = syncValue(profileFuture);
    if (cachedProfile != null) {
      if (!identical(cachedProfile, _profile)) {
        if (mounted) {
          setState(() => _profile = cachedProfile);
        } else {
          _profile = cachedProfile;
        }
      }
    } else {
      profileFuture
          .then((profile) {
            if (mounted) setState(() => _profile = profile);
          })
          .catchError((Object _) {});
    }
    final future = widget.assistantService.getHomeSummary();
    final cached = syncValue(future);
    if (cached != null) {
      if (!identical(cached, _summary)) {
        if (mounted) {
          setState(() => _summary = cached);
        } else {
          _summary = cached;
        }
      }
      return;
    }
    future
        .then((value) {
          if (mounted) setState(() => _summary = value);
        })
        .catchError((Object _) {});
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(PlanBillingVisibility.message(context, message)),
          backgroundColor: HomeMindTheme.danger,
        ),
      );
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.profile, oldWidget.profile)) {
      ++_quotaGeneration;
      _profile = widget.profile;
    }
  }

  @override
  void dispose() {
    ++_quotaGeneration;
    WidgetsBinding.instance.removeObserver(this);
    widget.assistantService.dataChanges.removeListener(_loadSummary);
    _errorSub?.cancel();
    AppText.language.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openVoiceSheet() async {
    if (_voiceBusy) return;
    setState(() => _voiceBusy = true);
    try {
      final source = widget.assistantService;
      if (source is VoiceQuotaSource) {
        final quota = await (source as VoiceQuotaSource).getVoiceQuota();
        if (!mounted) return;
        if (quota != null) {
          setState(() => _profile = _profile?.copyWith(voiceQuota: quota));
        }
        if (quota != null && quota.remaining == 0) {
          final canUpgrade = quota.plan == 'free' || quota.plan == 'personal';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  !PlanBillingVisibility.of(context)
                      ? 'Đã hết lượt trợ lý trong kỳ này.'
                      : canUpgrade
                      ? 'Đã hết lượt. Có thể nâng lên gói phù hợp cao hơn.'
                      : 'Đã hết lượt. Hãy chờ kỳ tiếp theo; gia hạn đang cập nhật.',
                ),
              ),
              action: canUpgrade && PlanBillingVisibility.of(context)
                  ? SnackBarAction(
                      label: tr('Xem gói hiện tại'),
                      onPressed: () => PaywallSheet.show(
                        context,
                        service: widget.assistantService,
                        source: 'voice_quota',
                      ),
                    )
                  : null,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      final text = await VoiceSheet.show(
        context,
        speechService: widget.speechService,
      );
      if (text != null && text.trim().isNotEmpty && mounted) {
        await _processVoiceCommand(text.trim());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Chưa tải được hạn mức trợ lý. Hãy thử lại.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  bool _voiceBusy = false;

  void _openSpendingPage() {
    final service = widget.assistantService;
    if (service is! SpendingSource) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpendingPage(
          service: service,
          source: service as SpendingSource,
          merchant: service.currentRole == AccountRole.merchant,
        ),
      ),
    );
  }

  Future<void> _processVoiceCommand(String text) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(tr('Đang phân tích câu lệnh với AI...')),
          ],
        ),
        backgroundColor: HomeMindTheme.primaryDark,
        duration: Duration(milliseconds: 900),
      ),
    );

    try {
      final turn = await widget.assistantService.turn(text: text);
      if (!mounted) return;

      // 1. Nếu là truy vấn thông tin (kiểm tra giỏ hàng, hạn sử dụng, tồn kho)
      if (turn.kind == AssistantTurnKind.readResult) {
        final entityLabels = PlanBillingVisibility.entityLabels(turn.data);
        final toolId = turn.toolsUsed.isNotEmpty
            ? turn.toolsUsed.first.toolId
            : '';
        if (toolId == 'shopping.list') {
          _showAssistantQuerySheet(
            title: tr('Danh sách cần mua 🛒'),
            query: text,
            reply: turn.message,
            preservedValues: entityLabels,
            actionLabel: tr('Mở Danh sách Mua sắm'),
            onAction: _openShoppingPage,
          );
          return;
        } else if (toolId == 'spending.month' &&
            SpendingCard.supported(widget.assistantService)) {
          _showAssistantQuerySheet(
            title: tr('Chi tiêu 💰'),
            query: text,
            reply: turn.message,
            preservedValues: entityLabels,
            actionLabel: tr('Xem chi tiêu'),
            onAction: () => _openSpendingPage(),
          );
          return;
        } else if (toolId == 'inventory.expiring' ||
            toolId == 'inventory.list') {
          _showAssistantQuerySheet(
            title: toolId == 'inventory.expiring'
                ? tr('Sản phẩm sắp hết hạn ⚠️')
                : tr('Tồn kho trong tủ 📦'),
            query: text,
            reply: turn.message,
            preservedValues: entityLabels,
            actionLabel: tr('Xem Tủ đồ'),
            onAction: () => _openInventoryPage(
              filterExpiring: toolId == 'inventory.expiring',
            ),
          );
          return;
        }
      }

      // 2. Nếu là câu lệnh ghi dữ liệu hoặc cần xác nhận (thêm vào kho, thêm vào giỏ, hết hàng)
      // Nhiều việc trong một câu: duyệt lần lượt "Việc 1/3, 2/3...", mỗi việc lưu hoặc huỷ riêng.
      final drafts = [turn, ...turn.followUps];
      for (var i = 0; i < drafts.length && mounted; i++) {
        final result = await Navigator.of(context).push<AssistantTurn>(
          MaterialPageRoute(
            builder: (_) => ConfirmPage(
              service: widget.assistantService,
              draft: drafts[i],
              step: drafts.length > 1
                  ? (index: i + 1, total: drafts.length)
                  : null,
            ),
          ),
        );
        if (result != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                PlanBillingVisibility.message(
                  context,
                  result.message,
                  preservedValues: PlanBillingVisibility.entityLabels([
                    result.data,
                    result.created,
                    ...drafts[i].toolsProposed.map((tool) => tool.arguments),
                  ]),
                ),
              ),
              backgroundColor: HomeMindTheme.primary,
            ),
          );
          // Dữ liệu đã đổi trên server: bộ nhớ đệm tự làm mới và báo các tab.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: HomeMindTheme.danger,
          ),
        );
      }
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (error is HomeMindApiException) {
      if (error.code == 'VOICE_QUOTA_EXHAUSTED') {
        return tr(
          PlanBillingVisibility.of(context)
              ? 'Gói đang dùng đã hết lượt trợ lý trong kỳ này.'
              : 'Đã hết lượt trợ lý trong kỳ này.',
        );
      }
      final code = error.statusCode;
      if (code == 429) {
        return tr('Bạn nói nhanh quá, đợi một chút rồi thử lại nhé.');
      }
      if (code == 503 || code == 504 || code == 502) {
        return tr('Trợ lý đang bận. Bạn thử lại sau ít giây nhé.');
      }
      if (code == 401) {
        return tr('Phiên đăng nhập đã hết hạn. Bạn đăng nhập lại nhé.');
      }
    }
    if (text.contains('Không thể kết nối') ||
        text.contains('SocketException')) {
      return tr('Không kết nối được mạng. Bạn kiểm tra Wi-Fi rồi thử lại nhé.');
    }
    return tr('Chưa xử lý được câu này. Bạn thử nói lại nhé.');
  }

  void _showAssistantQuerySheet({
    required String title,
    required String query,
    required String reply,
    required String actionLabel,
    required VoidCallback onAction,
    Iterable<String> preservedValues = const [],
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: HomeMindTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('🤖', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('Trợ lý giọng nói HomeMind'),
                        style: TextStyle(
                          fontSize: 12,
                          color: HomeMindTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // User spoken query
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: HomeMindTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HomeMindTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Câu hỏi của bạn:'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HomeMindTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '“$query”',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Assistant Reply
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('HomeMind trả lời:'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HomeMindTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    PlanBillingVisibility.message(
                      context,
                      reply,
                      fallback: tr('HomeMind đã xử lý câu lệnh của bạn.'),
                      preservedValues: preservedValues,
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HomeMindTheme.textMain,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          HomeMindTheme.radiusMd,
                        ),
                      ),
                      side: const BorderSide(color: HomeMindTheme.border),
                    ),
                    child: Text(
                      tr('Đóng'),
                      style: TextStyle(color: HomeMindTheme.textSub),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onAction();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HomeMindTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          HomeMindTheme.radiusMd,
                        ),
                      ),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openShoppingPage() => setState(() {
    if (_index != 2) _resetLeftTab(_index);
    _index = 2;
    _visited.add(2);
  });

  bool _inventoryExpiringFirst = false;

  void _openInventoryPage({bool filterExpiring = false}) => setState(() {
    if (_index != 1) _resetLeftTab(_index);
    if (_inventoryExpiringFirst != filterExpiring) {
      _inventoryExpiringFirst = filterExpiring;
      _inventoryGen++;
    }
    _index = 1;
    _visited.add(1);
  });

  @override
  Widget build(BuildContext context) {
    final role = widget.assistantService.currentRole;
    final summary = _summary;
    Widget buildTab(int i) => switch (i) {
      0 => HomePage(
        key: ValueKey('home_${role}_$_homeGen'),
        service: widget.assistantService,
        onOpenAssistant: _openVoiceSheet,
        onOpenShopping: _openShoppingPage,
        onOpenInventory: () => _openInventoryPage(filterExpiring: false),
        onOpenVoice: _openVoiceSheet,
        onOpenProfile: () => setState(() {
          _index = 3;
          _visited.add(3);
        }),
        onOpenSecurity: () async {
          final auth = widget.authService;
          final profile = await widget.assistantService.getMe();
          if (!context.mounted || auth is! AccountAuthService) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AccountSettingsPage(
                auth: auth as AccountAuthService,
                profile: profile,
                onProfileChanged: (p) => setState(() => _profile = p),
              ),
            ),
          );
        },
      ),
      1 => InventoryPage(
        key: ValueKey('inventory_${role}_$_inventoryGen'),
        service: widget.assistantService,
        initialFilterExpiring: _inventoryExpiringFirst,
      ),
      2 => ShoppingPage(
        key: ValueKey('shopping_${role}_$_shoppingGen'),
        service: widget.assistantService,
      ),
      _ => ProfilePage(
        authService: widget.authService,
        service: widget.assistantService,
        user: _profile,
        onProfileChanged: (p) => _profile = p,
        activeRole: role,
        inStockCount: summary?.inStockCount ?? 0,
        attentionCount:
            (summary?.expiringSoonCount ?? 0) + (summary?.expiredCount ?? 0),
        onLogout: widget.onLogout,
        onRoleChanged: (_) {},
      ),
    };

    // Các tab đã mở được giữ nguyên (IndexedStack) nên chuyển tab tức thì.
    void goTo(int i) => setState(() {
      if (i != _index) _resetLeftTab(_index);
      _index = i;
      _visited.add(i);
    });

    return Scaffold(
      backgroundColor: HomeMindTheme.background,
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < 4; i++)
              if (_visited.contains(i))
                // Tab ẩn không chạy animation (tiết kiệm pin, không giật).
                TickerMode(enabled: i == _index, child: buildTab(i))
              else
                const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Row(
              children: [
                _NavButton(
                  key: const Key('nav_home'),
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: tr('Trang chủ'),
                  active: _index == 0,
                  onTap: () => goTo(0),
                ),
                _NavButton(
                  key: const Key('nav_inventory'),
                  icon: Icons.kitchen_outlined,
                  activeIcon: Icons.kitchen_rounded,
                  label: role == AccountRole.merchant
                      ? tr('Kho hàng')
                      : tr('Tủ đồ'),
                  active: _index == 1,
                  onTap: () => goTo(1),
                ),
                _CenterMicButton(
                  key: const Key('nav_voice'),
                  onTap: _voiceBusy ? null : _openVoiceSheet,
                  exhausted: _profile?.voiceQuota?.remaining == 0,
                ),
                _NavButton(
                  key: const Key('nav_shopping'),
                  icon: Icons.shopping_basket_outlined,
                  activeIcon: Icons.shopping_basket_rounded,
                  label: role == AccountRole.merchant
                      ? tr('Cần nhập')
                      : tr('Đi chợ'),
                  active: _index == 2,
                  onTap: () => goTo(2),
                ),
                _NavButton(
                  key: const Key('nav_profile'),
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: tr('Cá nhân'),
                  active: _index == 3,
                  onTap: () => goTo(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? HomeMindTheme.primaryDark : HomeMindTheme.textMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pill nền cho tab đang chọn: nhận ra ngay, không chỉ dựa vào màu.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 56,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? HomeMindTheme.primaryLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(active ? activeIcon : icon, color: color, size: 24),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterMicButton extends StatelessWidget {
  const _CenterMicButton({
    required this.onTap,
    this.exhausted = false,
    super.key,
  });
  final VoidCallback? onTap;
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Transform.translate(
        // Nút nổi nhô lên khỏi thanh; nhãn "Nói" thẳng hàng với các nhãn tab khác.
        offset: const Offset(0, -12),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: exhausted
                        ? [HomeMindTheme.textMuted, HomeMindTheme.textSub]
                        : [HomeMindTheme.primary, HomeMindTheme.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: exhausted ? const [] : HomeMindTheme.greenShadow,
                ),
                child: const Center(
                  child: Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tr('Nói'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: exhausted
                      ? HomeMindTheme.textMuted
                      : HomeMindTheme.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeMindAppShell extends StatefulWidget {
  const HomeMindAppShell({
    required this.authService,
    required this.profile,
    this.assistantService,
    this.speechService,
    this.onLogout,
    super.key,
  });

  final AuthService authService;
  final UserProfile profile;
  final AssistantService? assistantService;
  final SpeechRecognitionService? speechService;
  final VoidCallback? onLogout;

  @override
  State<HomeMindAppShell> createState() => _HomeMindAppShellState();
}

class _HomeMindAppShellState extends State<HomeMindAppShell> {
  late final AssistantService _assistantService;
  late final SpeechRecognitionService _speechService;
  CachedAssistantService? _ownedCache;

  @override
  void initState() {
    super.initState();
    final injected = widget.assistantService;
    if (injected != null) {
      _assistantService = injected;
    } else {
      final cache = CachedAssistantService(
        BackendAssistantService(
          authService: widget.authService,
          profile: widget.profile,
        ),
        initialProfile: widget.profile,
      );
      _ownedCache = cache;
      _assistantService = cache;
      // Làm nóng bộ nhớ đệm ngay sau đăng nhập: Trang chủ hiện nhanh.
      cache.refresh().catchError((Object _) {});
    }
    _assistantService.switchRole(widget.profile.accountRole);
    _speechService = widget.speechService ?? NativeSpeechRecognitionService();
  }

  @override
  void dispose() {
    _ownedCache?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      authService: widget.authService,
      assistantService: _assistantService,
      speechService: _speechService,
      profile: widget.profile,
      onLogout: widget.onLogout,
    );
  }
}
