// ─── Amiin Design Tokens ── Élévation « vitrine » ───────────────────────────
// Ombres douces à deux couches, liseré de lumière et voile de verre dépoli.
// Référence : docs/REFONTE_VITRINE.md (étapes 1 à 4 et 10).

import 'package:flutter/material.dart';
import 'themes.dart';

/// Rayons de la refonte.
class RadiusVitrine {
  /// Cartes flottantes.
  static const double card = 18;

  /// Barre d'onglets.
  static const double bar = 26;

  /// Coins bas du bandeau héros.
  static const double hero = 32;

  /// Pastilles d'icône.
  static const double chip = 10;
}

/// Ombre « flottante » : un contact net + une diffusion large et douce.
/// [lift] de 0 (posé) à 1 (très soulevé) ; [tint] colore la diffusion.
List<BoxShadow> floatShadow(BuildContext context, {double lift = 0.5, Color? tint}) {
  final dark = context.ac.brightness == Brightness.dark;
  final base = dark ? Colors.black : context.ac.ink;
  final diffuse = tint ?? base;
  final k = dark ? 2.2 : 1.0;
  return [
    BoxShadow(
      color: base.withValues(alpha: 0.04 * k),
      blurRadius: 1.5,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: diffuse.withValues(alpha: (0.05 + 0.05 * lift) * k),
      blurRadius: 10 + 26 * lift,
      offset: Offset(0, 4 + 12 * lift),
      spreadRadius: -4,
    ),
  ];
}

/// Liseré clair sur le bord des cartes : accroche la lumière.
Border hairline(BuildContext context) => Border.all(
      color: context.ac.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.9),
      width: 1,
    );

/// Voile « verre » posé sur le bandeau : blanc sur bandeau foncé,
/// encre très légère sur bandeau clair (Lacté).
Color glass(BuildContext context, double alpha) => context.ac.lightHeader
    ? context.ac.onHeader.withValues(alpha: alpha * 0.45)
    : Colors.white.withValues(alpha: alpha);

/// Voile « verre » posé sur le contenu de la page (en-têtes, barres) :
/// surface translucide, plus claire en haut.
LinearGradient surfaceGlass(BuildContext context, {double strength = 1}) {
  final ac = context.ac;
  final dark = ac.brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      ac.surface.withValues(alpha: (dark ? 0.66 : 0.72) * strength),
      ac.surface.withValues(alpha: (dark ? 0.52 : 0.58) * strength),
    ],
  );
}
