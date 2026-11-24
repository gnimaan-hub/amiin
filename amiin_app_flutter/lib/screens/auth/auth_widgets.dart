// ─── Widgets partagés entre LoginScreen et RegisterScreen ────────────────────

import 'package:flutter/material.dart';
import '../../theme/spacing.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';

class AuthDarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const AuthDarkField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(RadiusAmiin.lg);
    final baseBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: ColorsAmiin.onDark.withValues(alpha: 0.15)),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: ColorsAmiin.turquoiseMid, width: 1.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: ColorsAmiin.corail),
    );

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: TextStyle(
        fontFamily: FontFamily.sans,
        fontSize: 15,
        color: ColorsAmiin.onDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          fontFamily: FontFamily.sans,
          fontSize: 13,
          color: ColorsAmiin.onDark.withValues(alpha: 0.5),
        ),
        hintStyle: TextStyle(
          fontFamily: FontFamily.sans,
          fontSize: 14,
          color: ColorsAmiin.onDark.withValues(alpha: 0.25),
        ),
        filled: true,
        fillColor: ColorsAmiin.onDark.withValues(alpha: 0.06),
        border: baseBorder,
        enabledBorder: baseBorder,
        focusedBorder: focusBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder,
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        suffixIcon: suffixIcon,
        errorStyle: TextStyle(
          fontFamily: FontFamily.sans,
          fontSize: 11,
          color: ColorsAmiin.corail,
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Pilule flottante : ombre turquoise diffuse sous le bouton.
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RadiusAmiin.full),
        boxShadow: [
          BoxShadow(
            color: ColorsAmiin.turquoise.withValues(alpha: loading ? 0.0 : 0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorsAmiin.turquoise,
          foregroundColor: ColorsAmiin.onTurquoise,
          disabledBackgroundColor: ColorsAmiin.turquoise.withValues(alpha: 0.5),
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColorsAmiin.onTurquoise,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: FontFamily.geoMedium,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ColorsAmiin.corail.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(RadiusAmiin.md),
        border: Border.all(color: ColorsAmiin.corail.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: ColorsAmiin.corail),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: 13,
                color: ColorsAmiin.corailLt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: ColorsAmiin.onDark.withValues(alpha: 0.12),
            thickness: 0.5,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ou',
            style: TextStyle(
              fontFamily: FontFamily.sans,
              fontSize: 12,
              color: ColorsAmiin.onDark.withValues(alpha: 0.35),
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: ColorsAmiin.onDark.withValues(alpha: 0.12),
            thickness: 0.5,
          ),
        ),
      ],
    );
  }
}

/// Fond des écrans d'authentification : encre de nuit avec les deux halos
/// diffus de l'accueil (turquoise en haut à droite, ocre en bas à gauche).
class AuthBackdrop extends StatelessWidget {
  final Widget child;
  const AuthBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget glow(Color color, double size, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ]),
          ),
        );
    // expand : le fond couvre tout l'écran, pas seulement le formulaire.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ColorsAmiin.encreNuit, Color(0xFF1C2E52)],
              ),
            ),
          ),
        ),
        Positioned(top: -140, right: -120, child: glow(ColorsAmiin.turquoise, 380, 0.28)),
        Positioned(bottom: -160, left: -140, child: glow(ColorsAmiin.ocre, 360, 0.12)),
        child,
      ],
    );
  }
}
