// ─── Tag ──────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/themes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum TagVariant { default_, turquoise, ocre, success, alert }

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
    final config = _getConfig(context, variant);
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

  _TagConfig _getConfig(BuildContext context, TagVariant v) {
    switch (v) {
      case TagVariant.default_:
        return _TagConfig(bg: context.ac.background, text: context.ac.midTone, border: context.ac.border);
      case TagVariant.turquoise:
        return _TagConfig(bg: context.ac.secretariatAccentLight, text: context.ac.secretariatAccentDark, border: context.ac.secretariatAccentLight);
      case TagVariant.ocre:
        return _TagConfig(bg: context.ac.infoAccentLight, text: context.ac.infoAccentDark, border: context.ac.infoAccentLight);
      case TagVariant.success:
        return _TagConfig(bg: context.ac.successLight, text: context.ac.success, border: context.ac.successLight);
      case TagVariant.alert:
        return _TagConfig(bg: context.ac.alertColorLight, text: context.ac.alertColor, border: context.ac.alertColorLight);
    }
  }
}

class _TagConfig {
  final Color bg;
  final Color text;
  final Color border;
  _TagConfig({required this.bg, required this.text, required this.border});
}
