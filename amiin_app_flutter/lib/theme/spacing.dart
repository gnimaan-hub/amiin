// ─── Amiin Design Tokens ── Spacing & Radii ─────────────────────────────────
// Pour les ombres, on peut soit les définir comme des List<BoxShadow>
// soit garder une classe utilitaire. Voici la conversion :
import 'package:flutter/material.dart';
import 'colors.dart';   

class Spacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

class RadiusAmiin {
  static const double sm = 6.0;
  static const double md = 10.0;
  static const double lg = 14.0;
  static const double xl = 20.0;
  static const double full = 9999.0;
}

class ShadowAmiin {
  static List<BoxShadow> get sm => [
        BoxShadow(
          color: ColorsAmiin.shadow,
          offset: const Offset(0, 1),
          blurRadius: 4,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: ColorsAmiin.shadowMd,
          offset: const Offset(0, 2),
          blurRadius: 8,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: ColorsAmiin.shadowLg,
          offset: const Offset(0, 4),
          blurRadius: 16,
          spreadRadius: 0,
        ),
      ];
}