// ─── Widgets partagés entre tous les écrans Settings ─────────────────────────

import 'package:flutter/material.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/grouped_list.dart';

// ── Section label ─────────────────────────────────────────────────────────────

class SettingsSection extends StatelessWidget {
  final String title;
  const SettingsSection(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.xs, top: Spacing.xl, bottom: Spacing.sm),
      child: Text(
        title.toUpperCase(),
        style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: context.ac.muted, letterSpacing: 1.2, fontFamily: FontFamily.geoBold),
      ),
    );
  }
}

// ── Ligne de réglage ─────────────────────────────────────────────────────────

class SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final bool toggle;
  final bool toggleValue;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.toggle = false,
    this.toggleValue = false,
    this.onToggle,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final labelColor = destructive ? context.ac.alertColor : context.ac.ink;

    return InkWell(
      onTap: toggle ? null : onTap,
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: 13,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: destructive
                    ? context.ac.alertColor.withValues(alpha: 0.10)
                    : primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 17,
                color: destructive ? context.ac.alertColor : primary,
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyles.body(context).copyWith(fontSize: 15, color: labelColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyles.caption(context),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyles.bodyMuted(context).copyWith(fontSize: 13),
              ),
            if (toggle)
              Switch(
                value: toggleValue,
                onChanged: onToggle,
                activeThumbColor: primary,
              )
            else if (onTap != null && showChevron)
              Icon(Icons.chevron_right_rounded, color: context.ac.muted.withValues(alpha: 0.6), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Divider entre rows ────────────────────────────────────────────────────────

class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(color: context.ac.border.withValues(alpha: 0.7), height: 0.5, thickness: 0.5, indent: 60);
}

// ── Card groupant des rows ────────────────────────────────────────────────────

class SettingCard extends StatelessWidget {
  final List<Widget> children;
  const SettingCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    // Liste groupée « vitrine » : une carte flottante, filets alignés sur
    // le texte (16 de marge + 32 d'icône + 12 d'espace).
    return GroupedList(dividerIndent: 60, children: children);
  }
}

// ── Sélecteur de choix (tone / longueur / expertise) ─────────────────────────

class ChoiceSelector extends StatelessWidget {
  final List<String> options;
  final List<String> labels;
  final String current;
  final ValueChanged<String> onSelect;

  const ChoiceSelector({
    super.key,
    required this.options,
    required this.labels,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: List.generate(options.length, (i) {
        final selected = options[i] == current;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(options[i]),
            child: Container(
              margin: EdgeInsets.only(right: i < options.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? primary : context.ac.surface,
                borderRadius: BorderRadius.circular(RadiusAmiin.full),
                border: selected ? null : Border.all(color: context.ac.border.withValues(alpha: 0.7)),
                boxShadow: selected
                    ? [BoxShadow(color: primary.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4), spreadRadius: -4)]
                    : null,
              ),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: selected ? Colors.white : context.ac.midTone),
              ),
            ),
          ),
        );
      }),
    );
  }
}

