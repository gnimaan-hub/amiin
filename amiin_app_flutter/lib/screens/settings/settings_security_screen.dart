// ─── SettingsSecurityScreen ───────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/toast.dart';
import 'settings_widgets.dart';

class SettingsSecurityScreen extends StatelessWidget {
  const SettingsSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ac.page,
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

                    const SettingsSection('Appareils connectés'),
                    const _DeviceSessions(),

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

/// Liste des sessions ouvertes (une par appareil) avec déconnexion à distance.
class _DeviceSessions extends StatefulWidget {
  const _DeviceSessions();

  @override
  State<_DeviceSessions> createState() => _DeviceSessionsState();
}

class _DeviceSessionsState extends State<_DeviceSessions> {
  List<DeviceSession>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await authService.listSessions();
      if (mounted) setState(() { _sessions = list; _error = null; });
    } on DioException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Liste des appareils indisponible.');
    }
  }

  Future<void> _revoke(DeviceSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter cet appareil ?'),
        content: Text(
          '« ${s.device} » sera déconnecté d\'ici une minute. Il faudra s\'y '
          'reconnecter avec votre mot de passe.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: context.ac.alertColor),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await authService.revokeSession(s.id);
      if (mounted) AmiinToast.show(context, 'Appareil déconnecté');
    } on DioException catch (e) {
      if (mounted) AmiinToast.show(context, authErrorMessage(e), success: false);
    }
    await _load();
  }

  String _when(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay
        ? "aujourd'hui à ${DateFormat('HH:mm').format(d)}"
        : 'le ${DateFormat('d MMM à HH:mm', 'fr_FR').format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    if (_error != null) {
      return SettingCard(children: [
        SettingRow(
          icon: Icons.devices_outlined,
          label: 'Appareils connectés',
          subtitle: _error,
          onTap: _load,
        ),
      ]);
    }
    if (sessions == null) {
      return const Padding(
        padding: EdgeInsets.all(Spacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingCard(children: [
          for (final s in sessions)
            SettingRow(
              icon: s.current ? Icons.smartphone : Icons.devices_other_outlined,
              label: s.current ? '${s.device} (cet appareil)' : s.device,
              subtitle: 'Actif ${_when(s.lastActiveAt)} · connecté ${_when(s.startedAt)}',
              destructive: false,
              onTap: s.current ? null : () => _revoke(s),
              value: s.current ? null : 'Déconnecter',
            ),
        ]),
        const SizedBox(height: Spacing.sm),
        Text(
          'Touchez un autre appareil pour le déconnecter. Pour tout fermer, '
          'y compris ici : Compte › Déconnecter tous mes appareils.',
          style: TextStyles.caption(context),
        ),
      ],
    );
  }
}
