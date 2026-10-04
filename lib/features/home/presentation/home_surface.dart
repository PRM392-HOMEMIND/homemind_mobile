import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../domain/home_hub_gateway.dart';

/// Search uses one keyboard-aware mobile sheet; notification preview retains
/// its existing anchored list/detail route and bounded-fetch behavior.
ModalBottomSheetRoute<HubTarget> homeSearchRoute({
  required WidgetBuilder builder,
  required bool reducedMotion,
}) => ModalBottomSheetRoute<HubTarget>(
  settings: const RouteSettings(name: '/search'),
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: HomeMindTheme.card,
  modalBarrierColor: Colors.black.withValues(alpha: .18),
  barrierLabel: tr('Đóng'),
  sheetAnimationStyle: reducedMotion ? AnimationStyle.noAnimation : null,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(HomeMindTheme.radiusXl),
    ),
  ),
  clipBehavior: Clip.antiAlias,
  builder: (context) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          key: const Key('mobile_search_sheet'),
          width: constraints.maxWidth,
          height: math.max(0, constraints.maxHeight * .94 - keyboard),
          child: Builder(builder: builder),
        ),
      );
    },
  ),
);

/// Thông báo mở như một bảng trượt từ dưới lên, cùng kiểu với tìm kiếm:
/// quen tay, không phải căn theo vị trí chuông, dễ đọc trên màn nhỏ.
ModalBottomSheetRoute<HubTarget> homeNotificationsRoute({
  required WidgetBuilder builder,
  required bool reducedMotion,
}) => ModalBottomSheetRoute<HubTarget>(
  settings: const RouteSettings(name: '/notifications'),
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: HomeMindTheme.card,
  modalBarrierColor: Colors.black.withValues(alpha: .18),
  barrierLabel: tr('Đóng'),
  sheetAnimationStyle: reducedMotion ? AnimationStyle.noAnimation : null,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(HomeMindTheme.radiusXl),
    ),
  ),
  clipBehavior: Clip.antiAlias,
  builder: (context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      key: const Key('mobile_notifications_sheet'),
      width: constraints.maxWidth,
      height: constraints.maxHeight * .8,
      child: Builder(builder: builder),
    ),
  ),
);

RawDialogRoute<HubTarget> homeSurfaceRoute({
  required WidgetBuilder builder,
  required bool reducedMotion,
  Rect? anchor,
  bool preview = false,
}) => RawDialogRoute<HubTarget>(
  barrierDismissible: true,
  barrierLabel: tr('Đóng'),
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: Duration(milliseconds: reducedMotion ? 0 : 180),
  pageBuilder: (context, animation, secondary) =>
      _SurfaceFrame(builder: builder, anchor: anchor, preview: preview),
  transitionBuilder: (context, animation, secondary, child) =>
      FadeTransition(opacity: animation, child: child),
);

class SurfaceExtent extends Notification {
  SurfaceExtent(this.expanded);
  final bool expanded;
}

class _SurfaceFrame extends StatefulWidget {
  const _SurfaceFrame({
    required this.builder,
    required this.preview,
    this.anchor,
  });
  final WidgetBuilder builder;
  final bool preview;
  final Rect? anchor;
  @override
  State<_SurfaceFrame> createState() => _SurfaceFrameState();
}

class _SurfaceFrameState extends State<_SurfaceFrame> {
  late bool _expanded = !widget.preview;
  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: LayoutBuilder(
          builder: (context, c) {
            final width = math.min(380.0, math.max(0.0, c.maxWidth - 32));
            final height = math.min(
              c.maxHeight * (_expanded ? .72 : .58),
              math.max(0.0, c.maxHeight - 32),
            );
            final left = (widget.anchor?.left ?? 16).clamp(
              16.0,
              math.max(16.0, c.maxWidth - width - 16),
            );
            final desiredTop = c.maxHeight < 550
                ? c.maxHeight - height - 16
                : (widget.anchor?.bottom ?? safeTop + 4) - safeTop + 8;
            final top = desiredTop.clamp(
              16.0,
              math.max(16.0, c.maxHeight - height - 16),
            );
            return Stack(
              children: [
                Positioned(
                  left: left.toDouble(),
                  top: top.toDouble(),
                  width: width,
                  height: height,
                  child: NotificationListener<SurfaceExtent>(
                    onNotification: (n) {
                      setState(() => _expanded = n.expanded);
                      return true;
                    },
                    child: Material(
                      color: Colors.white,
                      elevation: 12,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: HomeMindTheme.border),
                      ),
                      child: FocusScope(
                        autofocus: true,
                        child: Builder(builder: widget.builder),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SurfaceHeader extends StatelessWidget {
  const SurfaceHeader({required this.title, this.onBack, super.key});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: tr('Quay lại'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          key: const Key('hub_close'),
          tooltip: tr('Đóng'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}
