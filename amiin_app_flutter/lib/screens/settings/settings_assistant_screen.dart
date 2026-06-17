// ─── SettingsAssistantScreen ── Comportement d'Amiin ─────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsAssistantScreen extends StatelessWidget {
  const SettingsAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Comportement d\'Amiin', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    // ── Ton de réponse ────────────────────────────────────
                    const SettingsSection('Ton de réponse'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comment Amiin doit-il s\'exprimer avec vous ?',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          ChoiceSelector(
                            options: const ['formal', 'neutral', 'casual'],
                            labels: const ['Formel', 'Neutre', 'Décontracté'],
                            current: settings.tone,
                            onSelect: (v) => settingsService.tone = v,
                          ),
                        ],
                      ),
                    ),

                    // ── Longueur des réponses ─────────────────────────────
                    const SettingsSection('Longueur des réponses'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quelle verbosité préférez-vous dans les réponses ?',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          ChoiceSelector(
                            options: const ['concise', 'balanced', 'detailed'],
                            labels: const ['Concise', 'Équilibrée', 'Détaillée'],
                            current: settings.responseLength,
                            onSelect: (v) => settingsService.responseLength = v,
                          ),
                        ],
                      ),
                    ),

                    // ── Niveau d'expertise ────────────────────────────────
                    const SettingsSection("Niveau d'expertise"),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'À quel niveau de détail souhaitez-vous les explications ?',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          ChoiceSelector(
                            options: const ['simplified', 'standard', 'expert'],
                            labels: const ['Simplifié', 'Standard', 'Expert'],
                            current: settings.expertiseLevel,
                            onSelect: (v) => settingsService.expertiseLevel = v,
                          ),
                        ],
                      ),
                    ),

                    // ── Domaines favoris ──────────────────────────────────
                    const SettingsSection('Domaines favoris'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amiin priorisera ces thématiques dans ses réponses.',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          _TopicsPicker(
                            selected: settings.favoriteTopics,
                            onChanged: (v) => settingsService.favoriteTopics = v,
                          ),
                        ],
                      ),
                    ),

                    // ── Mémoire ───────────────────────────────────────────
                    const SettingsSection('Mémoire'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.memory_outlined,
                        label: 'Mémoire long terme',
                        subtitle: 'Amiin se souvient de vos actions passées',
                        toggle: true,
                        toggleValue: settings.memoryEnabled,
                        onToggle: (v) => settingsService.memoryEnabled = v,
                      ),
                      SettingRow(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Effacer la mémoire',
                        subtitle: 'Supprime l\'historique des actions mémorisées',
                        onTap: () => _confirmClearMemory(context),
                      ),
                    ]),

                    // ── Comportements proactifs ───────────────────────────
                    const SettingsSection('Comportements proactifs'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Suggestions automatiques',
                        subtitle: 'Amiin propose de créer des notes ou rappels',
                        toggle: true,
                        toggleValue: settings.proactiveSuggestions,
                        onToggle: (v) => settingsService.proactiveSuggestions = v,
                      ),
                      SettingRow(
                        icon: Icons.wb_sunny_outlined,
                        label: 'Résumé quotidien',
                        subtitle: 'Briefing matinal de l\'agenda et des tâches',
                        toggle: true,
                        toggleValue: settings.dailyDigest,
                        onToggle: (v) => settingsService.dailyDigest = v,
                      ),
                    ]),

                    // ── Mode vocal par défaut ─────────────────────────────
                    const SettingsSection('Mode vocal par défaut'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comportement vocal à l\'ouverture d\'une conversation.',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          ChoiceSelector(
                            options: const ['none', 'tts', 'voice'],
                            labels: const ['Aucun', 'Lecture auto', 'Conversationnel'],
                            current: settings.defaultVoiceMode,
                            onSelect: (v) => settingsService.defaultVoiceMode = v,
                          ),
                        ],
                      ),
                    ),

                    // ── Voix ──────────────────────────────────────────────
                    const SettingsSection('Synthèse vocale (TTS)'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.speed_outlined, size: 18, color: primary),
                              const SizedBox(width: Spacing.sm),
                              Text('Vitesse de lecture', style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 15,
                                color: ColorsAmiin.ink,
                              )),
                              const Spacer(),
                              Text(
                                '${settings.ttsSpeed.toStringAsFixed(1)}×',
                                style: TextStyle(
                                  fontFamily: FontFamily.geoMedium,
                                  fontSize: 14,
                                  color: primary,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: settings.ttsSpeed,
                            min: 0.5,
                            max: 2.0,
                            divisions: 6,
                            activeColor: primary,
                            onChanged: (v) => settingsService.ttsSpeed = v,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('0.5×', style: TextStyle(fontSize: 11, color: ColorsAmiin.muted, fontFamily: FontFamily.sans)),
                              Text('2.0×', style: TextStyle(fontSize: 11, color: ColorsAmiin.muted, fontFamily: FontFamily.sans)),
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

  static void _confirmClearMemory(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer la mémoire'),
        content: const Text(
            'Amiin oubliera tout l\'historique de vos actions. Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mémoire effacée')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }
}

// ── Sélecteur de domaines favoris (chips multi-sélection) ────────────────────

class _TopicsPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _TopicsPicker({required this.selected, required this.onChanged});

  static const _topics = [
    'Administration & démarches',
    'Santé',
    'Éducation & formation',
    'Finance & banque',
    'Droit & juridique',
    'Commerce & business',
    'Transport',
    'Immobilier',
    'Famille & social',
    'Technologie',
    'Tourisme & culture',
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: Spacing.xs,
      runSpacing: Spacing.xs,
      children: _topics.map((topic) {
        final isSelected = selected.contains(topic);
        return GestureDetector(
          onTap: () {
            final updated = List<String>.from(selected);
            if (isSelected) {
              updated.remove(topic);
            } else {
              updated.add(topic);
            }
            onChanged(updated);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? primary.withValues(alpha: 0.12) : ColorsAmiin.ecru,
              borderRadius: BorderRadius.circular(RadiusAmiin.full),
              border: Border.all(
                color: isSelected ? primary : ColorsAmiin.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check, size: 13, color: primary),
                  const SizedBox(width: 4),
                ],
                Text(topic, style: TextStyle(
                  fontFamily: FontFamily.geoMedium,
                  fontSize: 12,
                  color: isSelected ? primary : ColorsAmiin.mid,
                )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
