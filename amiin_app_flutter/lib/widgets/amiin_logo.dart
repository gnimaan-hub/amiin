// ─── AmiinLogo — SVG icon widget ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';


enum AmiinLogoVariant { dark, light, terra, mono }

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
        <circle cx="48" cy="48" r="46" fill="${config.bg}" stroke="${config.stroke}" stroke-width="1.5" />
        <circle cx="48" cy="48" r="36" fill="${config.ring}" opacity="0.15" />
        <path d="M28 68 L48 24 L68 68" stroke="${config.stroke}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M36 54 L60 54" stroke="${config.stroke}" stroke-width="3.5" stroke-linecap="round" />
        <circle cx="48" cy="17" r="3" fill="${config.stroke}" />
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
        return _AmiinLogoConfig(bg: '#2C2114', ring: '#B85530', stroke: '#B85530');
      case AmiinLogoVariant.light:
        return _AmiinLogoConfig(bg: '#F2E0D6', ring: '#B85530', stroke: '#B85530');
      case AmiinLogoVariant.terra:
        return _AmiinLogoConfig(bg: '#B85530', ring: 'rgba(255,255,255,0.2)', stroke: '#FFFFFF');
      case AmiinLogoVariant.mono:
        return _AmiinLogoConfig(bg: '#1A1208', ring: 'transparent', stroke: '#FFFFFF');
    }
  }
}

class _AmiinLogoConfig {
  final String bg;
  final String ring;
  final String stroke;
  _AmiinLogoConfig({required this.bg, required this.ring, required this.stroke});
}