// ─── Amiin Design Tokens ── Typography ──────────────────────────────────────
// Inter (géométrique) pour UI/titres — DM Sans (humaniste) pour le corps
// Space Mono pour les citations de sources et références légales

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'themes.dart';

class FontFamily {
  // Géométrique sobre — titres, labels, navigation
  static final String geo        = GoogleFonts.inter().fontFamily!;
  static final String geoMedium  = GoogleFonts.inter(fontWeight: FontWeight.w500).fontFamily!;
  static final String geoBold    = GoogleFonts.inter(fontWeight: FontWeight.w700).fontFamily!;
  static final String geoLight   = GoogleFonts.inter(fontWeight: FontWeight.w300).fontFamily!;

  // Humaniste — corps de texte, réponses longues
  static final String sans       = GoogleFonts.dmSans().fontFamily!;
  static final String sansMedium = GoogleFonts.dmSans(fontWeight: FontWeight.w500).fontFamily!;
  static final String sansBold   = GoogleFonts.dmSans(fontWeight: FontWeight.w600).fontFamily!;
  static final String sansLight  = GoogleFonts.dmSans(fontWeight: FontWeight.w300).fontFamily!;

  // Mono — sources vérifiables, citations légales, références
  static final String mono       = GoogleFonts.spaceMono().fontFamily!;
  static final String monoBold   = GoogleFonts.spaceMono(fontWeight: FontWeight.w700).fontFamily!;

  // Alias rétrocompat (seront supprimés progressivement)
  @Deprecated('Use geo') static String get serif        => geo;
  @Deprecated('Use geoBold') static String get serifBold  => geoBold;
  @Deprecated('Use geo') static String get serifItalic    => geo;
}

class FontSize {
  static const double xs      = 10.0;
  static const double sm      = 12.0;
  static const double base    = 14.0;
  static const double md      = 16.0;
  static const double lg      = 18.0;
  static const double xl      = 22.0;
  static const double xxl     = 28.0;
  static const double xxxl    = 36.0;
  static const double display = 48.0;
}

class LineHeight {
  static const double tight  = 1.2;
  static const double normal = 1.5;
  static const double loose  = 1.7;
}

class LetterSpacing {
  static const double tight   = -0.3;
  static const double normal  = 0.0;
  static const double wide    = 0.3;
  static const double wider   = 0.8;
  static const double widest  = 2.0;
}

class TextStyles {
  // ── Styles nommés, theme-aware (context.ac) ─────────────────────────────
  // Règle de la refonte : les écrans utilisent CES styles (copyWith au besoin
  // pour la couleur d'accent), plus de TextStyle artisanal.

  /// Grand titre d'écran héros (accueil, auth).
  static TextStyle displayTitle(BuildContext context) => TextStyle(
        fontFamily: FontFamily.geoBold,
        fontSize: FontSize.xxl,
        color: context.ac.ink,
        letterSpacing: LetterSpacing.tight,
        height: LineHeight.tight,
      );

  /// Titre d'écran standard (headers).
  static TextStyle screenTitle(BuildContext context) => TextStyle(
        fontFamily: FontFamily.geoBold,
        fontSize: FontSize.lg,
        color: context.ac.ink,
        letterSpacing: LetterSpacing.tight,
      );

  /// Label de section en capitales (ACCÈS RAPIDE, AUJOURD'HUI…).
  static TextStyle sectionLabel(BuildContext context) => TextStyle(
        fontFamily: FontFamily.geo,
        fontWeight: FontWeight.w600,
        fontSize: FontSize.xs,
        color: context.ac.muted,
        letterSpacing: LetterSpacing.widest * 0.6,
      );

  /// Titre d'une carte ou d'un élément de liste.
  static TextStyle cardTitle(BuildContext context) => TextStyle(
        fontFamily: FontFamily.geoMedium,
        fontSize: FontSize.base,
        color: context.ac.ink,
      );

  /// Corps de texte.
  static TextStyle body(BuildContext context) => TextStyle(
        fontFamily: FontFamily.sans,
        fontSize: FontSize.base,
        color: context.ac.ink,
        height: LineHeight.normal,
      );

  /// Corps atténué (sous-titres, descriptions).
  static TextStyle bodyMuted(BuildContext context) => TextStyle(
        fontFamily: FontFamily.sans,
        fontSize: FontSize.base,
        color: context.ac.muted,
        height: LineHeight.normal,
      );

  /// Métadonnées, horodatages, légendes.
  static TextStyle caption(BuildContext context) => TextStyle(
        fontFamily: FontFamily.sans,
        fontSize: FontSize.sm,
        color: context.ac.muted,
      );

  /// Sources et références vérifiables (mono).
  static TextStyle sourceRef(BuildContext context) => TextStyle(
        fontFamily: FontFamily.mono,
        fontSize: FontSize.xs,
        color: context.ac.muted,
      );
}
