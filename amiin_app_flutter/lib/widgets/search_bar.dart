// ─── SearchBar ───────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../widgets/amiin_svg_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/themes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

class AmiinSearchBar extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hintText;
  final VoidCallback? onClear;

  const AmiinSearchBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Rechercher…',
    this.onClear,
  });

  @override
  State<AmiinSearchBar> createState() => _AmiinSearchBarState();
}

class _AmiinSearchBarState extends State<AmiinSearchBar> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _controller.addListener(() {
      if (_controller.text != widget.value) {
        widget.onChanged(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(AmiinSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.ac.surface,
        borderRadius: BorderRadius.circular(RadiusAmiin.full),
        border: Border.all(color: context.ac.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          SvgPicture.string(
            AmiinSvgIcons.searchIcon,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(context.ac.muted, BlendMode.srcIn),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontFamily: FontFamily.sans,
                  fontSize: FontSize.base,
                  color: context.ac.muted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: FontSize.base,
                color: context.ac.ink,
              ),
            ),
          ),
          if (widget.value.isNotEmpty && widget.onClear != null)
            IconButton(
              icon: SvgPicture.string(
                AmiinSvgIcons.clearIcon,
                width: 16,
                height: 16,
              ),
              onPressed: () {
                _controller.clear();
                widget.onChanged('');
                if (widget.onClear != null) widget.onClear!();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

}