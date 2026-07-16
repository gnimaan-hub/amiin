// ─── SettingsLanguageScreen ───────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsLanguageScreen extends StatelessWidget {
  const SettingsLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Langue & Région', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    const SettingsSection("Langue de l'interface"),
                    AmiinCard(
                      child: Column(
                        children: [
                          _LangOption(
                            flag: '🇫🇷',
                            label: 'Français',
                            value: 'fr',
                            current: settings.language,
                            onTap: () => settingsService.language = 'fr',
                          ),
                          Divider(color: context.ac.border, height: 1, indent: 56),
                          _LangOption(
                            flag: '🇬🇧',
                            label: 'English',
                            value: 'en',
                            current: settings.language,
                            onTap: () => settingsService.language = 'en',
                          ),
                        ],
                      ),
                    ),

                    const SettingsSection("Langue des réponses d'Amiin"),
                    AmiinCard(
                      child: Column(
                        children: [
                          _LangOption(
                            flag: '🇫🇷',
                            label: 'Français',
                            value: 'fr',
                            current: settings.aiLanguage,
                            onTap: () => settingsService.aiLanguage = 'fr',
                          ),
                          Divider(color: context.ac.border, height: 1, indent: 56),
                          _LangOption(
                            flag: '🇬🇧',
                            label: 'English',
                            value: 'en',
                            current: settings.aiLanguage,
                            onTap: () => settingsService.aiLanguage = 'en',
                          ),
                          Divider(color: context.ac.border, height: 1, indent: 56),
                          _LangOption(
                            flag: '🇸🇦',
                            label: 'العربية',
                            value: 'ar',
                            current: settings.aiLanguage,
                            onTap: () => settingsService.aiLanguage = 'ar',
                          ),
                          Divider(color: context.ac.border, height: 1, indent: 56),
                          _LangOption(
                            flag: '🇩🇯',
                            label: 'Soomaali',
                            value: 'so',
                            current: settings.aiLanguage,
                            onTap: () => settingsService.aiLanguage = 'so',
                          ),
                        ],
                      ),
                    ),

                    const SettingsSection('Devise'),
                    SettingCard(children: [
                      _CurrencyOption(
                        label: 'Franc Djiboutien',
                        symbol: '₣',
                        code: 'DJF',
                        current: settings.currency,
                        onTap: () => settingsService.currency = 'DJF',
                      ),
                      _CurrencyOption(
                        label: 'Euro',
                        symbol: '€',
                        code: 'EUR',
                        current: settings.currency,
                        onTap: () => settingsService.currency = 'EUR',
                      ),
                      _CurrencyOption(
                        label: 'Dollar américain',
                        symbol: '\$',
                        code: 'USD',
                        current: settings.currency,
                        onTap: () => settingsService.currency = 'USD',
                      ),
                    ]),

                    const SettingsSection('Format de date'),
                    SettingCard(children: [
                      _FormatOption(
                        label: 'JJ/MM/AAAA',
                        subtitle: 'Ex : 16/06/2026',
                        value: 'dmy',
                        current: settings.dateFormat,
                        onTap: () => settingsService.dateFormat = 'dmy',
                      ),
                      _FormatOption(
                        label: 'MM/DD/YYYY',
                        subtitle: 'Ex : 06/16/2026',
                        value: 'mdy',
                        current: settings.dateFormat,
                        onTap: () => settingsService.dateFormat = 'mdy',
                      ),
                    ]),

                    const SettingsSection('Format d\'heure'),
                    SettingCard(children: [
                      _FormatOption(
                        label: '24 heures',
                        subtitle: 'Ex : 14:30',
                        value: '24h',
                        current: settings.timeFormat,
                        onTap: () => settingsService.timeFormat = '24h',
                      ),
                      _FormatOption(
                        label: '12 heures (AM/PM)',
                        subtitle: 'Ex : 2:30 PM',
                        value: '12h',
                        current: settings.timeFormat,
                        onTap: () => settingsService.timeFormat = '12h',
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
}

class _LangOption extends StatelessWidget {
  final String flag;
  final String label;
  final String value;
  final String current;
  final VoidCallback onTap;
  const _LangOption({required this.flag, required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(label, style: TextStyles.body(context).copyWith(fontSize: 15)),
            ),
            if (selected)
              Icon(Icons.check_circle, color: primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: context.ac.border, size: 20),
          ],
        ),
      ),
    );
  }
}

class _CurrencyOption extends StatelessWidget {
  final String label;
  final String symbol;
  final String code;
  final String current;
  final VoidCallback onTap;
  const _CurrencyOption({required this.label, required this.symbol, required this.code, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = code == current;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? primary.withValues(alpha: 0.1) : context.ac.background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(symbol, style: TextStyles.screenTitle(context).copyWith(fontSize: 16, color: selected ? primary : context.ac.midTone)),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyles.body(context).copyWith(fontSize: 15)),
                  Text(code, style: TextStyles.caption(context).copyWith(fontSize: 11)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: context.ac.border, size: 20),
          ],
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final String current;
  final VoidCallback onTap;
  const _FormatOption({required this.label, required this.subtitle, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyles.body(context).copyWith(fontSize: 15)),
                  Text(subtitle, style: TextStyles.caption(context)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: context.ac.border, size: 20),
          ],
        ),
      ),
    );
  }
}
