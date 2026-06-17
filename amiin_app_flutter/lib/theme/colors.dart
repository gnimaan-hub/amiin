// ─── Amiin Design Tokens ── Colors ───────────────────────────────────────────
// Palette ancrée dans le paysage de Djibouti

import 'package:flutter/material.dart';

class ColorsAmiin {
  // ── Palette Djibouti ────────────────────────────────────────────────────────

  // Encre de Nuit — fond sombre, ciel nocturne sur le golfe de Tadjourah
  static const Color encreNuit     = Color(0xFF14213D);
  static const Color darkMid       = Color(0xFF1C2E52);

  // Sel d'Assal — fond clair minéral, salines du lac Assal
  static const Color selAssal      = Color(0xFFF2EFE9);

  // Turquoise Tadjourah — accent secrétariat (agenda, notes, chat, actions)
  static const Color turquoise     = Color(0xFF1E8A8A);
  static const Color turquoiseDk   = Color(0xFF135E5E);
  static const Color turquoiseLt   = Color(0xFFCCEBEB);
  static const Color turquoiseMid  = Color(0xFF2AADAD);

  // Ocre des Dunes — accent information (démarches, annuaire, contenu éditorial)
  static const Color ocre          = Color(0xFFC8902F);
  static const Color ocreDk        = Color(0xFF8F6520);
  static const Color ocreLt        = Color(0xFFF5E8CC);
  static const Color ocreMid       = Color(0xFFDEA844);

  // Corail — alertes et échéances urgentes uniquement (usage parcimonieux)
  static const Color corail        = Color(0xFFC75145);
  static const Color corailLt      = Color(0xFFF5D0CC);

  // Succès / complété
  static const Color success       = Color(0xFF2A7A5A);
  static const Color successLt     = Color(0xFFCCE8DD);

  // ── Neutrals ─────────────────────────────────────────────────────────────
  static const Color ink           = Color(0xFF14213D);
  static const Color mid           = Color(0xFF4A5A7A);
  static const Color muted         = Color(0xFF7A8BA8);
  static const Color border        = Color(0xFFD0D5E2);
  static const Color borderMid     = Color(0xFFB8C0D2);
  static const Color sand          = Color(0xFFE4E8F0);
  static const Color ecru          = Color(0xFFF2EFE9);
  static const Color white         = Color(0xFFFFFFFF);

  // ── Texte sur fond sombre ─────────────────────────────────────────────────
  static const Color onDark        = Color(0xFFF2EFE9);
  static const Color onTurquoise   = Color(0xFFFFFFFF);
  static const Color onOcre        = Color(0xFFFFFFFF);

  // ── Ombres ───────────────────────────────────────────────────────────────
  static const Color shadow        = Color(0x1414213D);
  static const Color shadowMd      = Color(0x2414213D);
  static const Color shadowLg      = Color(0x3814213D);

  // ── Aliases pour rétrocompatibilité (seront supprimés progressivement) ───
  @Deprecated('Use turquoise') static const Color terra       = turquoise;
  @Deprecated('Use turquoiseDk') static const Color terraDk  = turquoiseDk;
  @Deprecated('Use turquoiseLt') static const Color terraLt  = turquoiseLt;
  @Deprecated('Use turquoiseMid') static const Color terraMid = turquoiseMid;
  @Deprecated('Use ocre') static const Color indigo           = ocre;
  @Deprecated('Use ocreLt') static const Color indigoLt       = ocreLt;
  @Deprecated('Use success') static const Color olive         = success;
  @Deprecated('Use successLt') static const Color oliveLt     = successLt;
}
