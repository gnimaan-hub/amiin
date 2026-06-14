// ─── Amiin Design Tokens ── Typography ──────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class FontFamily {
  static String get serif => GoogleFonts.playfairDisplay().fontFamily!;
  static String get serifBold => GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700).fontFamily!;
  static String get serifItalic => GoogleFonts.playfairDisplay(fontStyle: FontStyle.italic).fontFamily!;
  static String get sansLight => GoogleFonts.dmSans(fontWeight: FontWeight.w300).fontFamily!;
  static String get sans => GoogleFonts.dmSans().fontFamily!;
  static String get sansMedium => GoogleFonts.dmSans(fontWeight: FontWeight.w500).fontFamily!;
  static String get sansBold => GoogleFonts.dmSans(fontWeight: FontWeight.w600).fontFamily!;
}

class FontSize {
  static const double xs = 10.0;
  static const double sm = 12.0;
  static const double base = 14.0;
  static const double md = 16.0;
  static const double lg = 18.0;
  static const double xl = 22.0;
  static const double xxl = 28.0;
  static const double xxxl = 36.0;
  static const double display = 48.0;
}

class LineHeight {
  static const double tight = 1.2;
  static const double normal = 1.5;
  static const double loose = 1.7;
}

class LetterSpacing {
  static const double tight = -0.3;
  static const double normal = 0.0;
  static const double wide = 0.5;
  static const double wider = 1.2;
  static const double widest = 2.0;
}

class TextStyles {
  static TextStyle screenTitle(BuildContext context) => GoogleFonts.playfairDisplay(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.xl,
        color: ColorsAmiin.ink,
        letterSpacing: LetterSpacing.wide,
      );

  static TextStyle sectionTitle(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.md,
        color: ColorsAmiin.ink,
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

  static TextStyle label(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.xs,
        color: ColorsAmiin.muted,
        letterSpacing: LetterSpacing.wider,
      );

  static TextStyle caption(BuildContext context) => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: FontSize.sm,
        color: ColorsAmiin.muted,
      );

  static TextStyle tagline(BuildContext context) => GoogleFonts.playfairDisplay(
        fontWeight: FontWeight.w600,
        fontSize: FontSize.lg,
        color: ColorsAmiin.ink,
        fontStyle: FontStyle.italic,
      );
}