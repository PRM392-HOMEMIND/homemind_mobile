import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';

/// Presentation grouping only; contents and actions come from the Home data.
/// No frame of its own: the cards inside already carry the visual weight.
class HomeSection extends StatelessWidget {
  const HomeSection({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });
  final String title, subtitle, actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: HomeMindTheme.textMain,
        height: 1.25,
      ),
    );
    final action = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: HomeMindTheme.primaryStrong,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onPressed: onAction,
      child: Text(actionLabel, style: const TextStyle(fontSize: 13)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 19) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, action],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 8),
                action,
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: HomeMindTheme.textSub,
          ),
        ),
      ],
    );
  }
}

class HomeEmptyState extends StatelessWidget {
  const HomeEmptyState({required this.message, required this.icon, super.key});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: const TextStyle(
        color: HomeMindTheme.textSub,
        fontSize: 13,
        height: 1.4,
      ),
    ),
  );
}

class HomeSummaryGrid extends StatelessWidget {
  const HomeSummaryGrid({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(14) > 19
          ? 2
          : 4;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
