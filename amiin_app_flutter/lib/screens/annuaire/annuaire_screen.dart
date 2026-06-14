// ─── AnnuaireScreen ──────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../services/annuaire_service.dart';

class AnnuaireScreen extends StatefulWidget {
  const AnnuaireScreen({super.key});

  @override
  State<AnnuaireScreen> createState() => _AnnuaireScreenState();
}

class _AnnuaireScreenState extends State<AnnuaireScreen> {
  List<AmiinService> _services = [];
  String _query = '';
  ServiceCategory? _category;
  bool _nearbyMode = false;
  bool _loading = false;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  final List<({String key, String label, ServiceCategory? category})> _categories = const [
    (key: 'all', label: 'Tous', category: null),
    (key: 'ministere', label: 'Ministères', category: ServiceCategory.ministere),
    (key: 'mairie', label: 'Mairies', category: ServiceCategory.mairie),
    (key: 'sante', label: 'Santé', category: ServiceCategory.sante),
    (key: 'education', label: 'Éducation', category: ServiceCategory.education),
    (key: 'justice', label: 'Justice', category: ServiceCategory.justice),
    (key: 'securite', label: 'Sécurité', category: ServiceCategory.securite),
    (key: 'transport', label: 'Transport', category: ServiceCategory.transport),
  ];

  @override
  void initState() {
    super.initState();
    _search();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.offset > 200;
    if (show != _showBackToTop) setState(() => _showBackToTop = show);
  }

  void _scrollToTop() {
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      List<AmiinService> results;
      if (_nearbyMode) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission de localisation refusée')));
          setState(() => _nearbyMode = false);
          return;
        }
        final position = await Geolocator.getCurrentPosition();
        results = await annuaireService.getNearby(position.latitude, position.longitude);
      } else {
        results = await annuaireService.search(_query, category: _category);
      }
      if (!mounted) return;
      setState(() => _services = results);
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String text) {
    _query = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  void _onCategory(ServiceCategory? cat) {
    _category = cat;
    _search();
  }

  void _toggleNearby() {
    setState(() {
      _nearbyMode = !_nearbyMode;
      if (_nearbyMode) _category = null;
    });
    _search();
  }

  Color _categoryColor(ServiceCategory? category) {
    switch (category) {
      case ServiceCategory.ministere: return ColorsAmiin.terra;
      case ServiceCategory.mairie: return ColorsAmiin.indigo;
      case ServiceCategory.sante: return const Color(0xFFC0392B);
      case ServiceCategory.education: return const Color(0xFF8C6D3F);
      case ServiceCategory.justice: return ColorsAmiin.ink;
      case ServiceCategory.securite: return ColorsAmiin.olive;
      case ServiceCategory.transport: return const Color(0xFF2980B9);
      default: return ColorsAmiin.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Annuaire'),
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: AmiinSearchBar(
                      value: _query,
                      onChanged: _onSearch,
                      hintText: 'Ministère, service, nom…',
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  GestureDetector(
                    onTap: _toggleNearby,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                      decoration: BoxDecoration(
                        color: _nearbyMode ? ColorsAmiin.terraLt : ColorsAmiin.white,
                        borderRadius: BorderRadius.circular(RadiusAmiin.full),
                        border: Border.all(color: ColorsAmiin.border),
                      ),
                      child: Row(
                        children: [
                          SvgPicture.string(_locationSvg, width: 16, height: 16,
                            colorFilter: ColorFilter.mode(_nearbyMode ? ColorsAmiin.terraDk : ColorsAmiin.muted, BlendMode.srcIn),
                          ),
                          const SizedBox(width: 4),
                          Text('Proche', style: TextStyle(
                            fontFamily: FontFamily.sansMedium,
                            fontSize: 12,
                            color: _nearbyMode ? ColorsAmiin.terraDk : ColorsAmiin.muted,
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final selected = (_nearbyMode && cat.key == 'all') || (!_nearbyMode && _category == cat.category);
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
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: _loading
                  ? const SkeletonList()
                  : _services.isEmpty
                      ? const EmptyState(title: 'Aucun résultat', subtitle: 'Modifiez votre recherche ou la catégorie.')
                      : RefreshIndicator(
                          onRefresh: _search,
                          color: ColorsAmiin.terra,
                          child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(Spacing.lg),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _services.length,
                          separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) {
                            final s = _services[index];
                            return GestureDetector(
                              onTap: () => context.push('/annuaire/${s.id}'),
                              child: AmiinCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 10, height: 10,
                                          decoration: BoxDecoration(
                                            color: _categoryColor(s.category),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: Spacing.sm),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(
                                                fontFamily: FontFamily.sansBold,
                                                fontSize: 14,
                                                color: ColorsAmiin.ink,
                                              )),
                                              if (s.ministry != null)
                                                Text(s.ministry!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                                  fontFamily: FontFamily.sans,
                                                  fontSize: 12,
                                                  color: ColorsAmiin.muted,
                                                )),
                                            ],
                                          ),
                                        ),
                                        if (s.distanceKm != null)
                                          Text('${s.distanceKm!.toStringAsFixed(1)} km', style: TextStyle(
                                            fontFamily: FontFamily.sansBold,
                                            fontSize: 11,
                                            color: ColorsAmiin.terra,
                                          )),
                                      ],
                                    ),
                                    const SizedBox(height: Spacing.sm),
                                    Row(
                                      children: [
                                        SvgPicture.string(_locationSvg, width: 12, height: 12,
                                          colorFilter: const ColorFilter.mode(ColorsAmiin.muted, BlendMode.srcIn),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text('${s.address.street}, ${s.address.district}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                                            fontFamily: FontFamily.sans,
                                            fontSize: 12,
                                            color: ColorsAmiin.muted,
                                          )),
                                        ),
                                      ],
                                    ),
                                    if (s.phone != null) ...[
                                      const SizedBox(height: 4),
                                      Text(s.phone!, style: TextStyle(
                                        fontFamily: FontFamily.sans,
                                        fontSize: 12,
                                        color: ColorsAmiin.indigo,
                                      )),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        ),  // RefreshIndicator
            ),
          ],
        ),
      ),
      floatingActionButton: AnimatedScale(
        scale: _showBackToTop ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: FloatingActionButton.small(
          heroTag: 'annuaireScrollTop',
          onPressed: _scrollToTop,
          backgroundColor: ColorsAmiin.white,
          foregroundColor: ColorsAmiin.terra,
          elevation: 2,
          child: const Icon(Icons.keyboard_arrow_up),
        ),
      ),
    );
  }

  static const String _locationSvg = '''
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M8 1a5 5 0 015 5c0 3.5-5 9-5 9S3 9.5 3 6a5 5 0 015-5z" stroke="currentColor" stroke-width="1.4"/>
      <circle cx="8" cy="6" r="1.5" fill="currentColor"/>
    </svg>
  ''';
}