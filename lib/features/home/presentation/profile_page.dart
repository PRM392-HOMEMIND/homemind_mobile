import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/widgets/page_skeleton.dart';
import '../../family/family_gateway.dart';
import '../../family/family_page.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../assistant/data/backend_assistant_service.dart';
import '../../assistant/data/cached_assistant_service.dart'
    show ProfileSaveUncertain;
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'paywall_sheet.dart';
import 'plan_catalog.dart';
import '../../auth/domain/auth_service.dart';
import '../../auth/domain/account_auth_service.dart';
import '../../auth/presentation/account_settings_page.dart';
import '../../billing/billing_service.dart';
import '../../voice/presentation/voice_quota_panel.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    this.service,
    this.user,
    this.activeRole = AccountRole.consumer,
    this.inStockCount = 0,
    this.attentionCount = 0,
    this.onRoleChanged,
    this.onLogout,
    this.onBack,
    this.onProfileChanged,
    this.authService,
    super.key,
  });

  final AssistantService? service;
  final AuthService? authService;
  final UserProfile? user;
  final AccountRole activeRole;
  final int inStockCount;
  final int attentionCount;
  final ValueChanged<AccountRole>? onRoleChanged;
  final VoidCallback? onLogout;
  final VoidCallback? onBack;

  /// Gọi sau khi hồ sơ được lưu thành công để nơi chứa (shell) cập nhật.
  final ValueChanged<UserProfile>? onProfileChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum _EditField { name, phone, address }

final RegExp _phonePattern = RegExp(r'^\+?[0-9 .-]{8,20}$');

class _ProfilePageState extends State<ProfilePage> {
  late AccountRole _activeRole;
  UserProfile? _user;
  bool _profileLoading = false;
  Object? _profileError;
  int _profileGeneration = 0;

  Future<void> _loadProfile() async {
    final service = widget.service;
    if (service == null) return;
    final generation = ++_profileGeneration;
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final user = await service.getMe();
      if (mounted && generation == _profileGeneration) {
        setState(() => _user = user);
      }
    } catch (error) {
      if (mounted && generation == _profileGeneration) {
        setState(() {
          _profileError = error;
          _user = null;
        });
      }
    } finally {
      if (mounted && generation == _profileGeneration) {
        setState(() => _profileLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _activeRole = widget.service?.currentRole ?? widget.activeRole;
    _user = widget.user;
    if (_user == null && widget.service != null) _loadProfile();
    AppText.language.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    ++_profileGeneration;
    AppText.language.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.service, oldWidget.service)) {
      ++_profileGeneration;
      _profileError = null;
      _profileLoading = false;
      _user = widget.user;
      if (_user == null && widget.service != null) _loadProfile();
    }
    if (!identical(widget.user, oldWidget.user)) {
      _user = widget.user;
    }
    if (widget.service != null && widget.service!.currentRole != _activeRole) {
      _activeRole = widget.service!.currentRole;
    } else if (widget.activeRole != oldWidget.activeRole) {
      _activeRole = widget.activeRole;
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        ),
        title: Text(
          tr('Đăng xuất tài khoản'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          tr('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng HomeMind không?'),
          style: const TextStyle(color: HomeMindTheme.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              tr('Hủy'),
              style: const TextStyle(color: HomeMindTheme.textSub),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HomeMindTheme.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
            child: Text(tr('Đăng xuất')),
          ),
        ],
      ),
    );
  }

  // ── Lưu hồ sơ ──────────────────────────────────────────────────────────

  String _friendlySaveError(Object error) {
    if (error is ProfileSaveUncertain) {
      return error.reconciled
          ? tr('Thay đổi chưa được lưu. Hồ sơ đã đối soát với máy chủ.')
          : tr(
              'Chưa xác nhận được trạng thái lưu. Hãy tải lại hồ sơ trước khi thử lại.',
            );
    }
    if (error is HomeMindApiException && error.statusCode == 401) {
      return tr('Phiên đăng nhập đã hết hạn. Bạn đăng nhập lại nhé.');
    }
    if (error is HomeMindApiException && error.statusCode == 400) {
      return tr('Thông tin chưa hợp lệ. Kiểm tra trường đang sửa.');
    }
    return tr('Chưa lưu được. Bạn kiểm tra mạng rồi thử lại nhé.');
  }

  /// Gửi thay đổi lên server (nếu có service) và cập nhật hiển thị ngay.
  Future<void> _saveProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async {
    final service = widget.service;
    UserProfile updated;
    if (service != null) {
      updated = await service.updateProfile(
        displayName: displayName,
        phone: phone,
        address: address,
        language: language,
      );
    } else if (_user != null) {
      updated = _user!.copyWith(
        displayName: displayName,
        phone: phone,
        address: address,
        language: language,
      );
    } else {
      return;
    }
    if (!mounted) return;
    setState(() => _user = updated);
    widget.onProfileChanged?.call(updated);
    if (language != null) {
      AppText.setLanguage(updated.language);
    }
  }

  void _showSaved() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Đã lưu')),
          backgroundColor: HomeMindTheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _edit(_EditField field) async {
    final user = _user;
    final initial = switch (field) {
      _EditField.name => user?.displayName ?? '',
      _EditField.phone => user?.phone ?? '',
      _EditField.address => user?.address ?? '',
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditFieldSheet(
        field: field,
        initialValue: initial,
        onSave: (value) => switch (field) {
          _EditField.name => _saveProfile(displayName: value),
          _EditField.phone => _saveProfile(phone: value),
          _EditField.address => _saveProfile(address: value),
        },
        friendlyError: _friendlySaveError,
      ),
    );
    if (saved == true) _showSaved();
  }

  Future<void> _pickLanguage() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LanguageSheet(
        current: _user?.language ?? AppText.language.value,
        onSelect: (code) => _saveProfile(language: code),
        friendlyError: _friendlySaveError,
      ),
    );
    if (saved == true) _showSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isMerchant = _activeRole == AccountRole.merchant;
    final rawName = _user?.displayName.trim() ?? '';
    final displayName = rawName.isEmpty ? tr('Người dùng HomeMind') : rawName;
    final email = (_user?.email.isNotEmpty ?? false)
        ? _user!.email
        : tr('Chưa cập nhật');
    final workspaceName = (_user?.workspaceName.isNotEmpty ?? false)
        ? _user!.workspaceName
        : tr('Không gian HomeMind');
    final phone = _orNotSet(_user?.phone);
    final address = _orNotSet(_user?.address);
    final languageCode = _user?.language ?? AppText.language.value;
    final languageName = languageCode == 'en' ? 'English' : 'Tiếng Việt';

    return Scaffold(
      backgroundColor: HomeMindTheme.background,
      appBar: AppBar(
        backgroundColor: HomeMindTheme.background,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Hồ sơ & Tài khoản')),
        leading: (widget.onBack != null || Navigator.canPop(context))
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (_profileLoading && _user == null)
            const PageSkeleton(SkeletonPage.profile, sectionOnly: true)
          else if (_profileError != null && _user == null) ...[
            Text(tr('Chưa tải được hồ sơ. Vui lòng thử lại.')),
            TextButton(onPressed: _loadProfile, child: Text(tr('Thử lại'))),
          ] else ...[
            // Hero section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
                boxShadow: HomeMindTheme.softShadow,
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isMerchant
                            ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                            : [
                                HomeMindTheme.primary,
                                HomeMindTheme.primaryDark,
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isMerchant
                                      ? const Color(0xFFF59E0B)
                                      : HomeMindTheme.primary)
                                  .withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: isMerchant
                          ? const Icon(
                              Icons.storefront_rounded,
                              size: 38,
                              color: Colors.white,
                            )
                          : Text(
                              rawName.isEmpty
                                  ? 'H'
                                  : String.fromCharCode(rawName.runes.first)
                                        .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: HomeMindTheme.textSub,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isMerchant
                          ? const Color(0xFFFEF3C7)
                          : HomeMindTheme.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isMerchant
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                            : HomeMindTheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMerchant
                              ? Icons.storefront_rounded
                              : Icons.home_rounded,
                          size: 16,
                          color: isMerchant
                              ? const Color(0xFFB45309)
                              : HomeMindTheme.primaryDark,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isMerchant
                                ? tr('Tài khoản cửa hàng')
                                : tr('Tài khoản gia đình'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isMerchant
                                  ? const Color(0xFFB45309)
                                  : HomeMindTheme.primaryDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stats row
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatBox(
                    value: '${widget.inStockCount}',
                    label: isMerchant
                        ? tr('Mặt hàng quầy kệ')
                        : tr('Món trong tủ'),
                  ),
                  const SizedBox(width: 10),
                  _StatBox(
                    value: '${widget.attentionCount}',
                    label: tr('Cần chú ý'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Account info section
            Text(
              tr('Thông tin chi tiết'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HomeMindTheme.textMain,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
                boxShadow: HomeMindTheme.softShadow,
              ),
              child: Column(
                children: [
                  _InfoRow(
                    key: const Key('profile_row_name'),
                    label: tr('Tên'),
                    value: displayName,
                    onTap: () => _edit(_EditField.name),
                  ),
                  const Divider(color: HomeMindTheme.border, height: 1),
                  _InfoRow(label: tr('Không gian'), value: workspaceName),
                  const Divider(color: HomeMindTheme.border, height: 1),
                  if (widget.service != null &&
                      PlanBillingVisibility.of(context))
                    HomeSummaryGate(
                      service: widget.service!,
                      builder: (context, home) {
                        if (home == null) return const SizedBox.shrink();
                        final free = home.plan == 'free';
                        final planInfo = PlanInfo.of(home.plan);
                        final service = widget.service!;
                        final hasBilling =
                            service is BillingSource &&
                            (service as BillingSource).billing != null;
                        return Column(
                          children: [
                            _InfoRow(
                              key: const Key('profile_row_plan'),
                              label: tr('Gói của bạn'),
                              value: planInfo.key == home.plan
                                  ? planInfo.name
                                  : home.plan,
                              // Restore the existing row action only when the client UI is visible.
                              onTap:
                                  PlanBillingVisibility.of(context) &&
                                      (free || hasBilling)
                                  ? () => PaywallSheet.show(
                                      context,
                                      service: widget.service!,
                                      source: 'paywall',
                                    )
                                  : null,
                              trailing:
                                  PlanBillingVisibility.of(context) && free
                                  ? Container(
                                      key: const Key('profile_upgrade'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3D4),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: const Color(0xFFFFE299),
                                        ),
                                      ),
                                      child: Text(
                                        tr('Xem gói hiện tại'),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB45309),
                                          fontFamily: HomeMindTheme.fontFamily,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        );
                      },
                    ),
                  _InfoRow(
                    key: const Key('profile_row_phone'),
                    label: tr('Số điện thoại liên hệ'),
                    value: phone,
                    onTap: () => _edit(_EditField.phone),
                  ),
                  const Divider(color: HomeMindTheme.border, height: 1),
                  _InfoRow(
                    key: const Key('profile_row_address'),
                    label: tr('Địa chỉ'),
                    value: address,
                    onTap: () => _edit(_EditField.address),
                  ),
                  const Divider(color: HomeMindTheme.border, height: 1),
                  _InfoRow(
                    key: const Key('profile_row_language'),
                    label: tr('Ngôn ngữ'),
                    value: languageName,
                    onTap: _pickLanguage,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (widget.service != null) ...[
              VoiceQuotaPanel(
                service: widget.service!,
                billingPresentation: true,
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (widget.service is FamilySource &&
              (widget.service as FamilySource).family != null) ...[
            OutlinedButton.icon(
              key: const Key('profile_family'),
              icon: const Icon(Icons.group_outlined),
              label: Text(tr('Thành viên gia đình')),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FamilyPage(
                    gateway: (widget.service as FamilySource).family!,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Logout button
          if (widget.authService is AccountAuthService && _user != null) ...[
            OutlinedButton.icon(
              key: const ValueKey('profile_security'),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Bảo mật tài khoản'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountSettingsPage(
                    auth: widget.authService as AccountAuthService,
                    profile: _user!,
                    onProfileChanged: (profile) {
                      setState(() => _user = profile);
                      widget.onProfileChanged?.call(profile);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            key: const ValueKey('profile_logout'),
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, color: HomeMindTheme.danger),
            label: Text(
              tr('Đăng xuất'),
              style: const TextStyle(
                color: HomeMindTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD4D4)),
              backgroundColor: const Color(0xFFFFF5F5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  String _orNotSet(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? tr('Chưa cập nhật') : v;
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
          boxShadow: HomeMindTheme.softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: HomeMindTheme.textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: HomeMindTheme.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
    super.key,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: HomeMindTheme.textSub,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // Chip phụ nằm dưới giá trị: hàng không bị bóp khi cỡ chữ hệ thống lớn.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: HomeMindTheme.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

// ── Bottom sheets ────────────────────────────────────────────────────────

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: HomeMindTheme.textMain,
                  ),
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditFieldSheet extends StatefulWidget {
  const _EditFieldSheet({
    required this.field,
    required this.initialValue,
    required this.onSave,
    required this.friendlyError,
  });

  final _EditField field;
  final String initialValue;
  final Future<void> Function(String value) onSave;
  final String Function(Object error) friendlyError;

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    switch (widget.field) {
      case _EditField.name:
        if (value.isEmpty) return tr('Bạn chưa nhập tên.');
        if (value.length > 120) return tr('Tên tối đa 120 ký tự.');
      case _EditField.phone:
        // Để trống = xoá số điện thoại.
        if (value.isNotEmpty &&
            (value.length > 20 || !_phonePattern.hasMatch(value))) {
          return tr(
            'Số điện thoại cần 8-20 ký tự gồm số, khoảng trắng, +, - hoặc .',
          );
        }
      case _EditField.address:
        if (value.length > 300) return tr('Địa chỉ tối đa 300 ký tự.');
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final value = _controller.text.trim();
    final problem = _validate(value);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final title = switch (field) {
      _EditField.name => tr('Sửa tên hiển thị'),
      _EditField.phone => tr('Sửa số điện thoại liên hệ'),
      _EditField.address => tr('Sửa địa chỉ'),
    };
    final hint = switch (field) {
      _EditField.name => tr('Tên hiển thị'),
      _EditField.phone => tr('Nhập số điện thoại liên hệ'),
      _EditField.address => tr('Nhập địa chỉ'),
    };
    return _SheetFrame(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('profile_edit_field'),
            controller: _controller,
            enabled: !_saving,
            autofocus: true,
            keyboardType: switch (field) {
              _EditField.phone => TextInputType.phone,
              _EditField.address => TextInputType.multiline,
              _EditField.name => TextInputType.name,
            },
            minLines: field == _EditField.address ? 2 : 1,
            maxLines: field == _EditField.address ? 4 : 1,
            textCapitalization: field == _EditField.phone
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HomeMindTheme.textMain,
            ),
            decoration: InputDecoration(
              hintText: hint,
              errorText: _error,
              errorMaxLines: 3,
              filled: true,
              fillColor: HomeMindTheme.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                borderSide: const BorderSide(color: HomeMindTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                borderSide: const BorderSide(color: HomeMindTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                borderSide: const BorderSide(
                  color: HomeMindTheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            onSubmitted: field == _EditField.address ? null : (_) => _submit(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('profile_cancel_button'),
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
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
                    tr('Huỷ'),
                    style: const TextStyle(color: HomeMindTheme.textSub),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const Key('profile_save_button'),
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HomeMindTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: HomeMindTheme.primary.withValues(
                      alpha: 0.6,
                    ),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        HomeMindTheme.radiusMd,
                      ),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          tr('Lưu'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({
    required this.current,
    required this.onSelect,
    required this.friendlyError,
  });

  final String current;
  final Future<void> Function(String code) onSelect;
  final String Function(Object error) friendlyError;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _choose(String code) async {
    if (_saving) return;
    if (code == widget.current) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSelect(code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: tr('Chọn ngôn ngữ'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LanguageOption(
            key: const Key('language_option_vi'),
            label: 'Tiếng Việt',
            selected: widget.current == 'vi',
            onTap: _saving ? null : () => _choose('vi'),
          ),
          const SizedBox(height: 8),
          _LanguageOption(
            key: const Key('language_option_en'),
            label: 'English',
            selected: widget.current == 'en',
            onTap: _saving ? null : () => _choose('en'),
          ),
          const SizedBox(height: 12),
          if (_saving)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HomeMindTheme.primary,
                ),
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: HomeMindTheme.danger, fontSize: 13),
            ),
          Text(
            tr('Trợ lý giọng nói vẫn nghe tiếng Việt'),
            style: const TextStyle(
              fontSize: 12,
              color: HomeMindTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? HomeMindTheme.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
          border: Border.all(
            color: selected ? HomeMindTheme.primary : HomeMindTheme.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: HomeMindTheme.textMain,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? HomeMindTheme.primary : HomeMindTheme.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
