// ─── Amiin Theme System ───────────────────────────────────────────────────────
// 4 variantes : deux claires (turquoise / ocre) + deux sombres (turquoise / ocre)
// La dualité info (ocre) / secrétariat (turquoise) est lisible dans chaque variante.
// context.ac donne accès à tous les tokens depuis n'importe quel widget.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Extension custom : tokens exposés aux widgets ─────────────────────────────

class AmiinThemeColors extends ThemeExtension<AmiinThemeColors> {
  final Color primary;           // accent principal (turquoise ou ocre selon variante)
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryMid;
  final Color infoAccent;        // ocre — contenu éditorial, démarches, annuaire
  final Color infoAccentLight;
  final Color secretariatAccent; // turquoise — agenda, notes, chat
  final Color secretariatAccentLight;
  final Color alertColor;        // corail — alertes uniquement
  final Color background;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color border;
  final Color headerGradientStart;
  final Color headerGradientEnd;
  final Color onHeader;
  final Brightness brightness;

  const AmiinThemeColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryMid,
    required this.infoAccent,
    required this.infoAccentLight,
    required this.secretariatAccent,
    required this.secretariatAccentLight,
    required this.alertColor,
    required this.background,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.border,
    required this.headerGradientStart,
    required this.headerGradientEnd,
    required this.onHeader,
    required this.brightness,
  });

  @override
  AmiinThemeColors copyWith({
    Color? primary, Color? primaryLight, Color? primaryDark, Color? primaryMid,
    Color? infoAccent, Color? infoAccentLight,
    Color? secretariatAccent, Color? secretariatAccentLight,
    Color? alertColor,
    Color? background, Color? surface, Color? surface2,
    Color? ink, Color? muted, Color? border,
    Color? headerGradientStart, Color? headerGradientEnd, Color? onHeader,
    Brightness? brightness,
  }) => AmiinThemeColors(
    primary: primary ?? this.primary,
    primaryLight: primaryLight ?? this.primaryLight,
    primaryDark: primaryDark ?? this.primaryDark,
    primaryMid: primaryMid ?? this.primaryMid,
    infoAccent: infoAccent ?? this.infoAccent,
    infoAccentLight: infoAccentLight ?? this.infoAccentLight,
    secretariatAccent: secretariatAccent ?? this.secretariatAccent,
    secretariatAccentLight: secretariatAccentLight ?? this.secretariatAccentLight,
    alertColor: alertColor ?? this.alertColor,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    headerGradientStart: headerGradientStart ?? this.headerGradientStart,
    headerGradientEnd: headerGradientEnd ?? this.headerGradientEnd,
    onHeader: onHeader ?? this.onHeader,
    brightness: brightness ?? this.brightness,
  );

  @override
  AmiinThemeColors lerp(ThemeExtension<AmiinThemeColors>? other, double t) {
    if (other is! AmiinThemeColors) return this;
    return AmiinThemeColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryMid: Color.lerp(primaryMid, other.primaryMid, t)!,
      infoAccent: Color.lerp(infoAccent, other.infoAccent, t)!,
      infoAccentLight: Color.lerp(infoAccentLight, other.infoAccentLight, t)!,
      secretariatAccent: Color.lerp(secretariatAccent, other.secretariatAccent, t)!,
      secretariatAccentLight: Color.lerp(secretariatAccentLight, other.secretariatAccentLight, t)!,
      alertColor: Color.lerp(alertColor, other.alertColor, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      headerGradientStart: Color.lerp(headerGradientStart, other.headerGradientStart, t)!,
      headerGradientEnd: Color.lerp(headerGradientEnd, other.headerGradientEnd, t)!,
      onHeader: Color.lerp(onHeader, other.onHeader, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }

  // ── 4 Variantes ──────────────────────────────────────────────────────────────

  // "Sel d'Assal" — jour clair, accent secrétariat (turquoise)
  static const terre = AmiinThemeColors(
    primary:                    Color(0xFF1E8A8A),
    primaryLight:               Color(0xFFCCEBEB),
    primaryDark:                Color(0xFF135E5E),
    primaryMid:                 Color(0xFF2AADAD),
    infoAccent:                 Color(0xFFC8902F),
    infoAccentLight:            Color(0xFFF5E8CC),
    secretariatAccent:          Color(0xFF1E8A8A),
    secretariatAccentLight:     Color(0xFFCCEBEB),
    alertColor:                 Color(0xFFC75145),
    background:                 Color(0xFFF2EFE9),
    surface:                    Color(0xFFFFFFFF),
    surface2:                   Color(0xFFE4E8F0),
    ink:                        Color(0xFF14213D),
    muted:                      Color(0xFF7A8BA8),
    border:                     Color(0xFFD0D5E2),
    headerGradientStart:        Color(0xFF14213D),
    headerGradientEnd:          Color(0xFF1C2E52),
    onHeader:                   Color(0xFFF2EFE9),
    brightness:                 Brightness.light,
  );

  // "Aurore" — jour clair, accent information (ocre)
  static const ocean = AmiinThemeColors(
    primary:                    Color(0xFFC8902F),
    primaryLight:               Color(0xFFF5E8CC),
    primaryDark:                Color(0xFF8F6520),
    primaryMid:                 Color(0xFFDEA844),
    infoAccent:                 Color(0xFFC8902F),
    infoAccentLight:            Color(0xFFF5E8CC),
    secretariatAccent:          Color(0xFF1E8A8A),
    secretariatAccentLight:     Color(0xFFCCEBEB),
    alertColor:                 Color(0xFFC75145),
    background:                 Color(0xFFF2EFE9),
    surface:                    Color(0xFFFFFFFF),
    surface2:                   Color(0xFFEDE8F5),
    ink:                        Color(0xFF14213D),
    muted:                      Color(0xFF7A8BA8),
    border:                     Color(0xFFD0D5E2),
    headerGradientStart:        Color(0xFF2A1F0A),
    headerGradientEnd:          Color(0xFF3A2D14),
    onHeader:                   Color(0xFFF2EFE9),
    brightness:                 Brightness.light,
  );

  // "Dusk" — nuit sombre, accent information (ocre)
  static const foret = AmiinThemeColors(
    primary:                    Color(0xFFC8902F),
    primaryLight:               Color(0xFF3A2D14),
    primaryDark:                Color(0xFF8F6520),
    primaryMid:                 Color(0xFFDEA844),
    infoAccent:                 Color(0xFFC8902F),
    infoAccentLight:            Color(0xFF3A2D14),
    secretariatAccent:          Color(0xFF1E8A8A),
    secretariatAccentLight:     Color(0xFF1A3535),
    alertColor:                 Color(0xFFC75145),
    background:                 Color(0xFF14213D),
    surface:                    Color(0xFF1C2E52),
    surface2:                   Color(0xFF162038),
    ink:                        Color(0xFFF2EFE9),
    muted:                      Color(0xFF8090B0),
    border:                     Color(0xFF2A3A5A),
    headerGradientStart:        Color(0xFF0D1526),
    headerGradientEnd:          Color(0xFF14213D),
    onHeader:                   Color(0xFFF2EFE9),
    brightness:                 Brightness.dark,
  );

  // "Encre de Nuit" — nuit sombre, accent secrétariat (turquoise)
  static const nuit = AmiinThemeColors(
    primary:                    Color(0xFF1E8A8A),
    primaryLight:               Color(0xFF1A3535),
    primaryDark:                Color(0xFF135E5E),
    primaryMid:                 Color(0xFF2AADAD),
    infoAccent:                 Color(0xFFC8902F),
    infoAccentLight:            Color(0xFF3A2D14),
    secretariatAccent:          Color(0xFF1E8A8A),
    secretariatAccentLight:     Color(0xFF1A3535),
    alertColor:                 Color(0xFFC75145),
    background:                 Color(0xFF14213D),
    surface:                    Color(0xFF1C2E52),
    surface2:                   Color(0xFF162038),
    ink:                        Color(0xFFF2EFE9),
    muted:                      Color(0xFF8090B0),
    border:                     Color(0xFF2A3A5A),
    headerGradientStart:        Color(0xFF0D1526),
    headerGradientEnd:          Color(0xFF14213D),
    onHeader:                   Color(0xFFF2EFE9),
    brightness:                 Brightness.dark,
  );
}

// ── Variantes disponibles ─────────────────────────────────────────────────────

enum AmiinThemeVariant { terre, ocean, foret, nuit }

extension AmiinThemeVariantExt on AmiinThemeVariant {
  String get id {
    switch (this) {
      case AmiinThemeVariant.terre: return 'terre';
      case AmiinThemeVariant.ocean: return 'ocean';
      case AmiinThemeVariant.foret: return 'foret';
      case AmiinThemeVariant.nuit:  return 'nuit';
    }
  }

  String get label {
    switch (this) {
      case AmiinThemeVariant.terre: return "Sel d'Assal";
      case AmiinThemeVariant.ocean: return 'Aurore';
      case AmiinThemeVariant.foret: return 'Dusk';
      case AmiinThemeVariant.nuit:  return 'Encre de Nuit';
    }
  }

  AmiinThemeColors get colors {
    switch (this) {
      case AmiinThemeVariant.terre: return AmiinThemeColors.terre;
      case AmiinThemeVariant.ocean: return AmiinThemeColors.ocean;
      case AmiinThemeVariant.foret: return AmiinThemeColors.foret;
      case AmiinThemeVariant.nuit:  return AmiinThemeColors.nuit;
    }
  }

  static AmiinThemeVariant fromId(String id) {
    switch (id) {
      case 'ocean': return AmiinThemeVariant.ocean;
      case 'foret': return AmiinThemeVariant.foret;
      case 'nuit':  return AmiinThemeVariant.nuit;
      default:      return AmiinThemeVariant.terre;
    }
  }
}

// ── Constructeur de ThemeData ─────────────────────────────────────────────────

class AmiinThemes {
  static ThemeData forVariant(AmiinThemeVariant variant, String font) {
    final c = variant.colors;
    final isDark = c.brightness == Brightness.dark;
    final ff = _fontFamily(font);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: c.primary,
      primary: c.primary,
      surface: c.surface,
      brightness: c.brightness,
    ).copyWith(
      onPrimary: Colors.white,
      onSurface: c.ink,
      outline: c.border,
      surfaceContainerHighest: c.surface2,
      surfaceContainerLow: c.background,
      error: c.alertColor,
    );

    final baseTextTheme = TextTheme(
      bodyLarge:   TextStyle(fontSize: 15, color: c.ink,   fontFamily: ff, height: 1.6),
      bodyMedium:  TextStyle(fontSize: 14, color: c.ink,   fontFamily: ff, height: 1.6),
      bodySmall:   TextStyle(fontSize: 12, color: c.muted, fontFamily: ff),
      titleLarge:  TextStyle(fontSize: 20, color: c.ink,   fontFamily: _geoFamily(), fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: TextStyle(fontSize: 16, color: c.ink,   fontFamily: _geoFamily(), fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleSmall:  TextStyle(fontSize: 14, color: c.ink,   fontFamily: _geoFamily(), fontWeight: FontWeight.w500),
      labelLarge:  TextStyle(fontSize: 14, color: c.ink,   fontFamily: _geoFamily(), fontWeight: FontWeight.w500),
      labelMedium: TextStyle(fontSize: 12, color: c.muted, fontFamily: _geoFamily()),
      labelSmall:  TextStyle(fontSize: 10, color: c.muted, fontFamily: _geoFamily(), letterSpacing: 0.8),
    );

    return ThemeData(
      colorScheme: colorScheme,
      brightness: c.brightness,
      fontFamily: ff,
      scaffoldBackgroundColor: c.background,
      cardColor: c.surface,
      dividerColor: c.border,
      textTheme: baseTextTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 17,
          color: c.ink,
          fontFamily: _geoFamily(),
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontFamily: _geoFamily(), fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontFamily: _geoFamily()),
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: c.surface,
        textColor: c.ink,
        iconColor: c.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: TextStyle(color: c.muted, fontFamily: ff),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),

      dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          textStyle: TextStyle(fontFamily: _geoFamily(), fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(double.infinity, 50),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: TextStyle(fontFamily: _geoFamily(), fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          side: BorderSide(color: c.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surface2,
        selectedColor: c.primaryLight,
        labelStyle: TextStyle(color: c.ink, fontFamily: ff, fontSize: 13),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        thumbColor: c.primary,
        inactiveTrackColor: c.border,
        overlayColor: c.primary.withValues(alpha: 0.12),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.primary : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.primaryLight : c.border),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        titleTextStyle: TextStyle(fontSize: 18, color: c.ink, fontFamily: _geoFamily(), fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(fontSize: 14, color: c.ink, fontFamily: ff, height: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.surface2 : c.ink,
        contentTextStyle: TextStyle(color: c.onHeader, fontFamily: ff),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        textStyle: TextStyle(color: c.ink, fontFamily: ff, fontSize: 14),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: c.primary,
        textColor: Colors.white,
      ),

      extensions: [c],
    );
  }

  static String _fontFamily(String font) {
    switch (font) {
      case 'opensans': return GoogleFonts.openSans().fontFamily ?? 'Open Sans';
      case 'noto':     return GoogleFonts.notoSans().fontFamily ?? 'Noto Sans';
      default:         return GoogleFonts.dmSans().fontFamily   ?? 'DM Sans';
    }
  }

  static String _geoFamily() =>
      GoogleFonts.inter().fontFamily ?? 'Inter';
}

// ── Raccourci BuildContext ─────────────────────────────────────────────────────

extension AmiinContextExt on BuildContext {
  AmiinThemeColors get ac =>
      Theme.of(this).extension<AmiinThemeColors>() ?? AmiinThemeColors.terre;
}
