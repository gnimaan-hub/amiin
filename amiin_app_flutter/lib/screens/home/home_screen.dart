// ─── HomeScreen ──────────────────────────────────────────────────────────────
//
// Design d'origine (bandeau encre de nuit, micro central, labels de section
// en capitales, tuiles turquoise/ocre) retravaillé dans un esprit « vitrine » :
// fond blanc cassé, éléments qui flottent sur des ombres douces à plusieurs
// couches, carte « Aujourd'hui » posée à cheval sur le bandeau, halo autour
// du micro, champ de saisie en verre dépoli, cartes qui s'enfoncent au toucher.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/amiin_svg_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../theme/spacing.dart';
import '../../theme/themes.dart';
import '../../theme/typography.dart';
import '../../services/agenda_service.dart';
import '../../services/chat_controller.dart';
import '../../services/home_brief_service.dart';
import '../../services/notes_service.dart';
import '../../widgets/amiin_logo.dart';

// ── Tokens locaux de la vitrine ──────────────────────────────────────────────

/// Rayon des cartes flottantes.
const double _kRadius = 18;

/// Fond blanc cassé (thèmes clairs) ; les thèmes sombres gardent leur fond.
Color _pageBackground(BuildContext context) {
  final ac = context.ac;
  if (ac.brightness == Brightness.dark) return ac.background;
  return Color.lerp(ac.background, Colors.white, 0.62)!;
}

/// Ombre « flottante » : un contact net + une diffusion large et douce.
/// [lift] de 0 (posé) à 1 (très soulevé) ; [tint] colore la diffusion.
List<BoxShadow> _floatShadow(BuildContext context, {double lift = 0.5, Color? tint}) {
  final dark = context.ac.brightness == Brightness.dark;
  final base = dark ? Colors.black : context.ac.ink;
  final diffuse = tint ?? base;
  final k = dark ? 2.2 : 1.0;
  return [
    BoxShadow(
      color: base.withValues(alpha: 0.04 * k),
      blurRadius: 1.5,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: diffuse.withValues(alpha: (0.05 + 0.05 * lift) * k),
      blurRadius: 10 + 26 * lift,
      offset: Offset(0, 4 + 12 * lift),
      spreadRadius: -4,
    ),
  ];
}

/// Liseré clair sur le bord des cartes : accroche la lumière.
Border _hairline(BuildContext context) => Border.all(
      color: context.ac.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.9),
      width: 1,
    );

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
    _QuickTile(label: 'Agenda',    tab: 'agenda',    icon: Icons.calendar_today_rounded, accent: context.ac.secretariatAccent, bg: context.ac.secretariatAccentLight, text: context.ac.secretariatAccentDark),
    _QuickTile(label: 'Notes',     tab: 'notes',     icon: Icons.edit_note_rounded,      accent: context.ac.secretariatAccent, bg: context.ac.secretariatAccentLight, text: context.ac.secretariatAccentDark),
    _QuickTile(label: 'Annuaire',  tab: 'annuaire',  icon: Icons.people_rounded,         accent: context.ac.infoAccent,        bg: context.ac.infoAccentLight,        text: context.ac.infoAccentDark),
    _QuickTile(label: 'Démarches', tab: 'demarches', icon: Icons.assignment_rounded,     accent: context.ac.infoAccent,        bg: context.ac.infoAccentLight,        text: context.ac.infoAccentDark),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    homeBriefService.refresh();
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

  Future<void> _onRefresh() =>
      Future.wait([_loadData(), homeBriefService.refresh(force: true)]);

  String get _greeting {
    final h = DateTime.now().hour;
    final s = h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
    return '$s — que puis-je\nfaire pour vous ?';
  }

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
      backgroundColor: _pageBackground(context),
      body: RefreshIndicator(
        color: ac.secretariatAccent,
        backgroundColor: ac.surface,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // ── Hero header ───────────────────────────────────────────────────
            // Bandeau + carte « Aujourd'hui » dans le même bloc : la carte,
            // peinte après le bandeau, flotte par-dessus son bord inférieur.
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    topInset: insets.top,
                    greeting: _greeting,
                    onSettings: () => context.push('/settings'),
                    onMic: () {
                      chatListenRequest.value++;
                      context.go('/chat');
                    },
                    onAsk: () => context.go('/chat'),
                  ),
                  ValueListenableBuilder<HomeBrief?>(
                    valueListenable: homeBriefService.brief,
                    builder: (context, brief, _) {
                      // Sans brief, simple espace sous le bandeau.
                      if (brief == null || brief.isEmpty) {
                        return const SizedBox(height: Spacing.xxl);
                      }
                      // Le décalage vers le haut laisse sous la carte un espace
                      // égal à [_Hero.overlap] avant la section suivante.
                      return Transform.translate(
                        offset: const Offset(0, -_Hero.overlap),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                          child: _DailyBriefCard(brief: brief),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Contenu ────────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Accès rapide
                  _SectionLabel(
                    label: 'Accès rapide',
                    modeColor: ac.secretariatAccent,
                  ),
                  const SizedBox(height: Spacing.md),
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
                    const SizedBox(height: Spacing.md),
                    _FloatingCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _events.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 38),
                                child: Divider(height: 0.5, thickness: 0.5, color: ac.border.withValues(alpha: 0.7)),
                              ),
                            _EventRow(
                              title: _events[i].title,
                              when: _formatEventDate(_events[i].startDate),
                              dotColor: _categoryColor(_events[i].category.name),
                              byAgent: _events[i].createdByAgent == true,
                              onTap: () => context.push('/agenda/event/${_events[i].id}'),
                            ),
                          ],
                        ],
                      ),
                    ),
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
                    const SizedBox(height: Spacing.md),
                    ..._notes.map((note) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: _FloatingCard(
                        onTap: () => context.push('/notes/${note.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.title, style: TextStyles.cardTitle(context).copyWith(fontFamily: FontFamily.geoBold)),
                            const SizedBox(height: 4),
                            Text(
                              note.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.bodyMuted(context).copyWith(fontSize: 13),
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
}

// ── Bandeau héros ─────────────────────────────────────────────────────────────
// Encre de nuit, coins bas arrondis, ombre portée sur la page, halos diffus
// turquoise et ocre pour la profondeur.

class _Hero extends StatelessWidget {
  /// Hauteur dont la carte « Aujourd'hui » chevauche le bandeau.
  static const double overlap = 36;

  final double topInset;
  final String greeting;
  final VoidCallback onSettings;
  final VoidCallback onMic;
  final VoidCallback onAsk;

  const _Hero({
    required this.topInset,
    required this.greeting,
    required this.onSettings,
    required this.onMic,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    const radius = BorderRadius.vertical(bottom: Radius.circular(32));

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: ac.headerGradientStart.withValues(alpha: 0.28),
            blurRadius: 40,
            offset: const Offset(0, 18),
            spreadRadius: -12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Dégradé de fond
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ac.headerGradientStart, ac.headerGradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            // Halo turquoise, en haut à droite
            Positioned(
              top: -120, right: -90,
              child: _Glow(color: ac.secretariatAccent, size: 300, alpha: 0.30),
            ),
            // Halo ocre, plus discret, en bas à gauche
            Positioned(
              bottom: -140, left: -110,
              child: _Glow(color: ac.infoAccent, size: 280, alpha: 0.14),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topInset + 12),
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
                          style: TextStyles.screenTitle(context).copyWith(color: ac.onHeader, letterSpacing: 0.5),
                        ),
                      ),
                      _GlassIconButton(
                        icon: Icons.settings_outlined,
                        color: ac.onHeader,
                        onTap: onSettings,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.xxxl),
                // Greeting
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                  child: Text(
                    greeting,
                    style: TextStyle(
                      fontFamily: FontFamily.sansLight,
                      fontSize: 17,
                      color: ac.onHeader.withValues(alpha: 0.72),
                      height: 1.5,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: Spacing.xxl),
                Center(child: _MicButton(onTap: onMic)),
                const SizedBox(height: Spacing.xxl),
                // Barre de saisie — verre dépoli
                _GlassField(onTap: onAsk),
                // Réserve la place de la carte qui chevauche le bandeau
                const SizedBox(height: Spacing.xxl + _Hero.overlap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;

  const _Glow({required this.color, required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0.0),
        ]),
      ),
    );
  }
}

/// Micro flottant : anneau concentrique, dégradé, ombre teintée.
class _MicButton extends StatefulWidget {
  final VoidCallback onTap;
  const _MicButton({required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final accent = ac.secretariatAccent;
    return Semantics(
      button: true,
      label: 'Parler à Amiin',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.08),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Center(
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(accent, Colors.white, 0.18)!, accent],
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: SvgPicture.string(AmiinSvgIcons.mic, width: 22, height: 26),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Parler à Amiin',
              style: TextStyles.cardTitle(context).copyWith(fontSize: 11, color: ac.onHeader.withValues(alpha: 0.55), fontWeight: FontWeight.w500, letterSpacing: 0.6, fontFamily: FontFamily.geo),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Semantics(
        button: true,
        label: 'Écrire une question à Amiin',
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RadiusAmiin.full),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 50,
                padding: const EdgeInsets.only(left: Spacing.lg, right: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.circular(RadiusAmiin.full),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Écrivez votre question…',
                        style: TextStyles.body(context).copyWith(fontSize: 14, color: ac.onHeader.withValues(alpha: 0.45)),
                      ),
                    ),
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ac.onHeader.withValues(alpha: 0.92),
                      ),
                      child: Icon(Icons.arrow_upward_rounded, size: 20, color: ac.headerGradientStart),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Réglages',
      child: GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Center(child: Icon(icon, size: 18, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Carte flottante : surface, liseré clair, ombre douce, enfoncement ────────

class _FloatingCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double lift;
  final Color? color;
  final Color? shadowTint;

  const _FloatingCard({
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.onTap,
    this.lift = 0.5,
    this.color,
    this.shadowTint,
  });

  @override
  State<_FloatingCard> createState() => _FloatingCardState();
}

class _FloatingCardState extends State<_FloatingCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.color ?? context.ac.surface,
        borderRadius: BorderRadius.circular(_kRadius),
        border: _hairline(context),
        boxShadow: _floatShadow(
          context,
          lift: _pressed ? widget.lift * 0.3 : widget.lift,
          tint: widget.shadowTint,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kRadius - 1),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );

    if (widget.onTap == null) return card;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
          style: TextStyles.sectionLabel(context).copyWith(letterSpacing: 1.2),
        ),
        const Spacer(),
        if (action != null)
          InkWell(
            onTap: action!.onTap,
            borderRadius: BorderRadius.circular(RadiusAmiin.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: Spacing.xs),
              child: Text(
                '${action!.label} ›',
                style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: modeColor),
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
  final IconData icon;
  final Color accent;
  final Color bg;
  final Color text;
  const _QuickTile({required this.label, required this.tab, required this.icon, required this.accent, required this.bg, required this.text});
}

class _QuickTilesGrid extends StatelessWidget {
  final List<_QuickTile> tiles;
  const _QuickTilesGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(child: _QuickTileCard(tile: tiles[row * 2])),
              const SizedBox(width: Spacing.md),
              Expanded(child: _QuickTileCard(tile: tiles[row * 2 + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tuile teintée qui flotte : ombre colorée de son accent et pastille
/// d'icône blanche en relief.
class _QuickTileCard extends StatelessWidget {
  final _QuickTile tile;
  const _QuickTileCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    final dark = context.ac.brightness == Brightness.dark;
    return _FloatingCard(
      color: tile.bg,
      shadowTint: tile.accent,
      lift: 0.45,
      padding: const EdgeInsets.all(Spacing.md),
      onTap: () => context.go('/${tile.tab}'),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: tile.accent.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(tile.icon, size: 18, color: tile.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tile.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.cardTitle(context).copyWith(fontSize: 14, color: tile.text, fontFamily: FontFamily.geoBold),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: tile.text.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final String title;
  final String when;
  final Color dotColor;
  final bool byAgent;
  final VoidCallback onTap;

  const _EventRow({
    required this.title,
    required this.when,
    required this.dotColor,
    required this.byAgent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 14, Spacing.md, 14),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.45), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: Spacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyles.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(when, style: TextStyles.caption(context)),
                ],
              ),
            ),
            if (byAgent) _AgentBadge(color: ac.secretariatAccent),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: ac.muted.withValues(alpha: 0.6)),
          ],
        ),
      ),
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
      child: Text('Amiin', style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: color, letterSpacing: 0.5, fontFamily: FontFamily.geoBold)),
    );
  }
}

// ── Carte « Aujourd'hui » : météo, prochaine prière, taux FDJ ────────────────
// Flotte à cheval sur le bandeau ; uniquement les tuiles dont la donnée
// existe, et rien du tout si le brief est vide ou indisponible.

class _DailyBriefCard extends StatelessWidget {
  final HomeBrief brief;

  const _DailyBriefCard({required this.brief});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final tiles = <Widget>[];

    final weather = brief.weather;
    if (weather != null) {
      tiles.add(_BriefTile(
        icon: Icons.wb_sunny_outlined,
        value: '${weather.temp}°',
        label: weather.desc,
      ));
    }

    final prayers = brief.prayers;
    if (prayers != null) {
      final (name, time) = prayers.next(DateTime.now());
      tiles.add(_BriefTile(
        icon: Icons.mosque_outlined,
        value: time,
        label: name,
      ));
    }

    final fx = brief.fx;
    if (fx != null) {
      final eur = fx.eurFdj;
      tiles.add(_BriefTile(
        icon: Icons.currency_exchange_outlined,
        value: eur != null ? '${eur.round()} FDJ' : '${fx.usdFdj.round()} FDJ',
        label: eur != null ? '1 euro' : '1 dollar',
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    // Intercale un séparateur vertical entre les tuiles
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        children.add(Container(width: 0.5, height: 32, color: ac.border));
      }
      children.add(Expanded(child: tiles[i]));
    }

    return _FloatingCard(
      lift: 1,
      padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.md, Spacing.sm, Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Spacing.sm, bottom: Spacing.md),
            child: Text(
              "AUJOURD'HUI",
              style: TextStyles.sectionLabel(context).copyWith(letterSpacing: 1.2, color: ac.infoAccent),
            ),
          ),
          Row(children: children),
        ],
      ),
    );
  }
}

class _BriefTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _BriefTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: ac.infoAccent),
        const SizedBox(width: Spacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.cardTitle(context).copyWith(fontFamily: FontFamily.geoBold, fontSize: 15)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.caption(context).copyWith(fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }
}
