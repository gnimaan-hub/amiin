// ─── SettingsSecurityScreen ───────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsSecurityScreen extends StatelessWidget {
  const SettingsSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Sécurité', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    const SettingsSection('Protection des données'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.enhanced_encryption_outlined,
                        label: 'Chiffrement sur l\'appareil',
                        subtitle: 'Conversations, notes, agenda et démarches chiffrés '
                            '(AES-256, clé dans le stockage sécurisé du téléphone)',
                        value: 'Actif',
                      ),
                      SettingRow(
                        icon: Icons.lock_outline,
                        label: 'Connexion au serveur',
                        subtitle: 'Échanges chiffrés (HTTPS), session renouvelée '
                            'automatiquement',
                      ),
                    ]),

                    const SettingsSection('Autorisations système'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.tune_outlined,
                        label: 'Gérer les autorisations',
                        subtitle: 'Localisation, microphone, notifications',
                        onTap: () => Geolocator.openAppSettings(),
                      ),
                    ]),

                    const SettingsSection('Sessions'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.devices_outlined,
                        label: 'Appareils connectés',
                        subtitle: 'Pour fermer toutes vos sessions : '
                            'Compte › Déconnecter tous mes appareils',
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
