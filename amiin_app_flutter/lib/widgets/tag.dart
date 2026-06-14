// ─── Tag ─────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum TagVariant { default_, terra, indigo, olive }

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
          fontFamily: FontFamily.sansBold,
          fontSize: 11,
          letterSpacing: 0.2,
          color: config.text,
        ),
      ),
    );
  }

  _TagConfig _getConfig(TagVariant v) {
    switch (v) {
      case TagVariant.default_:
        return _TagConfig(bg: ColorsAmiin.ecru, text: ColorsAmiin.mid, border: ColorsAmiin.border);
      case TagVariant.terra:
        return _TagConfig(bg: ColorsAmiin.terraLt, text: ColorsAmiin.terraDk, border: ColorsAmiin.terraLt);
      case TagVariant.indigo:
        return _TagConfig(bg: ColorsAmiin.indigoLt, text: ColorsAmiin.indigo, border: ColorsAmiin.indigoLt);
      case TagVariant.olive:
        return _TagConfig(bg: ColorsAmiin.oliveLt, text: ColorsAmiin.olive, border: ColorsAmiin.oliveLt);
    }
  }
}

class _TagConfig {
  final Color bg;
  final Color text;
  final Color border;
  _TagConfig({required this.bg, required this.text, required this.border});
}