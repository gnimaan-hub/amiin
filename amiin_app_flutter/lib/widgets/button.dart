import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum ButtonVariant { primary, secondary, ghost, danger, info }
enum ButtonSize { sm, md, lg }

class AmiinButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;
  final bool disabled;
  final bool fullWidth;
  final Widget? icon;

  const AmiinButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.md,
    this.loading = false,
    this.disabled = false,
    this.fullWidth = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getVariantConfig(variant);
    final sizeConfig = _getSizeConfig(size);

    return ElevatedButton(
      onPressed: (disabled || loading) ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: config.bg,
        foregroundColor: config.text,
        disabledBackgroundColor: config.bg.withValues(alpha: 0.4),
        disabledForegroundColor: config.text.withValues(alpha: 0.4),
        side: BorderSide(color: config.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: sizeConfig.px),
        minimumSize: fullWidth ? Size(double.infinity, sizeConfig.height) : Size(0, sizeConfig.height),
      ),
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: config.text),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 6)],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: FontFamily.geoBold,
                    fontSize: sizeConfig.font,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
    );
  }

  _ButtonVariantConfig _getVariantConfig(ButtonVariant v) {
    switch (v) {
      case ButtonVariant.primary:
        return _ButtonVariantConfig(
            bg: ColorsAmiin.turquoise, text: ColorsAmiin.white, border: ColorsAmiin.turquoise);
      case ButtonVariant.secondary:
        return _ButtonVariantConfig(
            bg: ColorsAmiin.turquoiseLt, text: ColorsAmiin.turquoiseDk, border: ColorsAmiin.turquoiseLt);
      case ButtonVariant.ghost:
        return _ButtonVariantConfig(
            bg: Colors.transparent, text: ColorsAmiin.turquoise, border: ColorsAmiin.border);
      case ButtonVariant.info:
        return _ButtonVariantConfig(
            bg: ColorsAmiin.ocre, text: ColorsAmiin.white, border: ColorsAmiin.ocre);
      case ButtonVariant.danger:
        return _ButtonVariantConfig(
            bg: ColorsAmiin.corail, text: ColorsAmiin.white, border: ColorsAmiin.corail);
    }
  }

  _ButtonSizeConfig _getSizeConfig(ButtonSize s) {
    switch (s) {
      case ButtonSize.sm:
        return _ButtonSizeConfig(height: 34, px: Spacing.md, font: 13.0);
      case ButtonSize.md:
        return _ButtonSizeConfig(height: 46, px: Spacing.xl, font: 15.0);
      case ButtonSize.lg:
        return _ButtonSizeConfig(height: 54, px: Spacing.xxl, font: 16.0);
    }
  }
}

class _ButtonVariantConfig {
  final Color bg, text, border;
  _ButtonVariantConfig({required this.bg, required this.text, required this.border});
}

class _ButtonSizeConfig {
  final double height, px, font;
  _ButtonSizeConfig({required this.height, required this.px, required this.font});
}
