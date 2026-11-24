// ─── FloatingCard ────────────────────────────────────────────────────────────
// Brique de base de la refonte « vitrine » : surface, liseré de lumière,
// ombre douce ; si elle est tappable, elle s'enfonce légèrement (échelle +
// ombre réduite) avec un retour haptique.
// Référence : docs/REFONTE_VITRINE.md (étape 5).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/elevation.dart';
import '../theme/spacing.dart';
import '../theme/themes.dart';

class FloatingCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double lift;
  final Color? color;
  final Color? shadowTint;
  final double radius;

  const FloatingCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.onTap,
    this.onLongPress,
    this.lift = 0.5,
    this.color,
    this.shadowTint,
    this.radius = RadiusVitrine.card,
  });

  @override
  State<FloatingCard> createState() => _FloatingCardState();
}

class _FloatingCardState extends State<FloatingCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.color ?? context.ac.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: hairline(context),
        boxShadow: floatShadow(
          context,
          lift: _pressed ? widget.lift * 0.3 : widget.lift,
          tint: widget.shadowTint,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius - 1),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );

    if (!_interactive) return card;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }
}
