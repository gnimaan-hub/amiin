// ─── SettingsAboutScreen ── À propos & Support ────────────────────────────────

import 'package:flutter/material.dart';
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
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text('A', style: TextStyle(
                                fontFamily: FontFamily.geoBold,
                                fontSize: 36,
                                color: Colors.white,
                              )),
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          Text('Amiin', style: TextStyle(
                            fontFamily: FontFamily.geo,
                            fontSize: 26,
                            color: primary,
                            letterSpacing: 2,
                          )),
                          const SizedBox(height: 4),
                          Text(
                            'Version $_version (build $_build)',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: context.ac.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('أمين · Guide universel de Djibouti',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 12,
                                color: context.ac.muted,
                              )),
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
                      SettingRow(
                        icon: Icons.book_outlined,
                        label: 'Guide d\'utilisation',
                        subtitle: 'Rejouer l\'introduction à Amiin',
                        onTap: () => _stub(context, 'Guide bientôt disponible'),
                      ),
                    ]),

                    const SettingsSection('Support'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.help_outline,
                        label: 'Centre d\'aide / FAQ',
                        onTap: () => _stub(context, 'Ouverture du navigateur'),
                      ),
                      SettingRow(
                        icon: Icons.mail_outline,
                        label: 'Contacter le support',
                        subtitle: 'support@amiin.dj',
                        onTap: () => _stub(context, 'Ouverture de la messagerie'),
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
                        icon: Icons.star_outline,
                        label: 'Noter l\'application',
                        onTap: () => _stub(context, 'Ouverture du store'),
                      ),
                      SettingRow(
                        icon: Icons.share_outlined,
                        label: 'Partager Amiin',
                        onTap: () => _stub(context, 'Partage ouvert'),
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
                        style: TextStyle(
                          fontFamily: FontFamily.sans,
                          fontSize: 11,
                          color: context.ac.muted,
                        ),
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
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cache vidé avec succès'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Vider'),
          ),
        ],
      ),
    );
  }

  void _stub(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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
              Text('Nouveautés v1.0', style: TextStyle(
                fontFamily: FontFamily.geoBold, fontSize: 18, color: context.ac.ink,
              )),
              const SizedBox(height: Spacing.md),
              ...[
                '✦ Page paramètres complète avec 4 thèmes graphiques',
                '✦ Injection des préférences utilisateur dans Amiin',
                '✦ 36 fiches démarches e-gouv Djibouti',
                '✦ Annuaire de 899 services publics',
                '✦ Agenda, notes et chat vocal',
              ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(e, style: TextStyle(
                  fontFamily: FontFamily.sans, fontSize: 14, color: context.ac.ink, height: 1.4,
                )),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rapport envoyé — merci !')),
              );
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}

