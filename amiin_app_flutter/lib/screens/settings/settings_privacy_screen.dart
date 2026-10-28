// ─── SettingsPrivacyScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../widgets/toast.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/chat_controller.dart';
import '../../services/export_service.dart';
import '../../services/hive_utils.dart';
import '../../services/memory_service.dart';
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
      backgroundColor: context.ac.background,
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
                          Icon(Icons.info_outline, size: 16, color: context.ac.muted),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Cette option influe sur la longueur des réponses. Activez-la pour des démarches ou sujets juridiques.',
                              style: TextStyles.caption(context).copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SettingsSection('Historique des conversations'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.history_outlined,
                        label: 'Conservation',
                        value: '${MemoryService.maxStoredMessages} derniers messages',
                        subtitle: 'Sur cet appareil uniquement',
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
                          () async => context.read<ChatController>().clearConversation(),
                        ),
                      ),
                    ]),

                    const SettingsSection('Mes données'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.download_outlined,
                        label: 'Exporter mes données',
                        subtitle: 'Conversations, notes, agenda, démarches — fichier JSON',
                        onTap: () => _export(context),
                      ),
                      SettingRow(
                        icon: Icons.delete_forever_outlined,
                        label: 'Supprimer toutes mes données',
                        subtitle: 'Sur cet appareil — le compte se supprime dans Compte',
                        destructive: true,
                        onTap: () => _confirmClear(
                          context,
                          'Supprimer toutes vos données',
                          'Conversations, notes, agenda, démarches suivies, profil et préférences '
                          'enregistrés sur cet appareil seront supprimés définitivement. '
                          'Pour supprimer aussi votre compte sur nos serveurs, utilisez '
                          'Paramètres › Compte › Supprimer le compte.',
                          () async {
                            final chat = context.read<ChatController>();
                            await wipeLocalUserData();
                            chat.clearConversation();
                          },
                        ),
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

  Future<void> _export(BuildContext context) async {
    try {
      await exportService.exportAndShare();
    } catch (e) {
      if (context.mounted) AmiinToast.show(context, 'Export impossible : $e');
    }
  }

  void _confirmClear(BuildContext context, String title, String message,
      Future<void> Function() action) {
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
            onPressed: () async {
              Navigator.pop(ctx);
              await action();
              if (context.mounted) AmiinToast.show(context, 'Données supprimées');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
