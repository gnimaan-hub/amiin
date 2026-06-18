// ─── SettingsSecurityScreen ───────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsSecurityScreen extends StatelessWidget {
  const SettingsSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
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

                    const SettingsSection('Déverrouillage'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.fingerprint,
                        label: 'Biométrie',
                        subtitle: 'Face ID ou empreinte digitale',
                        toggle: true,
                        toggleValue: false,
                        onToggle: (_) => _stub(context),
                      ),
                      SettingRow(
                        icon: Icons.pin_outlined,
                        label: 'Code PIN',
                        subtitle: 'Alternative à la biométrie',
                        onTap: () => _stub(context),
                      ),
                      SettingRow(
                        icon: Icons.lock_clock_outlined,
                        label: 'Verrouillage automatique',
                        value: 'Après 5 min',
                        onTap: () => _showAutoLockPicker(context),
                      ),
                    ]),

                    const SettingsSection('Confidentialité d\'affichage'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.visibility_off_outlined,
                        label: 'Masquer les infos sensibles',
                        subtitle: 'Les données perso apparaissent masquées en aperçu',
                        toggle: true,
                        toggleValue: false,
                        onToggle: (_) => _stub(context),
                      ),
                    ]),

                    const SettingsSection('Autorisations système'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.location_on_outlined,
                        label: 'Localisation',
                        subtitle: 'Pour les services à proximité',
                        value: 'En utilisation',
                        onTap: () => _stub(context),
                      ),
                      SettingRow(
                        icon: Icons.mic_outlined,
                        label: 'Microphone',
                        subtitle: 'Pour la dictée vocale',
                        value: 'Autorisé',
                        onTap: () => _stub(context),
                      ),
                      SettingRow(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        subtitle: 'Gérer dans les paramètres système',
                        onTap: () => _stub(context),
                      ),
                    ]),

                    const SettingsSection('Historique de connexion'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.history_outlined,
                        label: 'Dernières sessions',
                        subtitle: 'Appareils et connexions récentes',
                        onTap: () => _stub(context),
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

  void _stub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fonctionnalité à venir'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAutoLockPicker(BuildContext context) {
    const options = ['Jamais', 'Après 1 min', 'Après 5 min', 'Après 15 min'];
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
}
