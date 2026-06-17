// ─── Tag ──────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum TagVariant { default_, turquoise, ocre, success, alert }

// Alias rétrocompat
const TagVariant tagTerra    = TagVariant.turquoise;
const TagVariant tagIndigo   = TagVariant.ocre;
const TagVariant tagOlive    = TagVariant.success;

class AmiinTag extends StatelessWidget {
  final String label;
  final TagVariant variant;

  const AmiinTag({
    super.key,
    required this.label,
    this.variant = TagVariant.default_,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(variant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
        border: Border.all(color: config.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: FontFamily.geoBold,
          fontSize: 10,
          letterSpacing: 0.3,
          color: config.text,
        ),
      ),
    );
  }

  _TagConfig _getConfig(TagVariant v) {
    switch (v) {
      case TagVariant.default_:
        return _TagConfig(bg: ColorsAmiin.ecru, text: ColorsAmiin.mid, border: ColorsAmiin.border);
      case TagVariant.turquoise:
        return _TagConfig(bg: ColorsAmiin.turquoiseLt, text: ColorsAmiin.turquoiseDk, border: ColorsAmiin.turquoiseLt);
      case TagVariant.ocre:
        return _TagConfig(bg: ColorsAmiin.ocreLt, text: ColorsAmiin.ocreDk, border: ColorsAmiin.ocreLt);
      case TagVariant.success:
        return _TagConfig(bg: ColorsAmiin.successLt, text: ColorsAmiin.success, border: ColorsAmiin.successLt);
      case TagVariant.alert:
        return _TagConfig(bg: ColorsAmiin.corailLt, text: ColorsAmiin.corail, border: ColorsAmiin.corailLt);
    }
  }
}

class _TagConfig {
  final Color bg;
  final Color text;
  final Color border;
  _TagConfig({required this.bg, required this.text, required this.border});
}
