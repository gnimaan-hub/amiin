// ─── Amiin Design Tokens ── Typography ──────────────────────────────────────
// Inter (géométrique) pour UI/titres — DM Sans (humaniste) pour le corps
// Space Mono pour les citations de sources et références légales

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

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
  static TextStyle screenTitle(BuildContext context) => GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.xl,
        color: ColorsAmiin.ink,
        letterSpacing: LetterSpacing.tight,
      );

  static TextStyle sectionTitle(BuildContext context) => GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.md,
        color: ColorsAmiin.ink,
        letterSpacing: LetterSpacing.tight,
      );

  static TextStyle body(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: FontSize.base,
        color: ColorsAmiin.ink,
        height: LineHeight.normal,
      );

  static TextStyle bodyMuted(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: FontSize.base,
        color: ColorsAmiin.muted,
        height: LineHeight.normal,
      );

  static TextStyle label(BuildContext context) => GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: FontSize.xs,
        color: ColorsAmiin.muted,
        letterSpacing: LetterSpacing.wider,
      );

  static TextStyle caption(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: FontSize.sm,
        color: ColorsAmiin.muted,
      );

  // Pour les sources et références — signal visuel "donnée vérifiable"
  static TextStyle sourceRef(BuildContext context) => GoogleFonts.spaceMono(
        fontWeight: FontWeight.w400,
        fontSize: FontSize.xs,
        color: ColorsAmiin.muted,
      );

  @Deprecated('Use screenTitle')
  static TextStyle tagline(BuildContext context) => screenTitle(context);
}
