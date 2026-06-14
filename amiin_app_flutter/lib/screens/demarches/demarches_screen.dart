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

  final List<({DemarcheCategory? category, String label})> _categories = const [
    (category: null, label: 'Toutes'),
    (category: DemarcheCategory.identite, label: 'Identité'),
    (category: DemarcheCategory.famille, label: 'Famille'),
    (category: DemarcheCategory.emploi, label: 'Emploi'),
    (category: DemarcheCategory.sante, label: 'Santé'),
    (category: DemarcheCategory.logement, label: 'Logement'),
    (category: DemarcheCategory.fiscal, label: 'Fiscal'),
    (category: DemarcheCategory.transport, label: 'Transport'),
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
      setState(() {
        _catalog = results[0] as List<Demarche>;
        _userDemarches = results[1] as List<UserDemarche>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _onSearch(String text) {
    _query = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadData);
  }

  void _onCategory(DemarcheCategory? cat) {
    _category = cat;
    _loadData();
  }

  String _statusLabel(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire: return 'À faire';
      case DemarcheStatus.enCours: return 'En cours';
      case DemarcheStatus.terminee: return 'Terminée';
      case DemarcheStatus.expiree: return 'Expirée';
    }
  }

  Color _statusColor(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire: return ColorsAmiin.mid;
      case DemarcheStatus.enCours: return ColorsAmiin.indigo;
      case DemarcheStatus.terminee: return ColorsAmiin.olive;
      case DemarcheStatus.expiree: return ColorsAmiin.muted;
    }
  }

  Color _statusBgColor(DemarcheStatus status) {
    switch (status) {
      case DemarcheStatus.aFaire: return ColorsAmiin.sand;
      case DemarcheStatus.enCours: return ColorsAmiin.indigoLt;
      case DemarcheStatus.terminee: return ColorsAmiin.oliveLt;
      case DemarcheStatus.expiree: return ColorsAmiin.ecru;
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
            // Tab selector
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
                padding: const EdgeInsets.all(Spacing.lg),
                child: AmiinSearchBar(
                  value: _query,
                  onChanged: _onSearch,
                  hintText: 'Carte nationale, passeport…',
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => SizedBox(width: Spacing.sm),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final selected = _category == cat.category;
                    return GestureDetector(
                      onTap: () => _onCategory(cat.category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? ColorsAmiin.terra : ColorsAmiin.white,
                          borderRadius: BorderRadius.circular(RadiusAmiin.full),
                          border: Border.all(color: ColorsAmiin.border),
                        ),
                        child: Text(cat.label, style: TextStyle(
                          fontFamily: FontFamily.sansMedium,
                          fontSize: 12,
                          color: selected ? ColorsAmiin.white : ColorsAmiin.mid,
                        )),
                      ),
                    );
                  },
                ),
              ),
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
            border: Border(bottom: BorderSide(color: isActive ? ColorsAmiin.terra : Colors.transparent, width: 2)),
          ),
          child: Text(label,
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
          child: EmptyState(title: 'Aucune démarche trouvée', subtitle: 'Essayez un autre terme ou catégorie.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _catalog.length,
      separatorBuilder: (_, __) => SizedBox(height: Spacing.sm),
      itemBuilder: (context, index) {
        final d = _catalog[index];
        return GestureDetector(
          onTap: () => context.push('/demarches/${d.id}'),
          child: AmiinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18, color: ColorsAmiin.muted),
                    SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(
                            fontFamily: FontFamily.sansBold,
                            fontSize: 14,
                            color: ColorsAmiin.ink,
                          )),
                          SizedBox(height: 2),
                          Text(d.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(
                            fontFamily: FontFamily.sans,
                            fontSize: 12,
                            color: ColorsAmiin.muted,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.md,
                  children: [
                    if (d.duration != null) Text('⏱ ${d.duration}', style: TextStyle(fontSize: 11, color: ColorsAmiin.muted)),
                    if (d.cost != null) Text('💰 ${d.cost}', style: TextStyle(fontSize: 11, color: ColorsAmiin.muted)),
                    Text('📄 ${d.documents.length} pièces', style: TextStyle(fontSize: 11, color: ColorsAmiin.muted)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserDemarchesList() {
    if (_userDemarches.isEmpty) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: EmptyState(
            title: 'Aucune démarche en cours',
            subtitle: 'Parcourez le catalogue pour démarrer une procédure.',
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _userDemarches.length,
      separatorBuilder: (_, __) => SizedBox(height: Spacing.sm),
      itemBuilder: (context, index) {
        final ud = _userDemarches[index];
        final total = ud.demarche.steps.length;
        final progress = total > 0 ? ud.currentStep / total : 0.0;
        return GestureDetector(
          onTap: () => context.push('/demarches/user/${ud.id}'),
          child: AmiinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ud.demarche.title, style: TextStyle(
                  fontFamily: FontFamily.sansBold,
                  fontSize: 14,
                  color: ColorsAmiin.ink,
                )),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusBgColor(ud.status),
                    borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                  ),
                  child: Text(_statusLabel(ud.status), style: TextStyle(
                    fontFamily: FontFamily.sansBold,
                    fontSize: 11,
                    color: _statusColor(ud.status),
                  )),
                ),
                if (total > 0) ...[
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: ColorsAmiin.border,
                      color: ColorsAmiin.terra,
                      minHeight: 4,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text('${ud.currentStep}/$total étapes', style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 11,
                    color: ColorsAmiin.muted,
                  )),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}