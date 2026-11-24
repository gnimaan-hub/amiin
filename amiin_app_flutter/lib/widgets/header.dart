// ─── AmiinHeader ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/elevation.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../theme/themes.dart';
import 'horizon_line.dart';

class AmiinHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final bool back;
  final VoidCallback? onBack;
  final Widget? rightAction;
  final bool dark;
  final AmiinMode mode;

  const AmiinHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.back = false,
    this.onBack,
    this.rightAction,
    this.dark = false,
    this.mode = AmiinMode.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    // Style « vitrine » : l'en-tête clair se fond dans le fond de page ;
    // la variante sombre garde le bandeau encre de nuit.
    final bgColor = dark ? ac.headerGradientEnd : ac.page;
    final textColor = dark ? ac.onHeader : ac.ink;
    final subColor = dark
        ? ac.onHeader.withValues(alpha: 0.55)
        : ac.muted;

    final paddingTop = MediaQuery.of(context).padding.top;

    return Container(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: paddingTop + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: back
                        ? _RoundButton(
                            dark: dark,
                            semanticLabel: 'Retour',
                            onTap: onBack ?? () => Navigator.of(context).pop(),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: textColor,
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyles.cardTitle(context).copyWith(fontSize: 17, color: textColor, fontWeight: FontWeight.w600, letterSpacing: -0.3, fontFamily: FontFamily.geo),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            style: TextStyles.body(context).copyWith(fontSize: 11, color: subColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: rightAction ?? const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Ligne d'horizon conservée pour les écrans en mode secrétariat /
          // information ; en mode neutre, un simple filet très léger.
          if (mode == AmiinMode.neutral)
            Container(
              height: 0.5,
              color: dark
                  ? ac.onHeader.withValues(alpha: 0.10)
                  : ac.border.withValues(alpha: 0.6),
            )
          else
            HorizonLine(color: mode.color(context), height: 1.5),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(72);
}

/// Bouton rond de l'en-tête : surface flottante (clair) ou verre (sombre).
class _RoundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool dark;
  final String semanticLabel;

  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.dark,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? glass(context, 0.10) : ac.surface,
          border: dark
              ? Border.all(color: glass(context, 0.16))
              : hairline(context),
          boxShadow: dark ? null : floatShadow(context, lift: 0.15),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
