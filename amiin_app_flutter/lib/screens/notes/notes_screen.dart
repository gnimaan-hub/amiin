// ─── NotesScreen ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/card.dart';
import '../../widgets/tag.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../../services/notes_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<AmiinNote> _notes = [];
  List<String> _allTags = [];
  String _query = '';
  String? _activeTag;
  bool _loading = true;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
    // Réactivité Hive : une note créée/modifiée ailleurs (chat Amiin…)
    // rafraîchit automatiquement la liste.
    notesService.listenable.addListener(_onBoxChanged);
  }

  @override
  void dispose() {
    notesService.listenable.removeListener(_onBoxChanged);
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onBoxChanged() {
    if (mounted) _loadData();
  }

  void _onScroll() {
    final show = _scrollController.offset > 200;
    if (show != _showBackToTop) setState(() => _showBackToTop = show);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadData() async {
    // Skeleton seulement au premier chargement — pas de flash lors des
    // rafraîchissements réactifs (box Hive) ou des recherches.
    if (_notes.isEmpty) setState(() => _loading = true);
    try {
      final notesFuture = notesService.getNotes(
          query: _query.isEmpty ? null : _query, tag: _activeTag);
      final tagsFuture = notesService.getTags();
      final results = await Future.wait([notesFuture, tagsFuture]);
      if (!mounted) return;
      setState(() {
        _notes = results[0] as List<AmiinNote>;
        _allTags = results[1] as List<String>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String text) {
    _query = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadData);
  }

  void _onTagTap(String tag) {
    setState(() => _activeTag = _activeTag == tag ? null : tag);
    _loadData();
  }

  Future<void> _deleteNote(AmiinNote note) async {
    // Retrait optimiste
    setState(() => _notes.removeWhere((n) => n.id == note.id));
    try {
      await notesService.deleteNote(note.id);
      if (mounted) AmiinToast.show(context, 'Note supprimée');
    } catch (_) {
      // Restaurer si erreur
      setState(() => _notes.insert(0, note));
      if (mounted) AmiinToast.show(context, 'Impossible de supprimer', success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: 'Notes',
              rightAction: IconButton(
                icon: SvgPicture.string(_plusSvg, width: 22, height: 22),
                onPressed: () =>
                    context.push('/notes/create').then((_) => _loadData()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: AmiinSearchBar(
                value: _query,
                onChanged: _onSearch,
                hintText: 'Rechercher une note…',
              ),
            ),
            if (_allTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: _allTags
                      .map((tag) => GestureDetector(
                            onTap: () => _onTagTap(tag),
                            child: AmiinTag(
                              label: tag,
                              variant: _activeTag == tag
                                  ? TagVariant.terra
                                  : TagVariant.default_,
                            ),
                          ))
                      .toList(),
                ),
              ),
            Expanded(
              child: _loading
                  ? const SkeletonList()
                  : _notes.isEmpty
                      ? const EmptyState(
                          title: 'Aucune note',
                          subtitle:
                              'Appuyez sur + pour créer votre première note.')
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: ColorsAmiin.terra,
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(Spacing.lg),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _notes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: Spacing.sm),
                            itemBuilder: (context, index) {
                              final note = _notes[index];
                              return Dismissible(
                                key: ValueKey(note.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.white, size: 22),
                                ),
                                confirmDismiss: (_) async {
                                  return await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) => AlertDialog(
                                          title: const Text('Supprimer'),
                                          content: Text(
                                              'Supprimer « ${note.title} » ?'),
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
                                                  foregroundColor:
                                                      Colors.red),
                                              child:
                                                  const Text('Supprimer'),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                },
                                onDismissed: (_) => _deleteNote(note),
                                child: GestureDetector(
                                  onTap: () => context
                                      .push('/notes/${note.id}')
                                      .then((_) => _loadData()),
                                  child: AmiinCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                note.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily:
                                                      FontFamily.sansBold,
                                                  fontSize: 15,
                                                  color: ColorsAmiin.ink,
                                                ),
                                              ),
                                            ),
                                            if (note.isPinned == true) ...[
                                              const SizedBox(
                                                  width: Spacing.sm),
                                              const Text('📌',
                                                  style: TextStyle(
                                                      fontSize: 13)),
                                            ],
                                            if (note.createdByAgent ==
                                                true) ...[
                                              const SizedBox(
                                                  width: Spacing.sm),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: ColorsAmiin.terraLt,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          RadiusAmiin.sm),
                                                ),
                                                child: Text(
                                                  'Amiin',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        FontFamily.sansBold,
                                                    fontSize: 10,
                                                    color:
                                                        ColorsAmiin.terraDk,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          note.content,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: FontFamily.sans,
                                            fontSize: 13,
                                            color: ColorsAmiin.mid,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              DateFormat('d MMM', 'fr').format(
                                                  DateTime.parse(
                                                      note.updatedAt)),
                                              style: TextStyle(
                                                fontFamily: FontFamily.sans,
                                                fontSize: 11,
                                                color: ColorsAmiin.muted,
                                              ),
                                            ),
                                            if (note.tags.isNotEmpty)
                                              Wrap(
                                                spacing: 4,
                                                children: note.tags
                                                    .take(3)
                                                    .map((t) => AmiinTag(
                                                        label: t,
                                                        variant: TagVariant
                                                            .default_))
                                                    .toList(),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _showBackToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton.small(
              heroTag: 'notesScrollTop',
              onPressed: _scrollToTop,
              backgroundColor: ColorsAmiin.white,
              foregroundColor: ColorsAmiin.terra,
              elevation: 2,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'notesCreate',
            onPressed: () =>
                context.push('/notes/create').then((_) => _loadData()),
            backgroundColor: ColorsAmiin.terra,
            child: const Icon(Icons.add, color: ColorsAmiin.white),
          ),
        ],
      ),
    );
  }

  static const String _plusSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M11 4v14M4 11h14" stroke="#B85530" stroke-width="2" stroke-linecap="round"/>
    </svg>
  ''';
}
