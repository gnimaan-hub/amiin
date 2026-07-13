// ─── AgendaScreen (avec bouton Créer sous le calendrier) ────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/colors.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../../services/agenda_service.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

enum _AgendaView { month, week }

class _AgendaScreenState extends State<AgendaScreen> {
  _AgendaView _view = _AgendaView.month;
  DateTime _currentDate = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<AmiinEvent> _events = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    // Réactivité Hive : un événement créé/modifié ailleurs (chat Amiin,
    // écran de création…) rafraîchit automatiquement le calendrier.
    agendaService.listenable.addListener(_refreshEvents);
  }

  @override
  void dispose() {
    agendaService.listenable.removeListener(_refreshEvents);
    super.dispose();
  }

  /// Lundi de la semaine contenant [d].
  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// Les 7 jours de la semaine affichée.
  List<DateTime> _weekDays() {
    final monday = _mondayOf(_currentDate);
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  ({DateTime from, DateTime to}) _visibleRange() {
    if (_view == _AgendaView.week) {
      final monday = _mondayOf(_currentDate);
      return (
        from: monday,
        to: monday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59)),
      );
    }
    return (
      from: DateTime(_currentDate.year, _currentDate.month, 1),
      to: DateTime(_currentDate.year, _currentDate.month + 1, 0, 23, 59, 59),
    );
  }

  Future<void> _loadEvents() async {
    if (_refreshing) return;
    setState(() => _loading = true);
    try {
      final range = _visibleRange();
      final from = range.from;
      final to = range.to;
      final events = await agendaService.getEvents(
        from.toIso8601String(),
        to.toIso8601String(),
      );
      if (mounted) {
        setState(() => _events = events);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Impossible de charger les événements');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshEvents() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final range = _visibleRange();
      final from = range.from;
      final to = range.to;
      final events = await agendaService.getEvents(
        from.toIso8601String(),
        to.toIso8601String(),
      );
      if (mounted) {
        setState(() => _events = events);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Impossible de rafraîchir');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.ac.secretariatAccent),
    );
  }

  List<DateTime> _getDaysInMonth() {
    final first = DateTime(_currentDate.year, _currentDate.month, 1);
    final last = DateTime(_currentDate.year, _currentDate.month + 1, 0);
    return List.generate(last.day, (i) => first.add(Duration(days: i)));
  }

  /// Un événement apparaît sur chaque jour qu'il couvre (multi-jours inclus).
  List<AmiinEvent> _eventsForDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _events.where((e) {
      final start = DateTime.parse(e.startDate);
      DateTime end;
      try {
        end = DateTime.parse(e.endDate);
      } catch (_) {
        end = start;
      }
      if (end.isBefore(start)) end = start;
      return start.isBefore(dayEnd) && !end.isBefore(dayStart);
    }).toList();
  }

  Color _categoryColor(EventCategory category) {
    switch (category) {
      case EventCategory.admin:
        return context.ac.secretariatAccent;
      case EventCategory.personal:
        return context.ac.success;
      case EventCategory.health:
        return context.ac.infoAccent;
      case EventCategory.education:
        return CategoryColors.education;
      default:
        return context.ac.muted;
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentDate =
          DateTime(_currentDate.year, _currentDate.month + delta, 1);
      // Garder un jour sélectionné cohérent avec le mois affiché :
      // aujourd'hui si on revient au mois courant, sinon le 1er du mois.
      final now = DateTime.now();
      _selectedDay = (_currentDate.year == now.year &&
              _currentDate.month == now.month)
          ? now
          : _currentDate;
    });
    _loadEvents();
  }

  void _goToPreviousMonth() => _changeMonth(-1);

  void _goToNextMonth() => _changeMonth(1);

  void _changeWeek(int delta) {
    setState(() {
      _currentDate = _currentDate.add(Duration(days: 7 * delta));
      final days = _weekDays();
      final now = DateTime.now();
      _selectedDay = days.any((d) => _isSameDay(d, now)) ? now : days.first;
    });
    _loadEvents();
  }

  void _goToPrevious() =>
      _view == _AgendaView.month ? _changeMonth(-1) : _changeWeek(-1);

  void _goToNext() =>
      _view == _AgendaView.month ? _changeMonth(1) : _changeWeek(1);

  void _switchView(_AgendaView v) {
    if (v == _view) return;
    setState(() {
      _view = v;
      // Recentre sur le jour sélectionné pour une transition naturelle.
      _currentDate = _selectedDay;
    });
    _loadEvents();
  }

  String _navLabel() {
    if (_view == _AgendaView.month) {
      return DateFormat('MMMM yyyy', 'fr').format(_currentDate);
    }
    final days = _weekDays();
    final first = days.first;
    final last = days.last;
    if (first.month == last.month) {
      return '${first.day} – ${DateFormat('d MMM yyyy', 'fr').format(last)}';
    }
    return '${DateFormat('d MMM', 'fr').format(first)} – ${DateFormat('d MMM yyyy', 'fr').format(last)}';
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final firstWeekday = DateTime(_currentDate.year, _currentDate.month, 1).weekday;
    final leadingEmpty = (firstWeekday - 1) % 7;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: 'Agenda',
              rightAction: IconButton(
                icon: SvgPicture.string(_plusSvg, width: 22, height: 22),
                onPressed: () async {
                  await context.push('/agenda/create');
                  _refreshEvents();
                },
              ),
            ),
            // Navigation période + bascule Mois/Semaine
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl, vertical: Spacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: SvgPicture.string(_chevronLeftSvg, width: 20, height: 20),
                    onPressed: _goToPrevious,
                  ),
                  Expanded(
                    child: Text(
                      _navLabel(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FontFamily.geo,
                        fontSize: 17,
                        color: context.ac.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: SvgPicture.string(_chevronRightSvg, width: 20, height: 20),
                    onPressed: _goToNext,
                  ),
                ],
              ),
            ),
            _ViewToggle(view: _view, onChanged: _switchView),
            const SizedBox(height: Spacing.sm),
            // Weekday headers (vue mensuelle uniquement)
            if (_view == _AgendaView.month)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: Row(
                children: ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di']
                    .map((d) => Expanded(
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: FontFamily.geoBold,
                              fontSize: 10,
                              color: context.ac.muted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 4),
            // Bande hebdomadaire (vue semaine)
            if (_view == _AgendaView.week)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Row(
                  children: [
                    for (final day in _weekDays())
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDay = day),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _isSameDay(day, _selectedDay)
                                  ? context.ac.secretariatAccent
                                  : _isToday(day)
                                      ? context.ac.secretariatAccentLight
                                      : null,
                              borderRadius: BorderRadius.circular(RadiusAmiin.md),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  ['LU', 'MA', 'ME', 'JE', 'VE', 'SA', 'DI']
                                      [day.weekday - 1],
                                  style: TextStyle(
                                    fontFamily: FontFamily.geoBold,
                                    fontSize: 9,
                                    letterSpacing: 0.5,
                                    color: _isSameDay(day, _selectedDay)
                                        ? context.ac.onAccent.withValues(alpha: 0.8)
                                        : context.ac.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  day.day.toString(),
                                  style: TextStyle(
                                    fontFamily: FontFamily.geoMedium,
                                    fontSize: 15,
                                    color: _isSameDay(day, _selectedDay)
                                        ? context.ac.onAccent
                                        : _isToday(day)
                                            ? context.ac.secretariatAccent
                                            : context.ac.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: _eventsForDay(day)
                                      .take(3)
                                      .map((e) => Container(
                                            width: 4,
                                            height: 4,
                                            margin: const EdgeInsets
                                                .symmetric(horizontal: 1),
                                            decoration: BoxDecoration(
                                              color: _isSameDay(day, _selectedDay)
                                                  ? context.ac.onAccent
                                                  : _categoryColor(e.category),
                                              shape: BoxShape.circle,
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Calendar grid (vue mensuelle)
            if (_view == _AgendaView.month)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                childAspectRatio: 1,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (int i = 0; i < leadingEmpty; i++) const SizedBox(),
                  for (var day in days)
                    GestureDetector(
                      onTap: () => setState(() => _selectedDay = day),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isSameDay(day, _selectedDay)
                              ? context.ac.secretariatAccent
                              : _isToday(day)
                                  ? context.ac.secretariatAccentLight
                                  : null,
                          borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              day.day.toString(),
                              style: TextStyle(
                                fontFamily: FontFamily.geoMedium,
                                fontSize: 13,
                                color: _isSameDay(day, _selectedDay)
                                    ? context.ac.onAccent
                                    : _isToday(day)
                                        ? context.ac.secretariatAccent
                                        : context.ac.ink,
                              ),
                            ),
                            if (_eventsForDay(day).isNotEmpty)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: _eventsForDay(day)
                                    .take(3)
                                    .map((e) => Container(
                                          width: 4,
                                          height: 4,
                                          margin: const EdgeInsets.symmetric(horizontal: 1),
                                          decoration: BoxDecoration(
                                            color: _categoryColor(e.category),
                                            shape: BoxShape.circle,
                                          ),
                                        ))
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Selected day events with pull-to-refresh
            Expanded(
              child: _buildSelectedDayEvents(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDayEvents() {
    final events = _eventsForDay(_selectedDay);
    if (_loading && !_refreshing) {
      return const SkeletonList(count: 4);
    }
    return RefreshIndicator(
      onRefresh: _refreshEvents,
      color: context.ac.secretariatAccent,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isToday(_selectedDay)
                        ? "Aujourd'hui"
                        : DateFormat('EEEE d MMMM', 'fr').format(_selectedDay),
                    style: TextStyle(
                      fontFamily: FontFamily.geo,
                      fontSize: 16,
                      color: context.ac.ink,
                    ),
                  ),
                  // Bouton Créer à côté de la date sélectionnée
                  ElevatedButton.icon(
                    onPressed: () async {
                      final dateStr = _selectedDay.toIso8601String().split('T').first;
                      await context.push('/agenda/create?date=$dateStr');
                      _refreshEvents();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Créer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.ac.secretariatAccent,
                      foregroundColor: context.ac.onAccent,
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (events.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Center(
                  child: Text(
                    'Aucun événement ce jour.',
                    style: TextStyle(
                      fontFamily: FontFamily.sans,
                      fontSize: 13,
                      color: context.ac.muted,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ev = events[index];
                  final start = DateTime.parse(ev.startDate);
                  final end = DateTime.parse(ev.endDate);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: 4),
                    child: Dismissible(
                      key: ValueKey(ev.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        decoration: BoxDecoration(
                          color: context.ac.alertColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                      ),
                      // Confirmation avant suppression — cohérent avec les
                      // notes : un événement effacé est irrécupérable.
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Supprimer'),
                                content:
                                    Text('Supprimer « ${ev.title} » ?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, false),
                                    child: const Text('Annuler'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    child: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) async {
                        setState(() => _events.removeWhere((e) => e.id == ev.id));
                        try {
                          await agendaService.deleteEvent(ev.id);
                          if (!mounted) return;
                          AmiinToast.show(this.context, 'Événement supprimé');
                        } catch (_) {
                          if (!mounted) return;
                          AmiinToast.show(this.context, 'Impossible de supprimer', success: false);
                          _loadEvents();
                        }
                      },
                      child: GestureDetector(
                      onTap: () async {
                        await context.push('/agenda/event/${ev.id}');
                        _refreshEvents();
                      },
                      child: AmiinCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 3,
                              decoration: BoxDecoration(
                                color: _categoryColor(ev.category),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: Spacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ev.title,
                                    style: TextStyle(
                                      fontFamily: FontFamily.geoMedium,
                                      fontSize: 14,
                                      color: context.ac.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}',
                                    style: TextStyle(
                                      fontFamily: FontFamily.sans,
                                      fontSize: 12,
                                      color: context.ac.muted,
                                    ),
                                  ),
                                  if (ev.location != null)
                                    Text(
                                      ev.location!,
                                      style: TextStyle(
                                        fontFamily: FontFamily.sans,
                                        fontSize: 12,
                                        color: context.ac.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (ev.createdByAgent == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.ac.secretariatAccentLight,
                                  borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                                ),
                                child: Text(
                                  'Amiin',
                                  style: TextStyle(
                                    fontFamily: FontFamily.geoBold,
                                    fontSize: 10,
                                    color: context.ac.secretariatAccentDark,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                      ),
                  );
                },
                childCount: events.length,
              ),
            ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  static const String _plusSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M11 4v14M4 11h14" stroke="#1E8A8A" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ''';
  static const String _chevronLeftSvg = '''
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M13 4L7 10l6 6" stroke="#7A6A5E" stroke-width="1.6" stroke-linecap="round"/>
    </svg>
  ''';
  static const String _chevronRightSvg = '''
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M7 4l6 6-6 6" stroke="#7A6A5E" stroke-width="1.6" stroke-linecap="round"/>
    </svg>
  ''';
}

// ── Bascule Mois / Semaine ────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final _AgendaView view;
  final ValueChanged<_AgendaView> onChanged;

  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;

    Widget segment(String label, _AgendaView v) {
      final selected = view == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? ac.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(RadiusAmiin.sm),
              boxShadow: selected ? ShadowAmiin.sm : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: selected ? FontFamily.geoBold : FontFamily.geoMedium,
                fontSize: 12,
                color: selected ? ac.secretariatAccent : ac.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ac.surface2,
          borderRadius: BorderRadius.circular(RadiusAmiin.md),
        ),
        child: Row(
          children: [
            segment('Mois', _AgendaView.month),
            segment('Semaine', _AgendaView.week),
          ],
        ),
      ),
    );
  }
}
