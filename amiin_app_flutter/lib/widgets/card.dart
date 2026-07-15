// ─── Card ─────────────────────────────────────────────────────────────────────
// Carte de marque. Les cartes tappables portent une micro-interaction
// (léger recul 0.98 + haptique) — appliquée ici une seule fois, elle vaut
// pour toutes les cartes de l'app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/spacing.dart';
import '../theme/themes.dart';

enum CardVariant { default_, surface2, dark, info, secretariat }

class AmiinCard extends StatefulWidget {
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
  State<AmiinCard> createState() => _AmiinCardState();
}

class _AmiinCardState extends State<AmiinCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    Color bgColor;
    Color? accentBorderColor;

    switch (widget.variant) {
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

    final effectivePadding = widget.padding ?? const EdgeInsets.all(Spacing.lg);

    Widget content = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(RadiusAmiin.lg),
        border: accentBorderColor != null
            ? Border(left: BorderSide(color: accentBorderColor, width: 3))
            : Border.all(color: ac.border),
        boxShadow: widget.elevated ? ShadowAmiin.md : ShadowAmiin.sm,
      ),
      padding: effectivePadding,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap!();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: content,
        ),
      );
    }

    return content;
  }
}

// Alias rétrocompat
typedef AmiinCardVariant = CardVariant;
