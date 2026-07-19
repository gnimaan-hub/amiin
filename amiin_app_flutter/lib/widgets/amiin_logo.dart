// ─── AmiinLogo — mark « A » pixel/tech de la marque ──────────────────────────
//
// Utilise les PNG officiels (assets/logo/), mark sur fond transparent.
// `variant` force une couleur ; sans variante explicite, le mark s'adapte au
// thème actif : turquoise sur fond clair, sel d'Assal (crème) sur fond sombre.

import 'package:flutter/material.dart';

enum AmiinLogoVariant {
  /// Crème (sel d'Assal) — pour fonds sombres
  dark,

  /// Encre de nuit (navy) — pour fonds clairs
  light,

  /// Turquoise Tadjourah — accent secrétariat
  turquoise,

  /// Ocre des Dunes — accent information
  ocre,

  /// Blanc pur — barres système, monochrome
  mono,
}

class AmiinLogo extends StatelessWidget {
  final double size;

  /// Couleur du mark ; null = adapté automatiquement au thème actif.
  final AmiinLogoVariant? variant;

  const AmiinLogo({
    super.key,
    this.size = 48,
    this.variant,
  });

  static const _assets = {
    AmiinLogoVariant.dark: 'assets/logo/amiin-A-selassal.png',
    AmiinLogoVariant.light: 'assets/logo/amiin-A-navy.png',
    AmiinLogoVariant.turquoise: 'assets/logo/amiin-A-turquoise.png',
    AmiinLogoVariant.ocre: 'assets/logo/amiin-A-ocre.png',
    AmiinLogoVariant.mono: 'assets/logo/amiin-A-blanc.png',
  };

  @override
  Widget build(BuildContext context) {
    final v = variant ??
        (Theme.of(context).brightness == Brightness.dark
            ? AmiinLogoVariant.dark
            : AmiinLogoVariant.turquoise);

    return Image.asset(
      _assets[v]!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
