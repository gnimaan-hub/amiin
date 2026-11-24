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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.bg,
        // Pastille en pilule, sans contour (refonte « vitrine »).
        borderRadius: BorderRadius.circular(RadiusAmiin.full),
      ),
      child: Text(
        label,
        style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: config.text, letterSpacing: 0.3, fontFamily: FontFamily.geoBold),
      ),
    );
  }

  _TagConfig _getConfig(BuildContext context, TagVariant v) {
    switch (v) {
      case TagVariant.default_:
        // surface2 se confond avec le fond en sombre : on y prend la surface.
        return _TagConfig(
          bg: context.ac.brightness == Brightness.dark ? context.ac.surface : context.ac.surface2,
          text: context.ac.midTone,
          border: context.ac.border,
        );
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
