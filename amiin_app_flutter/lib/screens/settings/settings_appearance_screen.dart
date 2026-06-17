// ─── SettingsAppearanceScreen ── Thème graphique uniquement ──────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../theme/themes.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Thème & couleurs', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),
                    const SettingsSection('Thème graphique'),
                    Text(
                      'Le thème s\'applique immédiatement sur toute l\'application.',
                      style: TextStyle(
                        fontFamily: FontFamily.sans,
                        fontSize: 13,
                        color: context.ac.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    _ThemePicker(current: settings.themeVariant),
                    const SizedBox(height: Spacing.xxxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sélecteur de thème (4 cards visuelles) ───────────────────────────────────

class _ThemePicker extends StatelessWidget {
  final String current;
  const _ThemePicker({required this.current});

  @override
  Widget build(BuildContext context) {
    final variants = AmiinThemeVariant.values;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Spacing.sm,
      mainAxisSpacing: Spacing.sm,
      childAspectRatio: 1.5,
      children: variants.map((v) {
        final c = v.colors;
        final selected = v.id == current;
        return GestureDetector(
          onTap: () => settingsService.themeVariant = v.id,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.headerGradientStart, c.headerGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? c.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Stack(
              children: [
                // Mini aperçu du fond de l'app
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 40,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 24, height: 3, decoration: BoxDecoration(
                          color: c.primary, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 3),
                        Container(width: 20, height: 2, decoration: BoxDecoration(
                          color: c.muted, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 2),
                        Container(width: 20, height: 2, decoration: BoxDecoration(
                          color: c.muted, borderRadius: BorderRadius.circular(2))),
                      ],
                    ),
                  ),
                ),
                // Label
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 5,
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(v.label, style: TextStyle(
                        fontFamily: FontFamily.geoBold,
                        fontSize: 12,
                        color: c.onHeader,
                      )),
                    ],
                  ),
                ),
                // Coche sélection
                if (selected)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

