// ─── SettingsTextScreen ── Taille, police et animations ──────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../theme/themes.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsTextScreen extends StatelessWidget {
  const SettingsTextScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final ac = context.ac;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Texte & accessibilité', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    // ── Taille du texte ───────────────────────────────────
                    const SettingsSection('Taille du texte'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('A', style: TextStyle(
                                fontSize: 12, color: ac.muted,
                                fontFamily: FontFamily.sans,
                              )),
                              Expanded(
                                child: Slider(
                                  value: settings.textScale,
                                  min: 0.8,
                                  max: 1.4,
                                  divisions: 6,
                                  onChanged: (v) =>
                                      settingsService.textScale = (v * 10).round() / 10,
                                ),
                              ),
                              Text('A', style: TextStyle(
                                fontSize: 22, color: ac.ink,
                                fontFamily: FontFamily.sans,
                              )),
                            ],
                          ),
                          Center(
                            child: Text(
                              _textScaleLabel(settings.textScale),
                              style: TextStyle(
                                fontFamily: FontFamily.geoMedium,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(Spacing.md),
                            decoration: BoxDecoration(
                              color: ac.background,
                              borderRadius: BorderRadius.circular(RadiusAmiin.md),
                            ),
                            child: Text(
                              'Aperçu : Amiin vous aide avec vos démarches administratives à Djibouti.',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 14,
                                color: ac.ink,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Police principale ─────────────────────────────────
                    const SettingsSection('Police principale'),
                    SettingCard(children: [
                      _FontOption(
                        label: 'DM Sans',
                        subtitle: 'Police par défaut d\'Amiin — moderne et lisible',
                        value: 'dmsans',
                        current: settings.font,
                        fontFamily: GoogleFonts.dmSans().fontFamily ?? 'DM Sans',
                      ),
                      _FontOption(
                        label: 'Open Sans',
                        subtitle: 'Espacement généreux — idéale pour l\'accessibilité',
                        value: 'opensans',
                        current: settings.font,
                        fontFamily: GoogleFonts.openSans().fontFamily ?? 'Open Sans',
                      ),
                      _FontOption(
                        label: 'Noto Sans',
                        subtitle: 'Multilingue — supporte l\'arabe et l\'afar',
                        value: 'noto',
                        current: settings.font,
                        fontFamily: GoogleFonts.notoSans().fontFamily ?? 'Noto Sans',
                      ),
                    ]),

                    // ── Animations ────────────────────────────────────────
                    const SettingsSection('Animations'),
                    SettingCard(children: [
                      _AnimOption(
                        label: 'Complètes',
                        subtitle: 'Transitions et effets visuels',
                        value: 'full',
                        current: settings.animations,
                      ),
                      _AnimOption(
                        label: 'Réduites',
                        subtitle: 'Moins de mouvements',
                        value: 'reduced',
                        current: settings.animations,
                      ),
                      _AnimOption(
                        label: 'Désactivées',
                        subtitle: 'Aucune animation (accessibilité)',
                        value: 'off',
                        current: settings.animations,
                      ),
                    ]),

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

  String _textScaleLabel(double v) {
    if (v <= 0.85) return 'Très petit';
    if (v <= 0.95) return 'Petit';
    if (v <= 1.05) return 'Normal';
    if (v <= 1.15) return 'Grand';
    if (v <= 1.25) return 'Très grand';
    return 'Très grand +';
  }
}

// ── Option police ─────────────────────────────────────────────────────────────

class _FontOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final String current;
  final String fontFamily;
  const _FontOption({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.current,
    required this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final primary = Theme.of(context).colorScheme.primary;
    final ac = context.ac;

    return InkWell(
      onTap: () => settingsService.font = value,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 16,
                    color: ac.ink,
                    fontWeight: FontWeight.w600,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 12,
                    color: ac.muted,
                  )),
                  const SizedBox(height: 4),
                  Text('Aa Bb Cc — 0 1 2 3', style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 13,
                    color: ac.muted,
                  )),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            if (selected)
              Icon(Icons.check_circle, color: primary, size: 22)
            else
              Icon(Icons.circle_outlined, color: ac.border, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Option animations ─────────────────────────────────────────────────────────

class _AnimOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final String current;
  const _AnimOption({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final primary = Theme.of(context).colorScheme.primary;
    final ac = context.ac;

    return InkWell(
      onTap: () => settingsService.animations = value,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 15,
                    color: ac.ink,
                  )),
                  Text(subtitle, style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 12,
                    color: ac.muted,
                  )),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: ac.border, size: 20),
          ],
        ),
      ),
    );
  }
}

