// â”€â”€â”€ ServiceDetailScreen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/button.dart';
import '../../services/annuaire_service.dart';

class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  AmiinService? _service;
  bool _loading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  Future<void> _loadService() async {
    try {
      final s = await annuaireService.getService(widget.serviceId);
      if (!mounted) return;
      setState(() {
        _service = s;
        _isFavorite = s.isFavorite ?? false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de charger le service')));
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_service == null) return;
    final newFavorite = !_isFavorite;
    setState(() => _isFavorite = newFavorite);
    await annuaireService.toggleFavorite(_service!.id, newFavorite);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (!mounted) return;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible dâ€™ouvrir le lien')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: context.ac.infoAccent)));
    }
    if (_service == null) return const SizedBox();

    final s = _service!;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: 'Service',
              back: true,
              rightAction: IconButton(
                icon: SvgPicture.string(
                  _heartSvg,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    _isFavorite ? context.ac.infoAccent : context.ac.infoAccent.withValues(alpha: 0.4),
                    BlendMode.srcIn,
                  ),
                ),
                onPressed: _toggleFavorite,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: TextStyle(
                      fontFamily: FontFamily.geo,
                      fontSize: 24,
                      color: context.ac.ink,
                    )),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (s.sousCategorie.isNotEmpty)
                          _tagChip(s.sousCategorie, context.ac.infoAccent),
                        if (s.quartier.isNotEmpty)
                          _tagChip(s.quartier, context.ac.infoAccent),
                        if (s.ministry != null)
                          _tagChip(s.ministry!, context.ac.muted),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Contact', style: TextStyle(
                            fontFamily: FontFamily.geoBold,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: context.ac.muted,
                          )),
                          const SizedBox(height: 8),
                          if (s.phone != null) ...[
                            _contactRow('ðŸ“ž', s.phone!, () => _launchUrl('tel:${s.phone}')),
                            const SizedBox(height: Spacing.sm),
                          ],
                          if (s.email != null) ...[
                            _contactRow('âœ‰ï¸', s.email!, () => _launchUrl('mailto:${s.email}')),
                            const SizedBox(height: Spacing.sm),
                          ],
                          if (s.website != null) ...[
                            _contactRow('ðŸŒ', s.website!, () => _launchUrl(s.website!)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Adresse', style: TextStyle(
                            fontFamily: FontFamily.geoBold,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: context.ac.muted,
                          )),
                          const SizedBox(height: 8),
                          Text('${s.address.street}\n${s.address.district}, ${s.address.city}', style: TextStyle(
                            fontFamily: FontFamily.sans,
                            fontSize: 14,
                            color: context.ac.midTone,
                          )),
                          if (s.address.coordinates != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: AmiinButton(
                                label: 'Ouvrir dans Maps',
                                variant: ButtonVariant.ghost,
                                size: ButtonSize.sm,
                                onPressed: () {
                                  final lat = s.address.coordinates!['lat']!;
                                  final lng = s.address.coordinates!['lng']!;
                                  _launchUrl('https://maps.google.com/?q=$lat,$lng');
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (s.hours != null && s.hours!.isNotEmpty) ...[
                      const SizedBox(height: Spacing.md),
                      AmiinCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Horaires', style: TextStyle(
                              fontFamily: FontFamily.geoBold,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: context.ac.muted,
                            )),
                            const SizedBox(height: 8),
                            Text(s.hours!, style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 14,
                              color: context.ac.midTone,
                            )),
                          ],
                        ),
                      ),
                    ],
                    if (s.description != null) ...[
                      const SizedBox(height: Spacing.md),
                      AmiinCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ã€ propos', style: TextStyle(
                              fontFamily: FontFamily.geoBold,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: context.ac.muted,
                            )),
                            const SizedBox(height: 8),
                            Text(s.description!, style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontSize: 14,
                              color: context.ac.midTone,
                              height: 1.5,
                            )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(String icon, String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(text, style: TextStyle(
            fontFamily: FontFamily.sans,
            fontSize: 14,
            color: context.ac.infoAccent,
          ))),
        ],
      ),
    );
  }

  Widget _tagChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(RadiusAmiin.xl),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: FontFamily.geoMedium,
          fontSize: 11,
          color: color,
        )),
      );

  static const String _heartSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M11 19S3 13 3 7.5A5 5 0 0111 4a5 5 0 018 3.5C19 13 11 19 11 19z" stroke="currentColor" stroke-width="1.6" fill="none"/>
    </svg>
  ''';
}
