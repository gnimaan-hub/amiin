// ─── Card ─────────────────────────────────────────────────────────────────────
// Carte de marque, au style « vitrine » (docs/REFONTE_VITRINE.md, phase B) :
// elle s'appuie sur [FloatingCard] — surface, liseré de lumière, ombre douce
// et, si elle est tappable, enfoncement + haptique. Modifiée ici une seule
// fois, elle vaut pour toutes les cartes de l'app.

import 'package:flutter/material.dart';
import '../theme/spacing.dart';
import '../theme/themes.dart';
import 'floating_card.dart';

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
  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    Color bgColor;
    Color? accent;
    var lift = widget.elevated ? 0.8 : 0.5;

    switch (widget.variant) {
      case CardVariant.default_:
        bgColor = ac.surface;
      case CardVariant.surface2:
        // Carte secondaire : posée plutôt que flottante.
        bgColor = ac.surface2;
        lift = 0.15;
      case CardVariant.dark:
        bgColor = ac.headerGradientEnd;
      case CardVariant.info:
        bgColor = ac.surface;
        accent = ac.infoAccent;
      case CardVariant.secretariat:
        bgColor = ac.surface;
        accent = ac.secretariatAccent;
    }

    final effectivePadding = widget.padding ?? const EdgeInsets.all(Spacing.lg);

    // Les variantes info / secrétariat gardent leur repère coloré, sous la
    // forme d'une fine pastille verticale à l'intérieur de la carte (et non
    // plus d'une bordure gauche).
    final content = accent == null
        ? widget.child
        : Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              Positioned(
                left: -effectivePadding.left + 6,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );

    return FloatingCard(
      color: bgColor,
      lift: lift,
      padding: effectivePadding,
      onTap: widget.onTap,
      child: content,
    );
  }
}

// Alias rétrocompat
typedef AmiinCardVariant = CardVariant;
