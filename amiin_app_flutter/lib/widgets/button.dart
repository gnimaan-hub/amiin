import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum ButtonVariant { primary, secondary, ghost, danger }
enum ButtonSize { sm, md, lg }

class AmiinButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;
  final bool disabled;
  final bool fullWidth;

  const AmiinButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.md,
    this.loading = false,
    this.disabled = false,
    this.fullWidth = false,
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
        disabledBackgroundColor: config.bg.withValues(alpha: 0.45),
        disabledForegroundColor: config.text.withValues(alpha: 0.45),
        side: BorderSide(color: config.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RadiusAmiin.md)),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: sizeConfig.px),
        minimumSize: fullWidth ? Size(double.infinity, sizeConfig.height) : Size(0, sizeConfig.height),
      ),
      child: loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(
              label,
              style: TextStyle(
                fontFamily: FontFamily.sansBold,
                fontSize: sizeConfig.font,
                letterSpacing: 0.2,
              ),
            ),
    );
  }

  _ButtonVariantConfig _getVariantConfig(ButtonVariant v) {
    switch (v) {
      case ButtonVariant.primary:
        return _ButtonVariantConfig(bg: ColorsAmiin.terra, text: ColorsAmiin.white, border: ColorsAmiin.terra);
      case ButtonVariant.secondary:
        return _ButtonVariantConfig(bg: ColorsAmiin.terraLt, text: ColorsAmiin.terraDk, border: ColorsAmiin.terraLt);
      case ButtonVariant.ghost:
        return _ButtonVariantConfig(bg: Colors.transparent, text: ColorsAmiin.terra, border: ColorsAmiin.border);
      case ButtonVariant.danger:
        return _ButtonVariantConfig(bg: const Color(0xFFC0392B), text: ColorsAmiin.white, border: const Color(0xFFC0392B));
    }
  }

  _ButtonSizeConfig _getSizeConfig(ButtonSize s) {
    switch (s) {
      case ButtonSize.sm:
        return _ButtonSizeConfig(height: 36, px: Spacing.md, font: 13.0);
      case ButtonSize.md:
        return _ButtonSizeConfig(height: 48, px: Spacing.xl, font: 15.0);
      case ButtonSize.lg:
        return _ButtonSizeConfig(height: 56, px: Spacing.xxl, font: 16.0);
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