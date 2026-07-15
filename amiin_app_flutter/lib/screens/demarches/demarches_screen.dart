// ─── DemarchesScreen ─────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/horizon_line.dart';
import 'package:go_router/go_router.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../services/demarches_service.dart';

class DemarchesScreen extends StatefulWidget {
  const DemarchesScreen({super.key});

  @override
  State<DemarchesScreen> createState() => _DemarchesScreenState();
}

class _DemarchesScreenState extends State<DemarchesScreen> {
  List<Demarche> _catalog = [];
  List<UserDemarche> _userDemarches = [];
  String _query = '';
  DemarcheCategory? _category;
  bool _loading = true;
  int _tabIndex = 0;
  Timer? _debounce;

  static const List<({DemarcheCategory? category, String label, String icon})> _categories = [
    (category: null,                                   label: 'Toutes',         icon: '📋'),
    (category: DemarcheCategory.identiteFamille,       label: 'Identité',       icon: '🪪'),
    (category: DemarcheCategory.santeSocial,           label: 'Santé',          icon: '🏥'),
    (category: DemarcheCategory.education,             label: 'Éducation',      icon: '🎓'),
    (category: DemarcheCategory.habitatLogement,       label: 'Habitat',        icon: '🏠'),
    (category: DemarcheCategory.transport,             label: 'Transport',      icon: '🚗'),
    (category: DemarcheCategory.justice,               label: 'Justice',        icon: '⚖️'),
    (category: DemarcheCategory.economieFinance,       label: 'Économie',       icon: '💼'),
    (category: DemarcheCategory.etrangers,             label: 'Étrangers',      icon: '✈️'),
    (category: DemarcheCategory.energieEau,            label: 'Énergie & Eau',  icon: '💡'),
    (category: DemarcheCategory.securite,              label: 'Sécurité',       icon: '🔐'),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final catalogFuture = demarchesService.getCatalog(
        category: _category,
        query: _query.isEmpty ? null : _query,
      );
      final userFuture = demarchesService.getUserDemarches();
      final results = await Future.wait([catalogFuture, userFuture]);
      if (mounted) {
        setState(() {
          _catalog = results[0] as List<Demarche>;
          _userDemarches = results[1] as List<UserDemarche>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String text) {
    _query = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadData);
  }

  void _onCategory(DemarcheCategory? cat) {
    setState(() => _category = cat);
    _loadData();
  }

  String _statusLabel(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire:   return 'À faire';
      case DemarcheStatus.enCours:  return 'En cours';
      case DemarcheStatus.terminee: return 'Terminée';
      case DemarcheStatus.expiree:  return 'Expirée';
    }
  }

  Color _statusColor(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire:   return context.ac.midTone;
      case DemarcheStatus.enCours:  return context.ac.infoAccent;
      case DemarcheStatus.terminee: return context.ac.success;
      case DemarcheStatus.expiree:  return context.ac.muted;
    }
  }

  Color _statusBgColor(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire:   return context.ac.surface2;
      case DemarcheStatus.enCours:  return context.ac.infoAccentLight;
      case DemarcheStatus.terminee: return context.ac.successLight;
      case DemarcheStatus.expiree:  return context.ac.background;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(
              mode: AmiinMode.info,title: 'Démarches'),
            // Onglets Catalogue / Mes démarches
            Container(
              color: context.ac.surface,
              child: Row(
                children: [
                  _buildTab('Catalogue', 0),
                  _buildTab('Mes démarches${_userDemarches.isNotEmpty ? ' (${_userDemarches.length})' : ''}', 1),
                ],
              ),
            ),
            if (_tabIndex == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                child: AmiinSearchBar(
                  value: _query,
                  onChanged: _onSearch,
                  hintText: 'Passeport, carte grise, CNSS…',
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final selected = _category == cat.category;
                    return GestureDetector(
                      onTap: () => _onCategory(cat.category),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? context.ac.infoAccent : context.ac.surface,
                          borderRadius: BorderRadius.circular(RadiusAmiin.full),
                          border: Border.all(color: selected ? context.ac.infoAccent : context.ac.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cat.icon, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(cat.label, style: TextStyle(
                              fontFamily: FontFamily.geoMedium,
                              fontSize: 12,
                              color: selected ? context.ac.onAccent : context.ac.midTone,
                            )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Expanded(
              child: _loading
                  ? const SkeletonList()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: context.ac.infoAccent,
                      child: _tabIndex == 0
                          ? _buildCatalogList()
                          : _buildUserDemarchesList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: isActive ? context.ac.infoAccent : Colors.transparent,
              width: 2,
            )),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FontFamily.geoMedium,
              fontSize: 13,
              color: isActive ? context.ac.infoAccent : context.ac.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogList() {
    if (_catalog.isEmpty) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: EmptyState(
            title: 'Aucune démarche trouvée',
            subtitle: 'Essayez un autre terme ou catégorie.',
          ),
        ),
      );
    }

    // Grouper par catégorie si pas de filtre actif
    if (_category == null && _query.isEmpty) {
      return _buildGroupedCatalog();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _catalog.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) => _catalogCard(_catalog[i]),
    );
  }

  Widget _buildGroupedCatalog() {
    final Map<DemarcheCategory, List<Demarche>> grouped = {};
    for (final d in _catalog) {
      grouped.putIfAbsent(d.category, () => []).add(d);
    }

    final sections = <Widget>[];
    for (final cat in DemarcheCategory.values) {
      final items = grouped[cat];
      if (items == null || items.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
        child: Row(
          children: [
            Text(cat.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: Spacing.sm),
            Text(cat.label, style: TextStyle(
              fontFamily: FontFamily.geoBold,
              fontSize: 13,
              color: context.ac.ink,
            )),
            const SizedBox(width: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.ac.surface2,
                borderRadius: BorderRadius.circular(RadiusAmiin.sm),
              ),
              child: Text('${items.length}', style: TextStyle(
                fontFamily: FontFamily.geoBold, fontSize: 10, color: context.ac.midTone,
              )),
            ),
          ],
        ),
      ));
      for (int i = 0; i < items.length; i++) {
        sections.add(Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.lg, 0, Spacing.lg, i < items.length - 1 ? Spacing.sm : 0,
          ),
          child: _catalogCard(items[i]),
        ));
      }
    }
    sections.add(const SizedBox(height: Spacing.xl));

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections),
    );
  }

  Widget _catalogCard(Demarche d) {
    final isInfo = d.type == DemarcheType.information;
    return GestureDetector(
      onTap: () => context.push('/demarches/${d.id}'),
      child: AmiinCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FontFamily.geoBold,
                          fontSize: 14,
                          color: context.ac.ink,
                          height: 1.3,
                        ),
                      ),
                      if (d.summary.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(d.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FontFamily.sans,
                            fontSize: 12,
                            color: context.ac.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isInfo ? context.ac.infoAccentLight : context.ac.successLight,
                    borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                  ),
                  child: Text(
                    isInfo ? 'Info' : 'Démarche',
                    style: TextStyle(
                      fontFamily: FontFamily.geoBold,
                      fontSize: 10,
                      color: isInfo ? context.ac.infoAccent : context.ac.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: 4,
              children: [
                if (d.duration != null && d.duration!.isNotEmpty && d.duration != 'Non spécifié.')
                  _metaTag('⏱', d.duration!),
                if (d.cost != null && d.cost!.isNotEmpty && d.cost != 'Non spécifié.')
                  _metaTag('💰', _truncateCost(d.cost!)),
                if (!isInfo && d.documents.isNotEmpty)
                  _metaTag('📄', '${d.documents.length} pièce${d.documents.length > 1 ? 's' : ''}'),
                if (!isInfo && d.steps.isNotEmpty)
                  _metaTag('📝', '${d.steps.length} étape${d.steps.length > 1 ? 's' : ''}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaTag(String icon, String label) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 140),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: context.ac.muted),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );

  String _truncateCost(String cost) {
    final first = cost.split('\n')[0].split('.')[0].trim();
    return first.length > 28 ? '${first.substring(0, 25)}…' : first;
  }

  Widget _buildUserDemarchesList() {
    if (_userDemarches.isEmpty) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: EmptyState(
            title: 'Aucune démarche en cours',
            subtitle: 'Parcourez le catalogue et démarrez une procédure.',
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _userDemarches.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) {
        final ud = _userDemarches[i];
        return Dismissible(
          key: Key(ud.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Spacing.lg),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(RadiusAmiin.md),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
          ),
          confirmDismiss: (_) => showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Supprimer la démarche ?'),
              content: const Text('Votre suivi sera supprimé. Le catalogue n\'est pas affecté.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
          onDismissed: (_) async {
            await demarchesService.deleteDemarche(ud.id);
            _loadData();
          },
          child: GestureDetector(
          onTap: () async {
            await context.push('/demarches/user/${ud.id}');
            _loadData();
          },
          child: AmiinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(ud.demarche.title, style: TextStyle(
                        fontFamily: FontFamily.geoBold, fontSize: 14, color: context.ac.ink,
                      )),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusBgColor(ud.status),
                        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                      ),
                      child: Text(_statusLabel(ud.status), style: TextStyle(
                        fontFamily: FontFamily.geoBold, fontSize: 11, color: _statusColor(ud.status),
                      )),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(ud.demarche.category.label, style: TextStyle(
                  fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.muted,
                )),
                if (ud.totalSteps > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ud.progress,
                            backgroundColor: context.ac.border,
                            color: ud.status == DemarcheStatus.terminee
                                ? context.ac.success
                                : context.ac.infoAccent,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        '${ud.completedSteps}/${ud.totalSteps}',
                        style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 11, color: context.ac.midTone),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ud.status == DemarcheStatus.terminee
                        ? 'Terminée ✓'
                        : 'Étape ${ud.currentStep} sur ${ud.totalSteps}',
                    style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: context.ac.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      },
    );
  }
}

