// ─── SettingsScreen ── Page principale des paramètres ────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final auth = context.watch<AuthService>();
    final authName = auth.currentUser?.displayName ?? '';
    final displayName = authName.isNotEmpty ? authName : settings.displayName;
    final initials = _initials(displayName);

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(title: 'Paramètres', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.lg),

                    // ── Carte utilisateur ─────────────────────────────────
                    _UserCard(
                      name: displayName.isNotEmpty ? displayName : 'Mon profil',
                      initials: initials,
                      onTap: () => context.push('/settings/profile'),
                    ),

                    // ── Compte & Sécurité ─────────────────────────────────
                    const SettingsSection('Compte & Sécurité'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Compte',
                        subtitle: 'Email, nom d\'utilisateur',
                        onTap: () => context.push('/settings/account'),
                      ),
                      SettingRow(
                        icon: Icons.shield_outlined,
                        label: 'Sécurité',
                        subtitle: 'Accès, verrouillage, autorisations',
                        onTap: () => context.push('/settings/security'),
                      ),
                    ]),

                    // ── Amiin ─────────────────────────────────────────────
                    const SettingsSection('Amiin'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.psychology_outlined,
                        label: 'Comportement d\'Amiin',
                        subtitle: 'Ton, longueur, expertise, mémoire',
                        onTap: () => context.push('/settings/assistant'),
                      ),
                      SettingRow(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        subtitle: 'Rappels, conseils, ne pas déranger',
                        onTap: () => context.push('/settings/notifications'),
                      ),
                    ]),

                    // ── Apparence ─────────────────────────────────────────
                    const SettingsSection('Apparence'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.palette_outlined,
                        label: 'Thème & couleurs',
                        value: _themeLabel(settings.themeVariant),
                        onTap: () => context.push('/settings/appearance'),
                      ),
                      SettingRow(
                        icon: Icons.text_fields_outlined,
                        label: 'Texte & accessibilité',
                        subtitle: 'Taille, police, animations',
                        onTap: () => context.push('/settings/text'),
                      ),
                    ]),

                    // ── Préférences ───────────────────────────────────────
                    const SettingsSection('Préférences'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.language_outlined,
                        label: 'Langue & région',
                        value: settings.language == 'fr' ? 'Français' : 'English',
                        onTap: () => context.push('/settings/language'),
                      ),
                      SettingRow(
                        icon: Icons.lock_outline,
                        label: 'Confidentialité & données',
                        onTap: () => context.push('/settings/privacy'),
                      ),
                    ]),

                    // ── Abonnement ────────────────────────────────────────
                    const SettingsSection('Abonnement'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.credit_card_outlined,
                        label: 'Facturation',
                        subtitle: 'Plan actuel, historique',
                        onTap: () => context.push('/settings/billing'),
                      ),
                    ]),

                    // ── Support ───────────────────────────────────────────
                    const SettingsSection('Support'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.info_outline,
                        label: 'À propos & support',
                        subtitle: 'Version, aide, contact',
                        onTap: () => context.push('/settings/about'),
                      ),
                    ]),

                    const SizedBox(height: Spacing.lg),

                    // ── Déconnexion ───────────────────────────────────────
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.logout,
                        label: 'Se déconnecter',
                        destructive: true,
                        showChevron: false,
                        onTap: () => _onLogout(context),
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'A';
    final f = parts[0][0].toUpperCase();
    final l = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0].toUpperCase() : '';
    return '$f$l';
  }

  String _themeLabel(String v) {
    switch (v) {
      case 'ocean':
        return 'Océan';
      case 'foret':
        return 'Forêt';
      case 'nuit':
        return 'Nuit';
      default:
        return 'Terre';
    }
  }

  void _onLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              authService.logout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String name;
  final String initials;
  final VoidCallback onTap;
  const _UserCard({required this.name, required this.initials, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: ColorsAmiin.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColorsAmiin.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: primary,
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: FontFamily.geoBold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(
                    fontFamily: FontFamily.geoBold,
                    fontSize: 16,
                    color: ColorsAmiin.ink,
                  )),
                  const SizedBox(height: 2),
                  Text('Modifier mon profil', style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 13,
                    color: primary,
                  )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: ColorsAmiin.muted, size: 18),
          ],
        ),
      ),
    );
  }
}


