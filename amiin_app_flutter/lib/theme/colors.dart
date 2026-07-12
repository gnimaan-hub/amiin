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
}

// ── Palette catégorielle — identique en clair et sombre ──────────────────────
// Couleurs d'identification (annuaire, catégories d'événements) : elles ne
// suivent pas le thème, comme les couleurs d'un logo.

class CategoryColors {
  static const Color education = Color(0xFF8C6D3F);

  static const Map<String, Color> annuaire = {
    'Alimentation & Restauration':               Color(0xFFE07B39),
    'Hébergement':                               Color(0xFF1A7A6E),
    'Santé':                                     Color(0xFFC0392B),
    'Commerce & Courses':                        Color(0xFF6B7C3A),
    'Transport & Logistique':                    Color(0xFF2980B9),
    'Éducation & Formation':                     education,
    'Administration & Services publics':         Color(0xFF3D5A8A),
    'Services financiers & juridiques':          Color(0xFF8B6914),
    'Culture & Culte':                           Color(0xFF7B4B94),
    'Tourisme & Loisirs':                        Color(0xFF0097A7),
    'Services automobile':                       Color(0xFF546E7A),
    'Services à la personne':                    Color(0xFF6D4C7E),
    'Géographie & Patrimoine naturel':           Color(0xFF388E3C),
    'Diplomatie & Organisations internationales':Color(0xFF1A3A5C),
    'Industrie, Énergie & Grandes entreprises':  Color(0xFF4E4E4E),
    'Télécom & Tech':                            Color(0xFF1565C0),
    'Associations & ONG':                        Color(0xFFAD1457),
    'Défense internationale':                    Color(0xFF33691E),
  };
}
