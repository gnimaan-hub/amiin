// ─── SettingsPrivacyScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsPrivacyScreen extends StatelessWidget {
  const SettingsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Confidentialité & Données', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    const SettingsSection('Réponses d\'Amiin'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.fact_check_outlined,
                        label: 'Afficher les sources',
                        subtitle: 'Amiin cite ses références dans chaque réponse',
                        toggle: true,
                        toggleValue: settings.showSources,
                        onToggle: (v) => settingsService.showSources = v,
                      ),
                    ]),
                    AmiinCard(
                      variant: CardVariant.surface2,
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: ColorsAmiin.muted),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Cette option influe sur la longueur des réponses. Activez-la pour des démarches ou sujets juridiques.',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 12,
                                color: ColorsAmiin.muted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SettingsSection('Amélioration du service'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.bug_report_outlined,
                        label: 'Rapports d\'erreurs automatiques',
                        subtitle: 'Aucune donnée personnelle envoyée',
                        toggle: true,
                        toggleValue: settings.errorReporting,
                        onToggle: (v) => settingsService.errorReporting = v,
                      ),
                      SettingRow(
                        icon: Icons.insights_outlined,
                        label: 'Analytique d\'usage',
                        subtitle: 'Aide à améliorer l\'expérience Amiin',
                        toggle: true,
                        toggleValue: settings.analytics,
                        onToggle: (v) => settingsService.analytics = v,
                      ),
                    ]),

                    const SettingsSection('Historique des conversations'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.history_outlined,
                        label: 'Durée de conservation',
                        value: '90 jours',
                        onTap: () => _showRetentionPicker(context),
                      ),
                      SettingRow(
                        icon: Icons.download_outlined,
                        label: 'Exporter mes conversations',
                        subtitle: 'Fichier JSON',
                        onTap: () => _stub(context, 'Export disponible prochainement — nécessite une connexion'),
                      ),
                      SettingRow(
                        icon: Icons.delete_outline,
                        label: 'Effacer l\'historique',
                        destructive: true,
                        showChevron: false,
                        onTap: () => _confirmClear(
                          context,
                          'Effacer l\'historique',
                          'Toutes vos conversations seront supprimées définitivement.',
                        ),
                      ),
                    ]),

                    const SettingsSection('Mes données'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.folder_zip_outlined,
                        label: 'Télécharger mes données',
                        subtitle: 'Archive complète de votre compte',
                        onTap: () => _stub(context, 'Téléchargement disponible prochainement'),
                      ),
                      SettingRow(
                        icon: Icons.delete_forever_outlined,
                        label: 'Supprimer toutes mes données',
                        subtitle: 'Suppression locale et sur les serveurs Amiin',
                        destructive: true,
                        onTap: () => _confirmClear(
                          context,
                          'Supprimer toutes vos données',
                          'Cette action supprime définitivement toutes vos données locales et sur nos serveurs. Elle est irréversible.',
                        ),
                      ),
                    ]),

                    const SettingsSection('Documents légaux'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Politique de confidentialité',
                        onTap: () => _stub(context, 'Ouverture du navigateur'),
                      ),
                      SettingRow(
                        icon: Icons.gavel_outlined,
                        label: 'Conditions d\'utilisation',
                        onTap: () => _stub(context, 'Ouverture du navigateur'),
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

  void _stub(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _showRetentionPicker(BuildContext context) {
    const options = ['30 jours', '90 jours', '1 an', 'Indéfini'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((o) => ListTile(
                    title: Text(o),
                    onTap: () => Navigator.pop(ctx),
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Action effectuée')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
