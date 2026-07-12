// ─── SettingsNotificationsScreen ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsNotificationsScreen extends StatelessWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final enabled = settings.notifMaster;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Notifications', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    // ── Maître ────────────────────────────────────────────
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.notifications_active_outlined,
                        label: 'Activer les notifications',
                        subtitle: 'Contrôle général de toutes les alertes',
                        toggle: true,
                        toggleValue: enabled,
                        onToggle: (v) => settingsService.notifMaster = v,
                      ),
                    ]),

                    // ── Rappels & Agenda ──────────────────────────────────
                    const SettingsSection('Rappels & Agenda'),
                    Opacity(
                      opacity: enabled ? 1.0 : 0.4,
                      child: SettingCard(children: [
                        SettingRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Rappels agenda',
                          subtitle: 'Avant vos rendez-vous',
                          toggle: true,
                          toggleValue: enabled && settings.notifAgenda,
                          onToggle: enabled ? (v) => settingsService.notifAgenda = v : null,
                        ),
                        SettingRow(
                          icon: Icons.assignment_outlined,
                          label: 'Mises à jour démarches',
                          subtitle: 'Expiration de documents, étapes',
                          toggle: true,
                          toggleValue: enabled && settings.notifDemarches,
                          onToggle: enabled ? (v) => settingsService.notifDemarches = v : null,
                        ),
                      ]),
                    ),

                    // ── Amiin ─────────────────────────────────────────────
                    const SettingsSection('Amiin'),
                    Opacity(
                      opacity: enabled ? 1.0 : 0.4,
                      child: SettingCard(children: [
                        SettingRow(
                          icon: Icons.tips_and_updates_outlined,
                          label: 'Conseil du jour',
                          subtitle: 'Une astuce ou information utile chaque matin',
                          toggle: true,
                          toggleValue: enabled && settings.notifConseil,
                          onToggle: enabled ? (v) => settingsService.notifConseil = v : null,
                        ),
                        SettingRow(
                          icon: Icons.replay_outlined,
                          label: 'Relance d\'actions',
                          subtitle: 'Rappel pour les tâches en cours non terminées',
                          toggle: true,
                          toggleValue: enabled && settings.notifRelance,
                          onToggle: enabled ? (v) => settingsService.notifRelance = v : null,
                        ),
                        SettingRow(
                          icon: Icons.summarize_outlined,
                          label: 'Résumé hebdomadaire',
                          subtitle: 'Bilan de votre semaine chaque lundi',
                          toggle: true,
                          toggleValue: enabled && settings.notifDigest,
                          onToggle: enabled ? (v) => settingsService.notifDigest = v : null,
                        ),
                      ]),
                    ),

                    // ── Ne pas déranger ───────────────────────────────────
                    const SettingsSection('Ne pas déranger'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aucune notification pendant ces heures',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: context.ac.muted,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _TimeButton(
                                  label: 'De',
                                  hour: settings.notifQuietStart,
                                  onTap: () => _pickHour(context, settings.notifQuietStart,
                                      (h) => settingsService.notifQuietStart = h),
                                ),
                              ),
                              const SizedBox(width: Spacing.md),
                              Text('—', style: TextStyle(color: context.ac.muted, fontFamily: FontFamily.sans)),
                              const SizedBox(width: Spacing.md),
                              Expanded(
                                child: _TimeButton(
                                  label: 'À',
                                  hour: settings.notifQuietEnd,
                                  onTap: () => _pickHour(context, settings.notifQuietEnd,
                                      (h) => settingsService.notifQuietEnd = h),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

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

  void _pickHour(BuildContext context, int current, ValueChanged<int> onPick) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: 24,
            itemBuilder: (_, h) => ListTile(
              title: Text('${h.toString().padLeft(2, '0')}:00'),
              trailing: h == current
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () { onPick(h); Navigator.pop(ctx); },
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final int hour;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.hour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: context.ac.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.ac.border),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: context.ac.muted, fontFamily: FontFamily.sans)),
            const SizedBox(height: 4),
            Text('${hour.toString().padLeft(2, '0')}:00',
                style: TextStyle(fontSize: 18, fontFamily: FontFamily.geoBold, color: primary)),
          ],
        ),
      ),
    );
  }
}

