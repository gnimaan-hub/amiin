// ─── AmiinHeader ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
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
    final bgColor = dark ? ac.headerGradientEnd : ac.surface;
    final textColor = dark ? ac.onHeader : ac.ink;
    final subColor = dark
        ? ac.onHeader.withValues(alpha: 0.45)
        : ac.muted;

    final paddingTop = MediaQuery.of(context).padding.top;

    return Container(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: paddingTop + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: back
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: textColor,
                            ),
                            onPressed: onBack ?? () => Navigator.of(context).pop(),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: FontFamily.geo,
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            letterSpacing: -0.2,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 11,
                              color: subColor,
                            ),
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
          HorizonLine(
            color: mode == AmiinMode.neutral
                ? (dark ? ac.onHeader.withValues(alpha: 0.12) : ac.border)
                : mode.color,
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(72);
}
