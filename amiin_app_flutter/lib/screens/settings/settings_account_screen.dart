// ─── SettingsAccountScreen ────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../services/auth_service.dart';
import '../../services/chat_controller.dart';
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
                      ),
                      SettingRow(
                        icon: Icons.badge_outlined,
                        label: 'Nom d\'utilisateur',
                        value: displayName,
                        onTap: () => _formDialog(
                          context,
                          title: 'Nom d\'utilisateur',
                          fields: [('Nom', false, displayName)],
                          submitLabel: 'Enregistrer',
                          successMessage: 'Nom mis à jour',
                          validate: (v) => v[0].trim().isEmpty ? 'Le nom ne peut pas être vide.' : null,
                          submit: (v) => authService.updateDisplayName(v[0].trim()),
                        ),
                      ),
                    ]),

                    const SettingsSection('Sécurité du compte'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.lock_reset_outlined,
                        label: 'Changer le mot de passe',
                        onTap: () => _formDialog(
                          context,
                          title: 'Changer le mot de passe',
                          fields: const [
                            ('Mot de passe actuel', true, ''),
                            ('Nouveau mot de passe (8 caractères min.)', true, ''),
                            ('Confirmer le nouveau mot de passe', true, ''),
                          ],
                          submitLabel: 'Modifier',
                          successMessage: 'Mot de passe modifié — vos autres appareils sont déconnectés',
                          validate: (v) {
                            if (v[1].length < 8) return 'Au moins 8 caractères.';
                            if (v[1] != v[2]) return 'Les mots de passe ne correspondent pas.';
                            return null;
                          },
                          submit: (v) => authService.changePassword(
                            currentPassword: v[0],
                            newPassword: v[1],
                          ),
                        ),
                      ),
                      SettingRow(
                        icon: Icons.devices_outlined,
                        label: 'Déconnecter tous mes appareils',
                        showChevron: false,
                        onTap: () => _onLogoutAll(context),
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
                        onTap: () => _onDeleteAccount(context),
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

  /// Petit formulaire en dialogue : champs (libellé, masqué, valeur initiale),
  /// validation locale, puis appel serveur ; les erreurs serveur s'affichent
  /// sous les champs.
  void _formDialog(
    BuildContext context, {
    required String title,
    required List<(String, bool, String)> fields,
    required String submitLabel,
    required String successMessage,
    required String? Function(List<String>) validate,
    required Future<void> Function(List<String>) submit,
  }) {
    final ctrls = [for (final f in fields) TextEditingController(text: f.$3)];
    final messenger = ScaffoldMessenger.of(context);
    String? error;
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fields.length; i++)
                TextField(
                  controller: ctrls[i],
                  obscureText: fields[i].$2,
                  enabled: !busy,
                  decoration: InputDecoration(labelText: fields[i].$1),
                ),
              if (error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final values = [for (final c in ctrls) c.text];
                      final invalid = validate(values);
                      if (invalid != null) {
                        setState(() => error = invalid);
                        return;
                      }
                      setState(() { busy = true; error = null; });
                      try {
                        await submit(values);
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
                      } on DioException catch (e) {
                        setState(() { busy = false; error = authErrorMessage(e); });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(submitLabel),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      for (final c in ctrls) {
        c.dispose();
      }
    });
  }

  void _onLogoutAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter tous mes appareils'),
        content: const Text(
          'Toutes vos sessions, y compris celle-ci, seront fermées. '
          'Vous devrez vous reconnecter sur chaque appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              authService.logoutAll();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Tout déconnecter'),
          ),
        ],
      ),
    );
  }

  void _onDeleteAccount(BuildContext context) {
    final chat = context.read<ChatController>();
    final passCtrl = TextEditingController();
    String? error;
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Supprimer le compte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Votre compte et vos données sur les serveurs Amiin seront '
                'supprimés définitivement, ainsi que les conversations, notes, '
                'agenda et démarches enregistrés sur cet appareil.',
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: passCtrl,
                obscureText: true,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (passCtrl.text.isEmpty) {
                        setState(() => error = 'Mot de passe requis');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await authService.deleteAccount(password: passCtrl.text);
                        chat.clearConversation();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on DioException catch (e) {
                        setState(() {
                          busy = false;
                          error = authErrorMessage(e);
                        });
                      }
                    },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Supprimer'),
            ),
          ],
        ),
      ),
    ).whenComplete(passCtrl.dispose);
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
