import 'package:flutter/material.dart';

import '../../app/homemind_theme.dart';
import '../l10n/app_text.dart';

/// Bounded static geometry: no fake rows in semantics, no animation controllers.
enum SkeletonPage {
  home,
  inventory,
  inventoryDetail,
  shopping,
  spending,
  search,
  notifications,
  profile,
  billing,
  family,
  invitations,
  memberUsage,
}

class SkeletonSlot extends StatelessWidget {
  const SkeletonSlot({
    this.width,
    this.height = 14,
    this.circle = false,
    super.key,
  });
  final double? width;
  final double height;
  final bool circle;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: HomeMindTheme.border,
      borderRadius: BorderRadius.circular(
        circle ? height : HomeMindTheme.radiusSm,
      ),
    ),
  );
}

/// Every composition follows the named page's actual data widgets.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton(this.page, {this.sectionOnly = false, super.key});
  final SkeletonPage page;
  final bool sectionOnly;
  Widget line(double fraction, {double height = 14}) => FractionallySizedBox(
    widthFactor: fraction,
    alignment: Alignment.centerLeft,
    child: SkeletonSlot(height: height),
  );
  Widget card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: HomeMindTheme.card,
      border: Border.all(color: HomeMindTheme.border),
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget row({bool avatar = false, bool trailing = false}) => Row(
    children: [
      if (avatar) ...[
        const SkeletonSlot(width: 40, height: 40, circle: true),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(.7),
            const SizedBox(height: 10),
            line(.4, height: 12),
          ],
        ),
      ),
      if (trailing) ...[
        const SizedBox(width: 10),
        const SkeletonSlot(width: 38, height: 18),
      ],
    ],
  );
  List<Widget> slots() => switch (page) {
    SkeletonPage.home => [
      card([line(.55, height: 20), const SizedBox(height: 12), line(.8)]),
      line(.45, height: 18),
      card([row(trailing: true)]),
      line(.5, height: 18),
      card([row()]),
      card([
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Column(
                  children: [
                    line(.65, height: 28),
                    const SizedBox(height: 8),
                    line(.75, height: 12),
                  ],
                ),
              ),
          ],
        ),
      ]),
    ],
    SkeletonPage.inventory => [
      line(.6, height: 20),
      card([
        row(trailing: true),
        const SizedBox(height: 14),
        line(.45, height: 12),
      ]),
    ],
    SkeletonPage.inventoryDetail => [
      line(.75, height: 26),
      line(.45),
      card([
        line(.65, height: 20),
        const SizedBox(height: 12),
        line(.5),
        const SizedBox(height: 12),
        line(.7),
        const SizedBox(height: 12),
        line(.55),
      ]),
    ],
    SkeletonPage.shopping => [
      Row(
        children: [
          Expanded(child: line(.7)),
          Expanded(child: line(.7)),
          Expanded(child: line(.7)),
        ],
      ),
      card([row(trailing: true)]),
    ],
    SkeletonPage.spending => [
      card([
        line(.4),
        const SizedBox(height: 14),
        line(.65, height: 30),
        const SizedBox(height: 14),
        line(.7),
      ]),
      card([
        Row(
          children: [
            Expanded(child: line(.8)),
            Expanded(child: line(.8)),
          ],
        ),
      ]),
      line(.5, height: 18),
      card([row(trailing: true)]),
    ],
    SkeletonPage.search => [row(avatar: true)],
    SkeletonPage.notifications => [
      row(avatar: true, trailing: true),
      line(.85, height: 12),
    ],
    SkeletonPage.profile => [
      card([
        const Center(child: SkeletonSlot(width: 76, height: 76, circle: true)),
        const SizedBox(height: 16),
        line(.6, height: 20),
        const SizedBox(height: 10),
        line(.7),
      ]),
      card([
        line(.4),
        const SizedBox(height: 16),
        line(.7),
        const SizedBox(height: 16),
        line(.55),
      ]),
    ],
    SkeletonPage.billing => [
      card([
        line(.45, height: 22),
        const SizedBox(height: 16),
        line(.7),
        const SizedBox(height: 12),
        line(.55),
      ]),
      card([line(.4), const SizedBox(height: 14), line(.8, height: 22)]),
      card([row(trailing: true)]),
    ],
    SkeletonPage.family => [
      card([
        line(.65, height: 20),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: line(.7, height: 24)),
            Expanded(child: line(.7, height: 24)),
            Expanded(child: line(.7, height: 24)),
          ],
        ),
      ]),
      card([row(avatar: true, trailing: true)]),
    ],
    SkeletonPage.invitations => [
      card([
        line(.7, height: 18),
        const SizedBox(height: 12),
        line(.9),
        const SizedBox(height: 12),
        line(.45),
      ]),
    ],
    SkeletonPage.memberUsage => [
      card([
        row(avatar: true),
        const SizedBox(height: 18),
        line(.5, height: 24),
        const SizedBox(height: 12),
        line(.65),
      ]),
    ],
  };
  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('Đang tải dữ liệu'),
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.all(sectionOnly ? 0 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final slot in slots()) ...[slot, const SizedBox(height: 16)],
            ],
          ),
        ),
      ),
    ),
  );
}

// Handled by Tran Gia Phu
