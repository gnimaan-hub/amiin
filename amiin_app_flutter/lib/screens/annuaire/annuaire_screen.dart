// ─── AnnuaireScreen ───────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/amiin_svg_icons.dart';
import '../../widgets/horizon_line.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../theme/colors.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/search_bar.dart' as amiin;
import '../../widgets/card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../services/annuaire_service.dart';

// ── Mapping catégorie → couleur + emoji ──────────────────────────────────────

const Map<String, String> _catEmoji = {
  'Alimentation & Restauration':               '🍽️',
  'Hébergement':                               '🏨',
  'Santé':                                     '🏥',
  'Commerce & Courses':                        '🛒',
  'Transport & Logistique':                    '🚛',
  'Éducation & Formation':                     '🎓',
  'Administration & Services publics':         '🏛️',
  'Services financiers & juridiques':          '⚖️',
  'Culture & Culte':                           '🕌',
  'Tourisme & Loisirs':                        '🌊',
  'Services automobile':                       '🚗',
  'Services à la personne':                    '💈',
  'Géographie & Patrimoine naturel':           '🗺️',
  'Diplomatie & Organisations internationales':'🌐',
  'Industrie, Énergie & Grandes entreprises':  '⚙️',
  'Télécom & Tech':                            '📡',
  'Associations & ONG':                        '🤝',
  'Défense internationale':                    '🎖️',
};

// ── Widget principal ──────────────────────────────────────────────────────────

class AnnuaireScreen extends StatefulWidget {
  const AnnuaireScreen({super.key});

  @override
  State<AnnuaireScreen> createState() => _AnnuaireScreenState();
}

class _AnnuaireScreenState extends State<AnnuaireScreen> {
  // Données locales
  AnnuaireLocalData? _localData;

  // État de la navigation
  String? _selectedCat;
  String? _selectedSousCat;
  String? _selectedQuartier;

  // État de la recherche
  String _query = '';
  List<AmiinService> _results = [];
  bool _loading = false;
  bool _nearbyMode = false;
  Timer? _debounce;

  final ScrollController _scroll = ScrollController();
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _scroll.addListener(() {
      final show = _scroll.offset > 200;
      if (show != _showTop) setState(() => _showTop = show);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    setState(() => _loading = true);
    try {
      final d = await annuaireService.loadLocal();
      if (!mounted) return;
      setState(() => _localData = d);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Recherche ──────────────────────────────────────────────────────────────

  void _onQueryChanged(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _doSearch);
  }

  Future<void> _doSearch() async {
    if (_query.isEmpty && !_nearbyMode) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      List<AmiinService> res;
      if (_nearbyMode) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) await Geolocator.requestPermission();
        final pos = await Geolocator.getCurrentPosition();
        res = await annuaireService.getNearby(pos.latitude, pos.longitude,
            categorie: _selectedCat);
      } else {
        res = await annuaireService.search(
          _query,
          categorie: _selectedCat,
          sousCategorie: _selectedSousCat,
          quartier: _selectedQuartier,
        );
      }
      if (!mounted) return;
      setState(() => _results = res);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleNearby() {
    setState(() {
      _nearbyMode = !_nearbyMode;
      _query = '';
      _results = [];
    });
    if (_nearbyMode) _doSearch();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _selectCat(String cat) {
    setState(() {
      _selectedCat   = cat;
      _selectedSousCat = null;
      _query = '';
      _results = [];
      _nearbyMode = false;
    });
  }

  void _selectSousCat(String? sc) {
    setState(() {
      _selectedSousCat = sc;
      _query = '';
      _results = [];
    });
  }

  void _selectQuartier(String? q) {
    setState(() {
      _selectedQuartier = q;
      _query = '';
      _results = [];
    });
  }

  void _goBack() {
    setState(() {
      if (_selectedSousCat != null) {
        _selectedSousCat = null;
      } else {
        _selectedCat = null;
        _selectedQuartier = null;
      }
      _results = [];
      _query = '';
    });
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  bool get _inSearch => _query.isNotEmpty || _nearbyMode;
  bool get _inCategory => _selectedCat != null && !_inSearch;

  List<AmiinService> get _browseEntries {
    if (_localData == null) return [];
    return _localData!.entries.where((e) {
      if (_selectedCat != null && e.category != _selectedCat) return false;
      if (_selectedSousCat != null && e.sousCategorie != _selectedSousCat) return false;
      if (_selectedQuartier != null && e.quartier != _selectedQuartier) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<String> get _availableSousCats {
    if (_localData == null || _selectedCat == null) return [];
    return _localData!.entries
        .where((e) => e.category == _selectedCat && e.sousCategorie.isNotEmpty)
        .map((e) => e.sousCategorie)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get _availableQuartiers {
    if (_localData == null) return [];
    final cats = _localData!.entries
        .where((e) =>
            (_selectedCat == null || e.category == _selectedCat) &&
            e.quartier.isNotEmpty)
        .map((e) => e.quartier)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (_inCategory) _buildSubCatBar(),
            if (_inCategory || _inSearch) _buildQuartierBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: AnimatedScale(
        scale: _showTop ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: FloatingActionButton.small(
          heroTag: 'annTop',
          onPressed: () => _scroll.animateTo(0,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
          backgroundColor: context.ac.surface,
          foregroundColor: context.ac.infoAccent,
          elevation: 2,
          child: const Icon(Icons.keyboard_arrow_up),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Column(
      children: [
        AmiinHeader(
              mode: AmiinMode.info,
          title: _selectedCat ?? 'Annuaire',
          back: _selectedCat != null,
          onBack: _goBack,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
          child: Row(
            children: [
              Expanded(
                child: amiin.AmiinSearchBar(
                  value: _query,
                  onChanged: _onQueryChanged,
                  hintText: _selectedCat != null
                      ? 'Rechercher dans ${_selectedCat!.split(' ').first}…'
                      : 'Pharmacie, restaurant, banque…',
                ),
              ),
              const SizedBox(width: Spacing.sm),
              _NearbyButton(active: _nearbyMode, onTap: _toggleNearby),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubCatBar() {
    final scs = _availableSousCats;
    if (scs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        children: [
          _FilterChip(
            label: 'Toutes',
            selected: _selectedSousCat == null,
            onTap: () => _selectSousCat(null),
          ),
          ...scs.map((sc) => Padding(
                padding: const EdgeInsets.only(left: Spacing.xs),
                child: _FilterChip(
                  label: sc,
                  selected: _selectedSousCat == sc,
                  onTap: () => _selectSousCat(_selectedSousCat == sc ? null : sc),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildQuartierBar() {
    final qs = _availableQuartiers;
    if (qs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        children: [
          _FilterChip(
            label: 'Partout',
            selected: _selectedQuartier == null,
            color: context.ac.infoAccent,
            onTap: () => _selectQuartier(null),
          ),
          ...qs.map((q) => Padding(
                padding: const EdgeInsets.only(left: Spacing.xs),
                child: _FilterChip(
                  label: q,
                  selected: _selectedQuartier == q,
                  color: context.ac.infoAccent,
                  onTap: () =>
                      _selectQuartier(_selectedQuartier == q ? null : q),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _localData == null) return const SkeletonList();

    // Mode recherche ou proche
    if (_inSearch) {
      if (_loading) return const SkeletonList();
      if (_results.isEmpty && _query.length > 1) {
        return const EmptyState(
            title: 'Aucun résultat',
            subtitle: 'Essayez avec d\'autres mots ou ajustez les filtres.');
      }
      return _buildServiceList(_results);
    }

    // Mode navigation catégorie
    if (_inCategory) {
      if (_loading) return const SkeletonList();
      final entries = _browseEntries;
      if (entries.isEmpty) {
        return const EmptyState(
            title: 'Aucune entrée',
            subtitle: 'Aucun service pour ces filtres.');
      }
      return _buildServiceList(entries);
    }

    // Grille d'accueil
    return _buildCategoryGrid();
  }

  Widget _buildCategoryGrid() {
    final cats = _localData?.categories ?? [];
    if (cats.isEmpty) return const SkeletonList();
    // Pré-calcule tous les counts en une seule passe O(n) au lieu de O(n*m)
    final counts = <String, int>{};
    for (final e in _localData!.entries) {
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    return RepaintBoundary(
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(Spacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Spacing.sm,
          crossAxisSpacing: Spacing.sm,
          childAspectRatio: 1.55,
        ),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          return _CategoryTile(
            label: cat,
            count: counts[cat] ?? 0,
            emoji: _catEmoji[cat] ?? '📍',
            color: CategoryColors.annuaire[cat] ?? context.ac.infoAccent,
            onTap: () => _selectCat(cat),
          );
        },
      ),
    );
  }

  Widget _buildServiceList(List<AmiinService> services) {
    return RepaintBoundary(
     child: ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(Spacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) {
        final s = services[i];
        return GestureDetector(
          onTap: () => context.push('/annuaire/${s.id}'),
          child: AmiinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: CategoryColors.annuaire[s.category] ?? context.ac.infoAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.cardTitle(context).copyWith(fontFamily: FontFamily.geoBold)),
                          if (s.sousCategorie.isNotEmpty)
                            Text(s.sousCategorie,
                                style: TextStyles.caption(context).copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                    if (s.distanceKm != null)
                      Text('${s.distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyles.cardTitle(context).copyWith(fontSize: 11, color: context.ac.infoAccent, fontFamily: FontFamily.geoBold)),
                  ],
                ),
                if (s.address.street.isNotEmpty ||
                    s.address.district.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SvgPicture.string(AmiinSvgIcons.loc,
                          width: 11,
                          height: 11,
                          colorFilter: ColorFilter.mode(
                              context.ac.muted, BlendMode.srcIn)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [s.address.street, s.address.district]
                              .where((x) => x.isNotEmpty)
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.caption(context),
                        ),
                      ),
                    ],
                  ),
                ],
                if (s.phone != null && s.phone!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(s.phone!,
                      style: TextStyles.body(context).copyWith(fontSize: 12, color: context.ac.infoAccent)),
                ],
              ],
            ),
          ),
        );
      },
     ),
    );
  }

}

// ── Widgets auxiliaires ───────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final String label;
  final int count;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  const _CategoryTile(
      {required this.label,
      required this.count,
      required this.emoji,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(RadiusAmiin.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: color, height: 1.2, fontFamily: FontFamily.geoBold)),
                Text('$count entrées',
                    style: TextStyles.body(context).copyWith(fontSize: 10, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label,
      required this.selected,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.ac.infoAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : context.ac.surface,
          borderRadius: BorderRadius.circular(RadiusAmiin.full),
          border: Border.all(color: selected ? c : context.ac.border),
        ),
        child: Text(label,
            style: TextStyles.cardTitle(context).copyWith(fontSize: 11, color: selected ? context.ac.onAccent : context.ac.midTone)),
      ),
    );
  }
}

class _NearbyButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _NearbyButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: active ? context.ac.infoAccentLight : context.ac.surface,
          borderRadius: BorderRadius.circular(RadiusAmiin.full),
          border: Border.all(color: context.ac.border),
        ),
        child: Row(
          children: [
            Icon(Icons.near_me,
                size: 15,
                color: active ? context.ac.infoAccentDark : context.ac.muted),
            const SizedBox(width: 4),
            Text('Proche',
                style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: active ? context.ac.infoAccentDark : context.ac.muted)),
          ],
        ),
      ),
    );
  }
}

