// ─── SearchBar ───────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';
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
        color: ColorsAmiin.white,
        borderRadius: BorderRadius.circular(RadiusAmiin.full),
        border: Border.all(color: ColorsAmiin.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          SvgPicture.string(
            _searchIconSvg,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(ColorsAmiin.muted, BlendMode.srcIn),
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
                  color: ColorsAmiin.muted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: FontSize.base,
                color: ColorsAmiin.ink,
              ),
            ),
          ),
          if (widget.value.isNotEmpty && widget.onClear != null)
            IconButton(
              icon: SvgPicture.string(
                _clearIconSvg,
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

  static const String _searchIconSvg = '''
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="8" cy="8" r="5.5" stroke="currentColor" stroke-width="1.6"/>
      <path d="M13 13l3 3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
    </svg>
  ''';

  static const String _clearIconSvg = '''
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="8" cy="8" r="7" fill="#DDD5C5"/>
      <path d="M5.5 5.5l5 5M10.5 5.5l-5 5" stroke="#6B5E4E" stroke-width="1.4" stroke-linecap="round"/>
    </svg>
  ''';
}