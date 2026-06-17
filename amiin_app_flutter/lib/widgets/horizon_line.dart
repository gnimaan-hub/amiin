// ─── HorizonLine ─────────────────────────────────────────────────────────────
// Élément signature d'Amiin : une fine ligne d'horizon animée.
// Change de teinte entre turquoise (secrétariat) et ocre (information).
// Sert également d'indicateur de chargement quand `animating = true`.

import 'package:flutter/material.dart';

class HorizonLine extends StatefulWidget {
  final Color color;
  final bool animating;
  final double height;

  const HorizonLine({
    super.key,
    required this.color,
    this.animating = false,
    this.height = 2.0,
  });

  @override
  State<HorizonLine> createState() => _HorizonLineState();
}

class _HorizonLineState extends State<HorizonLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _sweep = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.animating) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(HorizonLine old) {
    super.didUpdateWidget(old);
    if (widget.animating && !old.animating) {
      _ctrl.repeat();
    } else if (!widget.animating && old.animating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.color),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
      builder: (context, color, _) {
        final c = color ?? widget.color;
        return SizedBox(
          height: widget.height,
          child: widget.animating
              ? AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SweepPainter(
                        baseColor: c,
                        sweepPosition: _sweep.value,
                      ),
                      size: Size.infinite,
                    );
                  },
                )
              : Container(color: c),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  final Color baseColor;
  final double sweepPosition;

  const _SweepPainter({required this.baseColor, required this.sweepPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final baseAlpha = baseColor.withValues(alpha: 0.5);
    final glowAlpha = baseColor;

    // Base line
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseAlpha,
    );

    // Sweep glow
    final sweepX = sweepPosition * size.width;
    final glowWidth = size.width * 0.35;
    final gradient = LinearGradient(
      colors: [
        Colors.transparent,
        glowAlpha.withValues(alpha: 0.6),
        glowAlpha,
        glowAlpha.withValues(alpha: 0.6),
        Colors.transparent,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    final left = sweepX - glowWidth / 2;
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(left, 0, glowWidth, size.height),
      );
    canvas.drawRect(
      Rect.fromLTWH(left.clamp(0, size.width), 0,
          glowWidth.clamp(0, size.width), size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.sweepPosition != sweepPosition || old.baseColor != baseColor;
}

// ── Mode helpers ──────────────────────────────────────────────────────────────

enum AmiinMode { secretariat, info, neutral }

extension AmiinModeColor on AmiinMode {
  Color get color {
    switch (this) {
      case AmiinMode.secretariat: return const Color(0xFF1E8A8A);
      case AmiinMode.info:        return const Color(0xFFC8902F);
      case AmiinMode.neutral:     return const Color(0xFF8090B0);
    }
  }
}
