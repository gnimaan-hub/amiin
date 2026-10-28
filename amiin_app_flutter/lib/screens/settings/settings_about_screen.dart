// ─── SettingsAboutScreen ── À propos & Support ────────────────────────────────

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/toast.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsAboutScreen extends StatelessWidget {
  const SettingsAboutScreen({super.key});

  static const _version = '1.0.0';
  static const _build = '1';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'À propos & Support', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    // ── Logo ──────────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                            ),
                            child: Center(
                              child: Text('A', style: TextStyles.displayTitle(context).copyWith(fontSize: 36, color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          Text('Amiin', style: TextStyles.cardTitle(context).copyWith(fontSize: FontSize.xxl, color: primary, letterSpacing: 2, fontFamily: FontFamily.geo)),
                          const SizedBox(height: 4),
                          Text(
                            'Version $_version (build $_build)',
                            style: TextStyles.bodyMuted(context).copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text('أمين · Guide universel de Djibouti',
                              style: TextStyles.caption(context)),
                        ],
                      ),
                    ),

                    const SettingsSection('Application'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.new_releases_outlined,
                        label: 'Nouveautés',
                        subtitle: 'Voir les dernières mises à jour',
                        onTap: () => _showChangelog(context),
                      ),
                    ]),

                    const SettingsSection('Support'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.mail_outline,
                        label: 'Contacter le support',
                        subtitle: 'support@amiin.dj',
                        onTap: () => _mailSupport(context, 'Amiin — demande de support', ''),
                      ),
                      SettingRow(
                        icon: Icons.flag_outlined,
                        label: 'Signaler un problème',
                        onTap: () => _showReportDialog(context),
                      ),
                    ]),

                    const SettingsSection('Communauté'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.share_outlined,
                        label: 'Partager Amiin',
                        onTap: () => Share.share(
                          'Je te recommande Amiin, l\'assistant qui répond à tes questions '
                          'sur les démarches et les lois à Djibouti.',
                          subject: 'Amiin',
                        ),
                      ),
                    ]),

                    const SettingsSection('Mentions légales'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.code_outlined,
                        label: 'Licences open source',
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'Amiin',
                          applicationVersion: _version,
                        ),
                      ),
                    ]),

                    const SettingsSection('Avancé'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.cleaning_services_outlined,
                        label: 'Vider le cache',
                        subtitle: 'Libère l\'espace de stockage temporaire',
                        showChevron: false,
                        onTap: () => _confirmClearCache(context),
                      ),
                    ]),

                    const SizedBox(height: Spacing.xxxl),

                    Center(
                      child: Text(
                        '© 2026 Amiin · Fait avec ❤ à Djibouti',
                        style: TextStyles.caption(context).copyWith(fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider le cache'),
        content: const Text('Les données temporaires seront supprimées. L\'application peut être plus lente lors du prochain démarrage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final tmp = await getTemporaryDirectory();
              if (await tmp.exists()) {
                for (final entry in tmp.listSync()) {
                  try {
                    entry.deleteSync(recursive: true);
                  } catch (_) {}   // fichier en cours d'utilisation : ignoré
                }
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cache vidé'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Vider'),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'application de messagerie vers le support, sujet et corps
  /// pré-remplis (pas d'envoi côté serveur).
  Future<void> _mailSupport(BuildContext context, String subject, String body) async {
    final uri = Uri.parse('mailto:support@amiin.dj'
        '?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
    if (!await launchUrl(uri) && context.mounted) {
      AmiinToast.show(context, 'Aucune application de messagerie — écrivez à support@amiin.dj');
    }
  }

  void _showChangelog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nouveautés v1.0', style: TextStyles.screenTitle(context)),
              const SizedBox(height: Spacing.md),
              ...[
                '✦ Page paramètres complète avec 4 thèmes graphiques',
                '✦ Injection des préférences utilisateur dans Amiin',
                '✦ 36 fiches démarches e-gouv Djibouti',
                '✦ Annuaire de 899 services publics',
                '✦ Agenda, notes et chat vocal',
              ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(e, style: TextStyles.body(context).copyWith(height: 1.4)),
              )),
              const SizedBox(height: Spacing.md),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler un problème'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Décrivez le problème rencontré…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mailSupport(context, 'Amiin — signalement ($_version)', ctrl.text);
            },
            child: const Text('Envoyer par e-mail'),
          ),
        ],
      ),
    );
  }
}

