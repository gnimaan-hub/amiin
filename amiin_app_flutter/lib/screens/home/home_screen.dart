// ─── HomeScreen ──────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/agenda_service.dart';
import '../../services/chat_controller.dart';
import '../../services/notes_service.dart';
import '../../widgets/amiin_logo.dart';
import '../../widgets/card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AmiinEvent> _events = [];
  List<AmiinNote> _notes = [];

  final _quickTiles = [
    {'label': 'Agenda', 'tab': 'agenda', 'bg': ColorsAmiin.indigoLt, 'text': ColorsAmiin.indigo},
    {'label': 'Notes', 'tab': 'notes', 'bg': ColorsAmiin.terraLt, 'text': ColorsAmiin.terraDk},
    {'label': 'Annuaire', 'tab': 'annuaire', 'bg': ColorsAmiin.oliveLt, 'text': ColorsAmiin.olive},
    {'label': 'Démarches', 'tab': 'demarches', 'bg': ColorsAmiin.sand, 'text': ColorsAmiin.mid},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    // Hive est réactif : toute création/modification (manuelle ou par Amiin
    // depuis le chat) rafraîchit automatiquement l'accueil.
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
      final eventsFuture = agendaService.getEvents(
        now.toIso8601String(),
        end.toIso8601String(),
      );
      final notesFuture = notesService.getNotes();
      final results = await Future.wait([eventsFuture, notesFuture]);
      if (!mounted) return;
      setState(() {
        _events = (results[0] as List<AmiinEvent>).take(3).toList();
        _notes = (results[1] as List<AmiinNote>).take(2).toList();
      });
    } catch (e) {
      // ignore
    }
  }

 
  Future<void> _onRefresh() async {
    await _loadData();
  }

  String _formatEventDate(String iso) {
    final date = DateTime.parse(iso);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventDay = DateTime(date.year, date.month, date.day);
    if (eventDay == today) {
      return "Aujourd'hui · ${DateFormat('HH:mm').format(date)}";
    } else if (eventDay == tomorrow) {
      return "Demain · ${DateFormat('HH:mm').format(date)}";
    } else {
      return DateFormat("EEE d MMM · HH:mm", 'fr').format(date);
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'admin': return ColorsAmiin.terra;
      case 'personal': return ColorsAmiin.olive;
      case 'health': return ColorsAmiin.indigo;
      case 'education': return const Color(0xFF8C6D3F);
      default: return ColorsAmiin.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: RefreshIndicator(
        color: ColorsAmiin.terra,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            // Hero header with gradient
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [ColorsAmiin.ink, ColorsAmiin.darkMid],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: EdgeInsets.only(top: insets.top + 12, bottom: 32),
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                      child: Row(
                        children: [
                          const AmiinLogo(size: 36, variant: AmiinLogoVariant.dark),
                          SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Amiin',
                              style: TextStyle(
                                fontFamily: FontFamily.serif,
                                fontSize: 20,
                                letterSpacing: 0.4,
                                color: ColorsAmiin.onDark,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push('/profile'),
                            child: Container(
                              width: 32, height: 32,
                              decoration: const BoxDecoration(
                                color: ColorsAmiin.terra,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('M', style: TextStyle(
                                  fontFamily: FontFamily.serifBold,
                                  fontSize: 14,
                                  color: ColorsAmiin.white,
                                )),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: Spacing.xxl),
                    // Greeting + CTA
                    Column(
                      children: [
                        Text(
                          'Bonjour — que puis-je\nfaire pour vous ?',
                          style: TextStyle(
                            fontFamily: FontFamily.sansLight,
                            fontSize: 15,
                            color: ColorsAmiin.onDark.withValues(alpha: 0.6),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: Spacing.xl),
                        Semantics(
                          button: true,
                          label: 'Parler à Amiin (dictée vocale)',
                          child: GestureDetector(
                            onTap: () {
                              // Demander au chat de démarrer l'écoute :
                              // le bouton tient enfin sa promesse "Parler".
                              chatListenRequest.value++;
                              context.go('/chat');
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 64, height: 64,
                                  decoration: BoxDecoration(
                                    color: ColorsAmiin.terra,
                                    shape: BoxShape.circle,
                                    boxShadow: ShadowAmiin.lg,
                                  ),
                                  child: Center(
                                    child: SvgPicture.string(_micSvg, width: 22, height: 26),
                                  ),
                                ),
                                SizedBox(height: Spacing.sm),
                                Text(
                                  'Parler à Amiin',
                                  style: TextStyle(
                                    fontFamily: FontFamily.sans,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    color: ColorsAmiin.onDark.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: Spacing.xl),
                        GestureDetector(
                          onTap: () => context.go('/chat'),
                          child: Container(
                            width: double.infinity,
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                                  color: ColorsAmiin.onDark.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Sheet content
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  SizedBox(height: 16), // negative margin offset
                  // Quick tiles section
                  _buildSectionHeader('Accès rapide', null),
                  SizedBox(height: Spacing.sm),
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: _quickTiles.map((tile) {
                      return Material(
                        color: tile['bg'] as Color,
                        borderRadius: BorderRadius.circular(RadiusAmiin.md),
                        child: InkWell(
                          onTap: () {
                            final tab = tile['tab'] as String;
                            context.go('/$tab');
                          },
                          borderRadius: BorderRadius.circular(RadiusAmiin.md),
                          child: Container(
                            width: (MediaQuery.of(context).size.width - 3 * Spacing.xl - Spacing.sm) / 2,
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(
                              tile['label'] as String,
                              style: TextStyle(
                                fontFamily: FontFamily.sansBold,
                                fontSize: 13,
                                color: tile['text'] as Color,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: Spacing.xxl),
                  // Upcoming events
                  if (_events.isNotEmpty) ...[
                    _buildSectionHeader('Prochains événements', () => context.push('/agenda')),
                    SizedBox(height: Spacing.sm),
                    ..._events.map((ev) => GestureDetector(
                      onTap: () => context.push('/agenda/event/${ev.id}'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: AmiinCard(
                          variant: CardVariant.default_,
                          child: Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: _categoryColor(ev.category.name),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: Spacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ev.title, style: TextStyle(
                                      fontFamily: FontFamily.sansMedium,
                                      fontSize: 14,
                                      color: ColorsAmiin.ink,
                                    )),
                                    SizedBox(height: 2),
                                    Text(_formatEventDate(ev.startDate), style: TextStyle(
                                      fontFamily: FontFamily.sans,
                                      fontSize: 12,
                                      color: ColorsAmiin.muted,
                                    )),
                                  ],
                                ),
                              ),
                              if (ev.createdByAgent == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ColorsAmiin.terraLt,
                                    borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                                  ),
                                  child: Text('Amiin', style: TextStyle(
                                    fontFamily: FontFamily.sansBold,
                                    fontSize: 10,
                                    color: ColorsAmiin.terraDk,
                                  )),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )),
                  ],
                  if (_notes.isNotEmpty) ...[
                    SizedBox(height: Spacing.xxl),
                    _buildSectionHeader('Notes récentes', () => context.go('/notes')),
                    SizedBox(height: Spacing.sm),
                    ..._notes.map((note) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: AmiinCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.title, style: TextStyle(
                              fontFamily: FontFamily.sansBold,
                              fontSize: 14,
                              color: ColorsAmiin.ink,
                            )),
                            SizedBox(height: 4),
                            Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 13,
                              color: ColorsAmiin.muted,
                              height: 1.5,
                            )),
                          ],
                        ),
                      ),
                    )),
                  ],
                  SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(
          fontFamily: FontFamily.sansBold,
          fontSize: 10,
          letterSpacing: 1.2,
          color: ColorsAmiin.muted,
        )),
        if (onSeeAll != null)
          InkWell(
            onTap: onSeeAll,
            borderRadius: BorderRadius.circular(RadiusAmiin.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('Voir tout', style: TextStyle(
                fontFamily: FontFamily.sansMedium,
                fontSize: 12,
                color: ColorsAmiin.terra,
              )),
            ),
          ),
      ],
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