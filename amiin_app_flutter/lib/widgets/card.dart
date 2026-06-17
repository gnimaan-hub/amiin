// ─── Card ─────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/spacing.dart';
import '../theme/themes.dart';

enum CardVariant { default_, surface2, dark, info, secretariat }

class AmiinCard extends StatelessWidget {
  final Widget child;
  final CardVariant variant;
  final bool elevated;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  const AmiinCard({
    super.key,
    required this.child,
    this.variant = CardVariant.default_,
    this.elevated = false,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    Color bgColor;
    Color? accentBorderColor;

    switch (variant) {
      case CardVariant.default_:
        bgColor = ac.surface;
      case CardVariant.surface2:
        bgColor = ac.surface2;
      case CardVariant.dark:
        bgColor = ac.headerGradientEnd;
      case CardVariant.info:
        bgColor = ac.surface;
        accentBorderColor = ac.infoAccent;
      case CardVariant.secretariat:
        bgColor = ac.surface;
        accentBorderColor = ac.secretariatAccent;
    }

    final effectivePadding = padding ?? const EdgeInsets.all(Spacing.lg);

    Widget content = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: accentBorderColor != null
            ? Border(left: BorderSide(color: accentBorderColor, width: 3))
            : Border.all(color: ac.border),
        boxShadow: elevated ? ShadowAmiin.md : ShadowAmiin.sm,
      ),
      padding: effectivePadding,
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      );
    }

    return content;
  }
}

// Alias rétrocompat
typedef AmiinCardVariant = CardVariant;
