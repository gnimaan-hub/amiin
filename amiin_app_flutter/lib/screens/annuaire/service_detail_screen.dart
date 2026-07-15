// â”€â”€â”€ ServiceDetailScreen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

import 'package:flutter/material.dart';
import '../../widgets/amiin_svg_icons.dart';
import '../../widgets/horizon_line.dart';
import '../../widgets/toast.dart';
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
      AmiinToast.show(context, 'Impossible de charger le service');
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
      AmiinToast.show(context, 'Impossible dâ€™ouvrir le lien');
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
              mode: AmiinMode.info,
              title: 'Service',
              back: true,
              rightAction: IconButton(
                icon: SvgPicture.string(
                  AmiinSvgIcons.heart,
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
                    Text(s.name, style: TextStyles.cardTitle(context).copyWith(fontSize: 24, fontFamily: FontFamily.geo)),
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
                          Text('Contact', style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: context.ac.muted, letterSpacing: 1.2, fontFamily: FontFamily.geoBold)),
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
                          Text('Adresse', style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: context.ac.muted, letterSpacing: 1.2, fontFamily: FontFamily.geoBold)),
                          const SizedBox(height: 8),
                          Text('${s.address.street}\n${s.address.district}, ${s.address.city}', style: TextStyles.body(context).copyWith(color: context.ac.midTone)),
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
                            Text('Horaires', style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: context.ac.muted, letterSpacing: 1.2, fontFamily: FontFamily.geoBold)),
                            const SizedBox(height: 8),
                            Text(s.hours!, style: TextStyles.body(context).copyWith(color: context.ac.midTone)),
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
                            Text('Ã€ propos', style: TextStyles.cardTitle(context).copyWith(fontSize: 10, color: context.ac.muted, letterSpacing: 1.2, fontFamily: FontFamily.geoBold)),
                            const SizedBox(height: 8),
                            Text(s.description!, style: TextStyles.body(context).copyWith(color: context.ac.midTone)),
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
          Expanded(child: Text(text, style: TextStyles.body(context).copyWith(color: context.ac.infoAccent))),
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
        child: Text(label, style: TextStyles.cardTitle(context).copyWith(fontSize: 11, color: color)),
      );

}
