// ─── SettingsAssistantScreen ── Comportement d'Amiin ─────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../services/cloud_tts_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

// Miroir de la liste backend — permet l'affichage hors-ligne et l'aperçu.
const _kCloudVoices = [
  {'id': 'fr-FR-DeniseNeural',           'name': 'Denise',  'lang': 'Français', 'gender': 'F', 'note': ''},
  {'id': 'fr-FR-HenriNeural',            'name': 'Henri',   'lang': 'Français', 'gender': 'M', 'note': ''},
  {'id': 'fr-FR-RemyMultilingualNeural', 'name': 'Rémy',    'lang': 'Français', 'gender': 'M', 'note': 'grave'},
  {'id': 'fr-BE-GerardNeural',           'name': 'Gérard',  'lang': 'Français', 'gender': 'M', 'note': 'grave'},
  {'id': 'fr-CA-JeanNeural',             'name': 'Jean',    'lang': 'Français', 'gender': 'M', 'note': 'grave'},
  {'id': 'en-US-JennyNeural',            'name': 'Jenny',   'lang': 'Anglais',  'gender': 'F', 'note': ''},
  {'id': 'en-US-GuyNeural',              'name': 'Guy',     'lang': 'Anglais',  'gender': 'M', 'note': ''},
  {'id': 'en-GB-SoniaNeural',            'name': 'Sonia',   'lang': 'Anglais',  'gender': 'F', 'note': ''},
];

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
                          const SizedBox(height: Spacing.md),
                          _VoiceModeDescription(mode: settings.defaultVoiceMode),
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

                    // ── Voix cloud (Edge TTS) ─────────────────────────────
                    const SettingsSection('Voix cloud (Edge TTS)'),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.record_voice_over_outlined, size: 18, color: primary),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Voix neuronales Microsoft', style: TextStyle(
                                      fontFamily: FontFamily.sans,
                                      fontSize: 15,
                                      color: ColorsAmiin.ink,
                                    )),
                                    Text('Indépendantes des voix installées sur le téléphone.', style: TextStyle(
                                      fontFamily: FontFamily.sans,
                                      fontSize: 12,
                                      color: ColorsAmiin.muted,
                                    )),
                                    Text('Ajoute 2–5 s de délai avant la lecture.', style: TextStyle(
                                      fontFamily: FontFamily.sans,
                                      fontSize: 12,
                                      color: ColorsAmiin.ocre,
                                    )),
                                  ],
                                ),
                              ),
                              Switch(
                                value: settings.useCloudTts,
                                onChanged: (v) => settingsService.useCloudTts = v,
                                activeColor: primary,
                              ),
                            ],
                          ),
                          if (settings.useCloudTts) ...[
                            const Divider(height: 28),
                            Text('Choisir une voix', style: TextStyle(
                              fontFamily: FontFamily.geoMedium,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                            )),
                            const SizedBox(height: Spacing.sm),
                            ..._buildVoiceList(context, settings, primary),
                          ],
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

  /// Construit les tuiles de voix groupées par langue.
  static List<Widget> _buildVoiceList(
    BuildContext context,
    SettingsService settings,
    Color primary,
  ) {
    final groups = <String, List<Map<String, String>>>{};
    for (final v in _kCloudVoices) {
      final lang = v['lang']!;
      groups.putIfAbsent(lang, () => []).add(v);
    }

    final widgets = <Widget>[];
    groups.forEach((lang, voices) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: Spacing.sm, bottom: 4),
        child: Text(lang, style: TextStyle(
          fontFamily: FontFamily.sans,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ColorsAmiin.muted,
          letterSpacing: 0.5,
        )),
      ));
      for (final voice in voices) {
        final id = voice['id']!;
        final isSelected = settings.ttsVoice == id;
        widgets.add(_VoiceTile(
          voice: voice,
          selected: isSelected,
          primary: primary,
          onSelect: () => settingsService.ttsVoice = id,
        ));
      }
    });
    return widgets;
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

// ─── Description du mode vocal ───────────────────────────────────────────────

class _VoiceModeDescription extends StatelessWidget {
  const _VoiceModeDescription({required this.mode});
  final String mode;

  static const _descriptions = {
    'none': 'Amiin ne parle jamais. Tu lis les réponses à l\'écran, aucun son ne se déclenche.',
    'tts':  'Chaque réponse d\'Amiin est lue à voix haute automatiquement, que tu aies tapé ou parlé.',
    'voice': 'Amiin répond à voix haute uniquement quand tu lui parles au micro. Si tu tapes, il reste silencieux.',
  };

  static const _icons = {
    'none':  Icons.volume_off_outlined,
    'tts':   Icons.volume_up_outlined,
    'voice': Icons.mic_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final desc = _descriptions[mode] ?? '';
    final icon = _icons[mode] ?? Icons.volume_off_outlined;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(mode),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(desc, style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: 12,
                color: ColorsAmiin.ink,
                height: 1.5,
              )),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tuile de voix cloud ──────────────────────────────────────────────────────
// Affiche une voix sélectionnable + bouton d'aperçu.
class _VoiceTile extends StatefulWidget {
  const _VoiceTile({
    required this.voice,
    required this.selected,
    required this.primary,
    required this.onSelect,
  });

  final Map<String, String> voice;
  final bool selected;
  final Color primary;
  final VoidCallback onSelect;

  @override
  State<_VoiceTile> createState() => _VoiceTileState();
}

class _VoiceTileState extends State<_VoiceTile> {
  bool _previewing = false;

  Future<void> _preview() async {
    if (_previewing) {
      await cloudTtsService.stop();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    // Sélectionne temporairement la voix pour l'aperçu
    final prev = settingsService.ttsVoice;
    settingsService.ttsVoice = widget.voice['id']!;
    try {
      await cloudTtsService.speak('Bonjour, je suis votre assistant Amiin.');
    } catch (_) {
      // ignore — l'erreur est déjà loguée dans CloudTtsService
    }
    settingsService.ttsVoice = prev;
    if (mounted) setState(() => _previewing = false);
  }

  @override
  Widget build(BuildContext context) {
    final gender = widget.voice['gender'] == 'F' ? '♀' : '♂';
    return InkWell(
      onTap: widget.onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              widget.selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: widget.selected ? widget.primary : ColorsAmiin.muted,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Row(
                children: [
                  Text(
                    '${widget.voice['name']}  $gender',
                    style: TextStyle(
                      fontFamily: FontFamily.sans,
                      fontSize: 14,
                      color: widget.selected ? ColorsAmiin.ink : ColorsAmiin.mid,
                      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (widget.voice['note'] == 'grave') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('grave', style: TextStyle(
                        fontFamily: FontFamily.sans,
                        fontSize: 10,
                        color: widget.primary,
                        fontWeight: FontWeight.w600,
                      )),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: _preview,
              icon: _previewing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.primary,
                      ),
                    )
                  : Icon(Icons.play_circle_outline, size: 20, color: widget.primary),
              tooltip: 'Aperçu',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
