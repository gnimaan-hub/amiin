// ─── Header ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class AmiinHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final bool back;
  final VoidCallback? onBack;
  final Widget? rightAction;
  final bool dark;

  const AmiinHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.back = false,
    this.onBack,
    this.rightAction,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = dark ? ColorsAmiin.ink : ColorsAmiin.white;
    final textColor = dark ? ColorsAmiin.onDark : ColorsAmiin.ink;
    final subColor = dark ? ColorsAmiin.onDark.withValues(alpha: 0.5) : ColorsAmiin.muted;
    final borderColor = dark ? ColorsAmiin.darkMid : ColorsAmiin.border;

    final paddingTop = MediaQuery.of(context).padding.top;

    return Container(
      color: bgColor,
      padding: EdgeInsets.only(top: paddingTop + 8, bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: back
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: SvgPicture.string(
                          _backArrowSvg,
                          colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                          width: 22,
                          height: 22,
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
                        fontFamily: FontFamily.serif,
                        fontSize: 18,
                        letterSpacing: 0.2,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
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
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);

  static const String _backArrowSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M14 5L8 11l6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ''';
}