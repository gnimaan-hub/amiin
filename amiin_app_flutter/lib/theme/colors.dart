// ─── Amiin Design Tokens ── Colors ──────────────────────────────────────────

import 'package:flutter/material.dart';


class ColorsAmiin {
  // Brand
  static const Color terra = Color(0xFFB85530);
  static const Color terraDk = Color(0xFF8C3D20);
  static const Color terraLt = Color(0xFFF2E0D6);
  static const Color terraMid = Color(0xFFD4784A);

  static const Color indigo = Color(0xFF2D3D7A);
  static const Color indigoLt = Color(0xFFD4D9EE);

  static const Color olive = Color(0xFF4A6741);
  static const Color oliveLt = Color(0xFFD5E3D2);

  // Neutrals
  static const Color ink = Color(0xFF1A1208);
  static const Color darkMid = Color(0xFF2C2114);
  static const Color mid = Color(0xFF6B5E4E);
  static const Color muted = Color(0xFF9C8E80);
  static const Color border = Color(0xFFDDD5C5);
  static const Color borderMid = Color(0xFFC8BCAA);
  static const Color sand = Color(0xFFEDE5D5);
  static const Color ecru = Color(0xFFF4EFE6);
  static const Color white = Color(0xFFFFFFFF);

  // Semantic
  static const Color success = Color(0xFF4A6741);
  static const Color successLt = Color(0xFFD5E3D2);
  static const Color warning = Color(0xFFB85530);
  static const Color warningLt = Color(0xFFF2E0D6);
  static const Color info = Color(0xFF2D3D7A);
  static const Color infoLt = Color(0xFFD4D9EE);

  // Text on dark
  static const Color onDark = Color(0xFFF4EFE6);
  static const Color onTerra = Color(0xFFFFFFFF);

  // Shadows (opacités converties en double)
  static const Color shadow = Color(0x14B85530);   // rgba(26,18,8,0.08) ~ #1A120814
  static const Color shadowMd = Color(0x241A1208); // 0.14 -> 0x24
  static const Color shadowLg = Color(0x381A1208); // 0.22 -> 0x38
}