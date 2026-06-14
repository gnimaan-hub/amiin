// ─── EmptyState ──────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

class EmptyState extends StatelessWidget {
  final Widget? icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.huge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Container(
                margin: const EdgeInsets.only(bottom: Spacing.md),
                child: Opacity(opacity: 0.5, child: icon),
              ),
            Text(
              title,
              style: TextStyle(
                fontFamily: FontFamily.serif,
                fontSize: 18,
                color: ColorsAmiin.ink,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: FontSize.base,
                    color: ColorsAmiin.muted,
                    height: LineHeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.lg),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}