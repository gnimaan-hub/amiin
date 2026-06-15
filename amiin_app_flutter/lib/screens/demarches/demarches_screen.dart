// ─── DemarchesScreen ─────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
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
      case DemarcheStatus.aFaire:   return ColorsAmiin.mid;
      case DemarcheStatus.enCours:  return ColorsAmiin.indigo;
      case DemarcheStatus.terminee: return ColorsAmiin.olive;
      case DemarcheStatus.expiree:  return ColorsAmiin.muted;
    }
  }

  Color _statusBgColor(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire:   return ColorsAmiin.sand;
      case DemarcheStatus.enCours:  return ColorsAmiin.indigoLt;
      case DemarcheStatus.terminee: return ColorsAmiin.oliveLt;
      case DemarcheStatus.expiree:  return ColorsAmiin.ecru;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Démarches'),
            // Onglets Catalogue / Mes démarches
            Container(
              color: ColorsAmiin.white,
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
                          color: selected ? ColorsAmiin.terra : ColorsAmiin.white,
                          borderRadius: BorderRadius.circular(RadiusAmiin.full),
                          border: Border.all(color: selected ? ColorsAmiin.terra : ColorsAmiin.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cat.icon, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(cat.label, style: TextStyle(
                              fontFamily: FontFamily.sansMedium,
                              fontSize: 12,
                              color: selected ? ColorsAmiin.white : ColorsAmiin.mid,
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
                      color: ColorsAmiin.terra,
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: isActive ? ColorsAmiin.terra : Colors.transparent,
              width: 2,
            )),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FontFamily.sansMedium,
              fontSize: 13,
              color: isActive ? ColorsAmiin.terra : ColorsAmiin.muted,
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
              fontFamily: FontFamily.sansBold,
              fontSize: 13,
              color: ColorsAmiin.ink,
            )),
            const SizedBox(width: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ColorsAmiin.sand,
                borderRadius: BorderRadius.circular(RadiusAmiin.sm),
              ),
              child: Text('${items.length}', style: TextStyle(
                fontFamily: FontFamily.sansBold, fontSize: 10, color: ColorsAmiin.mid,
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
                          fontFamily: FontFamily.sansBold,
                          fontSize: 14,
                          color: ColorsAmiin.ink,
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
                            color: ColorsAmiin.muted,
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
                    color: isInfo ? ColorsAmiin.indigoLt : ColorsAmiin.oliveLt,
                    borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                  ),
                  child: Text(
                    isInfo ? 'Info' : 'Démarche',
                    style: TextStyle(
                      fontFamily: FontFamily.sansBold,
                      fontSize: 10,
                      color: isInfo ? ColorsAmiin.indigo : ColorsAmiin.olive,
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

  Widget _metaTag(String icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(icon, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted)),
    ],
  );

  String _truncateCost(String cost) {
    final lines = cost.split('.')[0].split('\n')[0].trim();
    return lines.length > 40 ? '${lines.substring(0, 37)}…' : lines;
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
        return GestureDetector(
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
                        fontFamily: FontFamily.sansBold, fontSize: 14, color: ColorsAmiin.ink,
                      )),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusBgColor(ud.status),
                        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                      ),
                      child: Text(_statusLabel(ud.status), style: TextStyle(
                        fontFamily: FontFamily.sansBold, fontSize: 11, color: _statusColor(ud.status),
                      )),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(ud.demarche.category.label, style: TextStyle(
                  fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.muted,
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
                            backgroundColor: ColorsAmiin.border,
                            color: ud.status == DemarcheStatus.terminee
                                ? ColorsAmiin.olive
                                : ColorsAmiin.terra,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        '${ud.completedSteps}/${ud.totalSteps}',
                        style: TextStyle(fontFamily: FontFamily.sansBold, fontSize: 11, color: ColorsAmiin.mid),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ud.status == DemarcheStatus.terminee
                        ? 'Terminée ✓'
                        : 'Étape ${ud.currentStep} sur ${ud.totalSteps}',
                    style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
