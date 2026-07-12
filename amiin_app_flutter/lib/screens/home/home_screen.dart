// ─── HomeScreen ──────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../theme/spacing.dart';
import '../../theme/themes.dart';
import '../../theme/typography.dart';
import '../../services/agenda_service.dart';
import '../../services/chat_controller.dart';
import '../../services/notes_service.dart';
import '../../widgets/amiin_logo.dart';
import '../../widgets/card.dart';
import '../../widgets/horizon_line.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AmiinEvent> _events = [];
  List<AmiinNote> _notes = [];

  // Tuiles d'accès rapide — turquoise pour secretariat, ocre pour info
  List<_QuickTile> get _quickTiles => [
    _QuickTile(label: 'Agenda',     tab: 'agenda',    bg: context.ac.secretariatAccentLight, text: context.ac.secretariatAccentDark, isInfo: false),
    _QuickTile(label: 'Notes',      tab: 'notes',     bg: context.ac.secretariatAccentLight, text: context.ac.secretariatAccentDark, isInfo: false),
    _QuickTile(label: 'Annuaire',   tab: 'annuaire',  bg: context.ac.infoAccentLight,      text: context.ac.infoAccentDark,      isInfo: true),
    _QuickTile(label: 'Démarches',  tab: 'demarches', bg: context.ac.infoAccentLight,      text: context.ac.infoAccentDark,      isInfo: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    agendaService.listenable.addListener(_loadData);
    notesService.listenable.addListener(_loadData);
  }

  @override
  void dispose() {
    agendaService.listenable.removeListener(_loadData);
    notesService.listenable.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    try {
      final now = DateTime.now();
      final end = now.add(const Duration(days: 7));
      final results = await Future.wait([
        agendaService.getEvents(now.toIso8601String(), end.toIso8601String()),
        notesService.getNotes(),
      ]);
      if (!mounted) return;
      setState(() {
        _events = (results[0] as List<AmiinEvent>).take(3).toList();
        _notes = (results[1] as List<AmiinNote>).take(2).toList();
      });
    } catch (_) {}
  }

  Future<void> _onRefresh() => _loadData();

  String _formatEventDate(String iso) {
    final date = DateTime.parse(iso);
    final now = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventDay = DateTime(date.year, date.month, date.day);
    if (eventDay == today) return "Aujourd'hui · ${DateFormat('HH:mm').format(date)}";
    if (eventDay == tomorrow) return "Demain · ${DateFormat('HH:mm').format(date)}";
    return DateFormat("EEE d MMM · HH:mm", 'fr').format(date);
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'admin':     return context.ac.infoAccent;
      case 'personal':  return context.ac.secretariatAccent;
      case 'health':    return context.ac.success;
      case 'education': return context.ac.infoAccentMid;
      default:          return context.ac.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final insets = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: ac.background,
      body: RefreshIndicator(
        color: ac.secretariatAccent,
        backgroundColor: ac.surface,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            // ── Hero header ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ac.headerGradientStart, ac.headerGradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: insets.top + 12),
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                      child: Row(
                        children: [
                          const AmiinLogo(size: 32, variant: AmiinLogoVariant.turquoise),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Amiin',
                              style: TextStyle(
                                fontFamily: FontFamily.geoBold,
                                fontSize: 18,
                                letterSpacing: 0.5,
                                color: ac.onHeader,
                              ),
                            ),
                          ),
                          _HeaderIconButton(
                            icon: Icons.settings_outlined,
                            color: ac.onHeader,
                            onTap: () => context.push('/settings'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xxxl),
                    // Greeting
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                      child: Text(
                        'Bonjour — que puis-je\nfaire pour vous ?',
                        style: TextStyle(
                          fontFamily: FontFamily.sansLight,
                          fontSize: 15,
                          color: ac.onHeader.withValues(alpha: 0.55),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    // Bouton micro
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'Parler à Amiin',
                        child: GestureDetector(
                          onTap: () {
                            chatListenRequest.value++;
                            context.go('/chat');
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 60, height: 60,
                                decoration: BoxDecoration(
                                  color: ac.secretariatAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: ac.secretariatAccent.withValues(alpha: 0.35),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    )
                                  ],
                                ),
                                child: Center(
                                  child: SvgPicture.string(_micSvg, width: 22, height: 26),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Parler à Amiin',
                                style: TextStyle(
                                  fontFamily: FontFamily.geo,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                  color: ac.onHeader.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    // Barre de saisie rapide
                    GestureDetector(
                      onTap: () => context.go('/chat'),
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                          borderRadius: BorderRadius.circular(RadiusAmiin.full),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Écrivez votre question…',
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ac.onHeader.withValues(alpha: 0.30),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.xxxl),
                    // Ligne d'horizon — au bas du header
                    HorizonLine(color: context.ac.secretariatAccent, height: 1.5),
                  ],
                ),
              ),
            ),

            // ── Contenu ────────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: Spacing.xxl),

                  // Accès rapide
                  _SectionLabel(
                    label: 'Accès rapide',
                    modeColor: ac.secretariatAccent,
                  ),
                  const SizedBox(height: Spacing.sm),
                  _QuickTilesGrid(tiles: _quickTiles),

                  // Événements
                  if (_events.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxxl),
                    _SectionLabel(
                      label: 'Cette semaine',
                      modeColor: ac.secretariatAccent,
                      action: _SectionAction(
                        label: 'Agenda',
                        onTap: () => context.push('/agenda'),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    ..._events.map((ev) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: AmiinCard(
                        variant: CardVariant.secretariat,
                        onTap: () => context.push('/agenda/event/${ev.id}'),
                        child: Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: _categoryColor(ev.category.name),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: Spacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ev.title, style: TextStyle(
                                    fontFamily: FontFamily.geoMedium,
                                    fontSize: 14,
                                    color: ac.ink,
                                  )),
                                  const SizedBox(height: 2),
                                  Text(_formatEventDate(ev.startDate), style: TextStyle(
                                    fontFamily: FontFamily.sans,
                                    fontSize: 12,
                                    color: ac.muted,
                                  )),
                                ],
                              ),
                            ),
                            if (ev.createdByAgent == true)
                              _AgentBadge(color: ac.secretariatAccent),
                          ],
                        ),
                      ),
                    )),
                  ],

                  // Notes récentes
                  if (_notes.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxxl),
                    _SectionLabel(
                      label: 'Notes récentes',
                      modeColor: ac.secretariatAccent,
                      action: _SectionAction(
                        label: 'Voir tout',
                        onTap: () => context.go('/notes'),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    ..._notes.map((note) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: AmiinCard(
                        onTap: () => context.push('/notes/${note.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.title, style: TextStyle(
                              fontFamily: FontFamily.geoBold,
                              fontSize: 14,
                              color: ac.ink,
                            )),
                            const SizedBox(height: 4),
                            Text(
                              note.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 13,
                                color: ac.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ],

                  const SizedBox(height: Spacing.huge),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _micSvg = '''
    <svg width="22" height="26" viewBox="0 0 26 30" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect x="8" y="1" width="10" height="16" rx="5" stroke="white" stroke-width="2"/>
      <path d="M3 15a10 10 0 0020 0" stroke="white" stroke-width="2" stroke-linecap="round"/>
      <path d="M13 25v4" stroke="white" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ''';
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(child: Icon(icon, size: 17, color: color)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color modeColor;
  final _SectionAction? action;

  const _SectionLabel({required this.label, required this.modeColor, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: modeColor, borderRadius: BorderRadius.circular(2))),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: FontFamily.geo,
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 1.2,
            color: context.ac.muted,
          ),
        ),
        const Spacer(),
        if (action != null)
          InkWell(
            onTap: action!.onTap,
            borderRadius: BorderRadius.circular(RadiusAmiin.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                action!.label,
                style: TextStyle(
                  fontFamily: FontFamily.geoMedium,
                  fontSize: 12,
                  color: modeColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionAction {
  final String label;
  final VoidCallback onTap;
  const _SectionAction({required this.label, required this.onTap});
}

class _QuickTile {
  final String label;
  final String tab;
  final Color bg;
  final Color text;
  final bool isInfo;
  const _QuickTile({required this.label, required this.tab, required this.bg, required this.text, required this.isInfo});
}

class _QuickTilesGrid extends StatelessWidget {
  final List<_QuickTile> tiles;
  const _QuickTilesGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 2 * Spacing.xl - Spacing.sm) / 2;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: tiles.map((tile) {
        return Material(
          color: tile.bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => context.go('/${tile.tab}'),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: w,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: tile.text, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tile.label,
                      style: TextStyle(
                        fontFamily: FontFamily.geoBold,
                        fontSize: 13,
                        color: tile.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AgentBadge extends StatelessWidget {
  final Color color;
  const _AgentBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text('Amiin', style: TextStyle(
        fontFamily: FontFamily.geoBold,
        fontSize: 9,
        letterSpacing: 0.5,
        color: color,
      )),
    );
  }
}
