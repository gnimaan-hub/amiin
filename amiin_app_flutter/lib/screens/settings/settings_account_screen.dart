// ─── SettingsAccountScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../services/auth_service.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsAccountScreen extends StatelessWidget {
  const SettingsAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final email = auth.currentUser?.email ?? '';
    final displayName = auth.currentUser?.displayName ?? '';

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Compte', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    const SettingsSection('Informations'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.email_outlined,
                        label: 'Adresse e-mail',
                        value: email,
                        onTap: () => _showComingSoon(context),
                      ),
                      SettingRow(
                        icon: Icons.badge_outlined,
                        label: 'Nom d\'utilisateur',
                        value: displayName,
                        onTap: () => _showComingSoon(context),
                      ),
                    ]),

                    const SettingsSection('Sécurité du compte'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.lock_reset_outlined,
                        label: 'Changer le mot de passe',
                        onTap: () => _showComingSoon(context),
                      ),
                    ]),

                    const SettingsSection('Zone de danger'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.logout,
                        label: 'Se déconnecter',
                        destructive: true,
                        showChevron: false,
                        onTap: () => _onLogout(context),
                      ),
                      SettingRow(
                        icon: Icons.delete_forever_outlined,
                        label: 'Supprimer le compte',
                        subtitle: 'Action irréversible',
                        destructive: true,
                        onTap: () => _showComingSoon(context),
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

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disponible après connexion au compte'),
        duration: Duration(seconds: 2),
      ),
    );
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
