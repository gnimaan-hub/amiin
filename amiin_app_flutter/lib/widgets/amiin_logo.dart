// ─── AmiinLogo — SVG icon widget ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AmiinLogoVariant { dark, light, turquoise, ocre, mono }

class AmiinLogo extends StatelessWidget {
  final double size;
  final AmiinLogoVariant variant;

  const AmiinLogo({
    super.key,
    this.size = 48,
    this.variant = AmiinLogoVariant.dark,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(variant);
    final String svgString = '''
      <svg viewBox="0 0 96 96" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="48" cy="48" r="46" fill="${config.bg}" />
        <path d="M26 70 L48 22 L70 70" stroke="${config.stroke}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M35 55 L61 55" stroke="${config.stroke}" stroke-width="3" stroke-linecap="round" />
        <line x1="48" y1="16" x2="48" y2="10" stroke="${config.accent}" stroke-width="2.5" stroke-linecap="round" />
        <line x1="44" y1="13" x2="52" y2="13" stroke="${config.accent}" stroke-width="2.5" stroke-linecap="round" />
      </svg>
    ''';

    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
    );
  }

  _AmiinLogoConfig _getConfig(AmiinLogoVariant variant) {
    switch (variant) {
      case AmiinLogoVariant.dark:
        return _AmiinLogoConfig(bg: '#14213D', stroke: '#F2EFE9', accent: '#1E8A8A');
      case AmiinLogoVariant.light:
        return _AmiinLogoConfig(bg: '#F2EFE9', stroke: '#14213D', accent: '#1E8A8A');
      case AmiinLogoVariant.turquoise:
        return _AmiinLogoConfig(bg: '#1E8A8A', stroke: '#FFFFFF', accent: '#FFFFFF');
      case AmiinLogoVariant.ocre:
        return _AmiinLogoConfig(bg: '#C8902F', stroke: '#FFFFFF', accent: '#FFFFFF');
      case AmiinLogoVariant.mono:
        return _AmiinLogoConfig(bg: '#14213D', stroke: '#FFFFFF', accent: '#FFFFFF');
    }
  }
}

class _AmiinLogoConfig {
  final String bg;
  final String stroke;
  final String accent;
  _AmiinLogoConfig({required this.bg, required this.stroke, required this.accent});
}
