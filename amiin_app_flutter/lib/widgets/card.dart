// ─── Card ────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';

enum CardVariant { default_, sand, dark }

class AmiinCard extends StatelessWidget {
  final Widget child;
  final CardVariant variant;
  final bool elevated;

  const AmiinCard({
    super.key,
    required this.child,
    this.variant = CardVariant.default_,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    switch (variant) {
      case CardVariant.default_:
        bgColor = ColorsAmiin.white;
        break;
      case CardVariant.sand:
        bgColor = ColorsAmiin.sand;
        break;
      case CardVariant.dark:
        bgColor = ColorsAmiin.darkMid;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(RadiusAmiin.md),
        border: Border.all(color: ColorsAmiin.border),
        boxShadow: elevated ? ShadowAmiin.md : ShadowAmiin.sm,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: child,
    );
  }
}