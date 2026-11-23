// ─── HomeScreen ──────────────────────────────────────────────────────────────
//
// Refonte « épurée » : grand titre, beaucoup d'air, cartes arrondies sans
// ombre posées sur le fond sable, une seule couleur d'action par zone
// (turquoise = secrétariat, ocre = information). Une barre translucide
// floutée apparaît en haut quand le grand titre sort de l'écran.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/agenda_service.dart';
import '../../services/chat_controller.dart';
import '../../services/home_brief_service.dart';
import '../../services/notes_service.dart';
import '../../theme/spacing.dart';
import '../../theme/themes.dart';
import '../../theme/typography.dart';
import '../../widgets/amiin_logo.dart';
import '../../widgets/amiin_svg_icons.dart';

/// Rayon commun des cartes de l'accueil.
const double _kCardRadius = 22;

/// Marge latérale de l'écran.
const double _kGutter = Spacing.xl;

/// Espace vertical entre deux sections.
const double _kSectionGap = 36;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();
  final _compactBar = ValueNotifier<bool>(false);

  List<AmiinEvent> _events = [];
  List<AmiinNote> _notes = [];

  /// Suggestions : (libellé court affiché, question envoyée à Amiin).
  static const _suggestions = [
    ('Passeport', 'Comment renouveler mon passeport ?'),
    ('Horaires CNSS', 'Quels sont les horaires de la CNSS ?'),
    ('Carte grise', 'Comment obtenir une carte grise ?'),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadData();
    homeBriefService.refresh();
    agendaService.listenable.addListener(_loadData);
    notesService.listenable.addListener(_loadData);
  }

  @override
  void dispose() {
    agendaService.listenable.removeListener(_loadData);
    notesService.listenable.removeListener(_loadData);
    _scroll.dispose();
    _compactBar.dispose();
    super.dispose();
  }

  void _onScroll() => _compactBar.value = _scroll.offset > 64;

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
        _notes = (results[1] as List<AmiinNote>).take(6).toList();
      });
    } catch (_) {}
  }

  Future<void> _onRefresh() =>
      Future.wait([_loadData(), homeBriefService.refresh(force: true)]);

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
  }

  String get _dateLine =>
      DateFormat('EEEE d MMMM', 'fr').format(DateTime.now()).toUpperCase();

  void _ask(String question) {
    HapticFeedback.selectionClick();
    context.read<ChatController>().sendMessage(question);
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final insets = MediaQuery.of(context).padding;

    final sections = <Widget>[
      // ── Grand titre ─────────────────────────────────────────────────────
      _LargeTitle(
        overline: _dateLine,
        title: _greeting,
        onSettings: () => context.push('/settings'),
      ),
      const SizedBox(height: Spacing.xxl),

      // ── Carte « Demandez à Amiin » ──────────────────────────────────────
      _AskCard(
        suggestions: _suggestions,
        onAsk: _ask,
        onOpenChat: () => context.go('/chat'),
        onMic: () {
          chatListenRequest.value++;
          context.go('/chat');
        },
      ),

      // ── Aujourd'hui ─────────────────────────────────────────────────────
      ValueListenableBuilder<HomeBrief?>(
        valueListenable: homeBriefService.brief,
        builder: (context, brief, _) {
          if (brief == null || brief.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: _kSectionGap),
            child: _BriefSection(brief: brief),
          );
        },
      ),

      // ── Raccourcis ──────────────────────────────────────────────────────
      const SizedBox(height: _kSectionGap),
      const _SectionHeader(title: 'Raccourcis'),
      const SizedBox(height: Spacing.md),
      _ShortcutGrid(eventCount: _events.length, noteCount: _notes.length),

      // ── Cette semaine ───────────────────────────────────────────────────
      if (_events.isNotEmpty) ...[
        const SizedBox(height: _kSectionGap),
        _SectionHeader(
          title: 'Cette semaine',
          actionLabel: 'Agenda',
          actionColor: ac.secretariatAccent,
          onAction: () => context.go('/agenda'),
        ),
        const SizedBox(height: Spacing.md),
        _EventList(events: _events),
      ],

      // ── Notes récentes ──────────────────────────────────────────────────
      if (_notes.isNotEmpty) ...[
        const SizedBox(height: _kSectionGap),
        _SectionHeader(
          title: 'Notes récentes',
          actionLabel: 'Tout voir',
          actionColor: ac.secretariatAccent,
          onAction: () => context.go('/notes'),
        ),
        const SizedBox(height: Spacing.md),
      ],
    ];

    return Scaffold(
      backgroundColor: ac.background,
      body: Stack(
        children: [
          RefreshIndicator(
            color: ac.secretariatAccent,
            backgroundColor: ac.surface,
            edgeOffset: insets.top,
            onRefresh: _onRefresh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      _kGutter, insets.top + Spacing.lg, _kGutter, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      for (var i = 0; i < sections.length; i++)
                        _Reveal(index: i, child: sections[i]),
                    ]),
                  ),
                ),
                // Le carrousel de notes déborde volontairement des marges.
                if (_notes.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _Reveal(
                      index: sections.length,
                      child: _NotesCarousel(notes: _notes),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: Spacing.huge * 2)),
              ],
            ),
          ),

          // ── Barre compacte translucide (apparaît au défilement) ───────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _compactBar,
              builder: (context, visible, _) => IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _CompactBar(
                    title: _greeting,
                    topInset: insets.top,
                    onSettings: () => context.push('/settings'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Apparition douce : fondu + légère montée, décalée par section ─────────────
// Désactivée si l'utilisateur a demandé de réduire les animations.

class _Reveal extends StatelessWidget {
  final int index;
  final Widget child;

  const _Reveal({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + 50 * index.clamp(0, 8)),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

// ── Grand titre ───────────────────────────────────────────────────────────────

class _LargeTitle extends StatelessWidget {
  final String overline;
  final String title;
  final VoidCallback onSettings;

  const _LargeTitle({
    required this.overline,
    required this.title,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overline,
                style: TextStyles.sectionLabel(context).copyWith(
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: ac.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyles.displayTitle(context).copyWith(
                  fontSize: 34,
                  letterSpacing: -0.9,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        _CircleButton(
          onTap: onSettings,
          semanticLabel: 'Réglages',
          child: const AmiinLogo(size: 22),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color? color;

  const _CircleButton({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: color ?? context.ac.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Center(child: child)),
        ),
      ),
    );
  }
}

// ── Barre compacte floutée ────────────────────────────────────────────────────

class _CompactBar extends StatelessWidget {
  final String title;
  final double topInset;
  final VoidCallback onSettings;

  const _CompactBar({
    required this.title,
    required this.topInset,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: topInset),
          decoration: BoxDecoration(
            color: ac.background.withValues(alpha: 0.78),
            border: Border(
              bottom: BorderSide(color: ac.border.withValues(alpha: 0.6), width: 0.5),
            ),
          ),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(title, style: TextStyles.screenTitle(context).copyWith(fontSize: 17)),
                Positioned(
                  right: _kGutter - 6,
                  child: _CircleButton(
                    onTap: onSettings,
                    semanticLabel: 'Réglages',
                    size: 32,
                    color: Colors.transparent,
                    child: const AmiinLogo(size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Carte « Demandez à Amiin » ────────────────────────────────────────────────

class _AskCard extends StatelessWidget {
  final List<(String, String)> suggestions;
  final ValueChanged<String> onAsk;
  final VoidCallback onOpenChat;
  final VoidCallback onMic;

  const _AskCard({
    required this.suggestions,
    required this.onAsk,
    required this.onOpenChat,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Container(
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(_kCardRadius),
      ),
      padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Que puis-je faire\npour vous ?',
            style: TextStyles.displayTitle(context).copyWith(
              fontSize: 24,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Démarches, annuaire, agenda : posez votre question, Amiin s\'occupe du reste.',
            style: TextStyles.bodyMuted(context).copyWith(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: Spacing.lg),

          // Champ + micro
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Écrire une question à Amiin',
                  child: Material(
                    color: ac.background,
                    borderRadius: BorderRadius.circular(RadiusAmiin.full),
                    child: InkWell(
                      onTap: onOpenChat,
                      borderRadius: BorderRadius.circular(RadiusAmiin.full),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 20, color: ac.muted),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'Écrivez votre question…',
                              style: TextStyles.body(context)
                                  .copyWith(fontSize: 15, color: ac.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              _CircleButton(
                onTap: onMic,
                semanticLabel: 'Parler à Amiin',
                size: 48,
                color: ac.secretariatAccent,
                child: SvgPicture.string(AmiinSvgIcons.mic, width: 18, height: 21),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // Suggestions
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final (label, question) in suggestions)
                _SuggestionChip(label: label, onTap: () => onAsk(question)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Material(
      color: ac.secretariatAccentLight,
      borderRadius: BorderRadius.circular(RadiusAmiin.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusAmiin.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
              label,
              style: TextStyles.cardTitle(context).copyWith(
                fontSize: 13,
                color: ac.secretariatAccentDark,
              ),
          ),
        ),
      ),
    );
  }
}

// ── En-tête de section : titre en casse normale + lien « › » ─────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final Color? actionColor;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.actionColor,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyles.displayTitle(context).copyWith(
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(RadiusAmiin.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '$actionLabel ›',
                style: TextStyles.cardTitle(context).copyWith(
                  fontSize: 15,
                  color: actionColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Aujourd'hui : trois tuiles, chiffres en grand ─────────────────────────────

class _BriefSection extends StatelessWidget {
  final HomeBrief brief;

  const _BriefSection({required this.brief});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];

    final weather = brief.weather;
    if (weather != null) {
      tiles.add(_BriefTile(
        icon: Icons.wb_sunny_rounded,
        value: '${weather.temp}°',
        label: weather.desc,
      ));
    }

    final prayers = brief.prayers;
    if (prayers != null) {
      final (name, time) = prayers.next(DateTime.now());
      tiles.add(_BriefTile(icon: Icons.mosque_rounded, value: time, label: name));
    }

    final fx = brief.fx;
    if (fx != null) {
      final eur = fx.eurFdj;
      tiles.add(_BriefTile(
        icon: Icons.currency_exchange_rounded,
        value: (eur ?? fx.usdFdj).round().toString(),
        label: eur != null ? 'FDJ pour 1 €' : 'FDJ pour 1 \$',
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: "Aujourd'hui"),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: Spacing.sm),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(_kCardRadius - 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ac.infoAccent),
          const SizedBox(height: Spacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyles.displayTitle(context).copyWith(
                fontSize: 24,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.caption(context),
          ),
        ],
      ),
    );
  }
}

// ── Raccourcis : grille 2 × 2, icône dans un carré arrondi coloré ─────────────

class _ShortcutGrid extends StatelessWidget {
  final int eventCount;
  final int noteCount;

  const _ShortcutGrid({required this.eventCount, required this.noteCount});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final tiles = [
      _Shortcut(
        icon: Icons.calendar_today_rounded,
        label: 'Agenda',
        detail: eventCount == 0
            ? 'Rien cette semaine'
            : '$eventCount à venir',
        accent: ac.secretariatAccent,
        accentLight: ac.secretariatAccentLight,
        route: '/agenda',
      ),
      _Shortcut(
        icon: Icons.edit_note_rounded,
        label: 'Notes',
        detail: noteCount == 0 ? 'Aucune note' : 'Vos notes récentes',
        accent: ac.secretariatAccent,
        accentLight: ac.secretariatAccentLight,
        route: '/notes',
      ),
      _Shortcut(
        icon: Icons.people_rounded,
        label: 'Annuaire',
        detail: 'Services publics',
        accent: ac.infoAccent,
        accentLight: ac.infoAccentLight,
        route: '/annuaire',
      ),
      _Shortcut(
        icon: Icons.assignment_rounded,
        label: 'Démarches',
        detail: 'Guides et suivi',
        accent: ac.infoAccent,
        accentLight: ac.infoAccentLight,
        route: '/demarches',
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(child: _ShortcutTile(data: tiles[row * 2])),
              const SizedBox(width: Spacing.sm),
              Expanded(child: _ShortcutTile(data: tiles[row * 2 + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

class _Shortcut {
  final IconData icon;
  final String label;
  final String detail;
  final Color accent;
  final Color accentLight;
  final String route;

  const _Shortcut({
    required this.icon,
    required this.label,
    required this.detail,
    required this.accent,
    required this.accentLight,
    required this.route,
  });
}

class _ShortcutTile extends StatefulWidget {
  final _Shortcut data;

  const _ShortcutTile({required this.data});

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final d = widget.data;
    return Semantics(
      button: true,
      label: '${d.label}, ${d.detail}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          context.go(d.route);
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: ac.surface,
              borderRadius: BorderRadius.circular(_kCardRadius - 4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: d.accentLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(d.icon, size: 19, color: d.accent),
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  d.label,
                  style: TextStyles.screenTitle(context).copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  d.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.caption(context).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cette semaine : liste groupée dans une seule carte ───────────────────────

class _EventList extends StatelessWidget {
  final List<AmiinEvent> events;

  const _EventList({required this.events});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kCardRadius - 4),
      child: Material(
        color: ac.surface,
        child: Column(
          children: [
            for (var i = 0; i < events.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Divider(height: 0.5, thickness: 0.5, color: ac.border),
                ),
              _EventRow(event: events[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final AmiinEvent event;

  const _EventRow({required this.event});

  String _timeLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final hour = DateFormat('HH:mm').format(date);
    if (day == today) return "Aujourd'hui · $hour";
    if (day == today.add(const Duration(days: 1))) return 'Demain · $hour';
    return '${DateFormat('EEEE', 'fr').format(date)} · $hour';
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final date = DateTime.parse(event.startDate);
    return InkWell(
      onTap: () => context.push('/agenda/event/${event.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        child: Row(
          children: [
            // Pavé date
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM', 'fr').format(date).replaceAll('.', '').toUpperCase(),
                    style: TextStyles.sectionLabel(context).copyWith(
                      fontSize: 10,
                      color: ac.secretariatAccent,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    '${date.day}',
                    style: TextStyles.displayTitle(context).copyWith(
                      fontSize: 22,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.cardTitle(context).copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(_timeLabel(date), style: TextStyles.caption(context).copyWith(fontSize: 13)),
                ],
              ),
            ),
            if (event.createdByAgent == true) ...[
              const SizedBox(width: Spacing.sm),
              Icon(Icons.auto_awesome_rounded, size: 15, color: ac.secretariatAccent),
            ],
            const SizedBox(width: Spacing.sm),
            Icon(Icons.chevron_right_rounded, size: 20, color: ac.muted.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ── Notes récentes : carrousel horizontal ────────────────────────────────────

class _NotesCarousel extends StatelessWidget {
  final List<AmiinNote> notes;

  const _NotesCarousel({required this.notes});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kGutter),
        physics: const BouncingScrollPhysics(),
        itemCount: notes.length,
        separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, i) {
          final note = notes[i];
          return SizedBox(
            width: 232,
            child: Material(
              color: ac.surface,
              borderRadius: BorderRadius.circular(_kCardRadius - 4),
              child: InkWell(
                onTap: () => context.push('/notes/${note.id}'),
                borderRadius: BorderRadius.circular(_kCardRadius - 4),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.screenTitle(context).copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          note.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.bodyMuted(context).copyWith(fontSize: 13, height: 1.4),
                        ),
                      ),
                      Text(
                        DateFormat('d MMM', 'fr').format(DateTime.parse(note.updatedAt)),
                        style: TextStyles.caption(context).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
