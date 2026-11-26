// ─── SettingsNotificationsScreen ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../services/agenda_service.dart';
import '../../services/demarches_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import 'settings_widgets.dart';

class SettingsNotificationsScreen extends StatelessWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final enabled = settings.notifMaster;

    return Scaffold(
      backgroundColor: context.ac.page,
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
                        onToggle: (v) {
                          settingsService.notifMaster = v;
                          if (v) {
                            agendaService.rescheduleAllReminders();
                            demarchesService.rescheduleAllFollowUps();
                          } else {
                            agendaService.cancelAllReminders();
                            demarchesService.cancelAllFollowUps();
                          }
                        },
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
                          onToggle: enabled
                              ? (v) {
                                  settingsService.notifAgenda = v;
                                  v
                                      ? agendaService.rescheduleAllReminders()
                                      : agendaService.cancelAllReminders();
                                }
                              : null,
                        ),
                        SettingRow(
                          icon: Icons.assignment_outlined,
                          label: 'Mises à jour démarches',
                          subtitle: 'Expiration de documents, étapes',
                          toggle: true,
                          toggleValue: enabled && settings.notifDemarches,
                          onToggle: enabled
                              ? (v) {
                                  settingsService.notifDemarches = v;
                                  v
                                      ? demarchesService.rescheduleAllFollowUps()
                                      : demarchesService.cancelAllFollowUps();
                                }
                              : null,
                        ),
                      ]),
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
}
