// ─── DemarcheDetailScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/button.dart';
import '../../services/demarches_service.dart';
import '../../services/annuaire_service.dart';

class DemarcheDetailScreen extends StatefulWidget {
  final String demarcheId;
  const DemarcheDetailScreen({super.key, required this.demarcheId});

  @override
  State<DemarcheDetailScreen> createState() => _DemarcheDetailScreenState();
}

class _DemarcheDetailScreenState extends State<DemarcheDetailScreen> {
  Demarche? _demarche;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadDemarche();
  }

  Future<void> _loadDemarche() async {
    try {
      final d = await demarchesService.getDemarche(widget.demarcheId);
      if (mounted) setState(() { _demarche = d; _loading = false; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de charger cette démarche.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startDemarche() async {
    setState(() => _starting = true);
    try {
      final ud = await demarchesService.startDemarche(widget.demarcheId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Démarche démarrée — retrouvez-la dans « Mes démarches ».')),
        );
        context.pushReplacement('/demarches/user/${ud.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: ColorsAmiin.ocre)));
    }
    if (_demarche == null) return const SizedBox();

    final d = _demarche!;
    final isInfo = d.type == DemarcheType.information;

    // Grouper les docs par cas
    final Map<String?, List<DemarcheDocument>> docsByCas = {};
    for (final doc in d.documents) {
      docsByCas.putIfAbsent(doc.cas, () => []).add(doc);
    }

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Démarche', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge type
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isInfo ? ColorsAmiin.ocreLt : ColorsAmiin.successLt,
                            borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                          ),
                          child: Text(
                            isInfo ? 'Fiche d\'information' : 'Démarche administrative',
                            style: TextStyle(
                              fontFamily: FontFamily.geoBold,
                              fontSize: 10,
                              color: isInfo ? ColorsAmiin.ocre : ColorsAmiin.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          '${d.category.icon} ${d.category.label}',
                          style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    // Titre
                    Text(d.title, style: TextStyle(
                      fontFamily: FontFamily.geo,
                      fontSize: 22,
                      color: ColorsAmiin.ink,
                      height: 1.3,
                    )),
                    const SizedBox(height: Spacing.sm),

                    // Métadonnées
                    if (d.duration != null || d.cost != null || d.documents.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            if (d.duration != null) _metaChip('⏱', d.duration!),
                            if (d.cost != null) _metaChip('💰', d.cost!),
                            if (d.documents.isNotEmpty) _metaChip('📄', '${d.documents.length} pièce${d.documents.length > 1 ? 's' : ''}'),
                            if (d.steps.isNotEmpty) _metaChip('📝', '${d.steps.length} étape${d.steps.length > 1 ? 's' : ''}'),
                          ],
                        ),
                      ),

                    // Description
                    if (d.summary.isNotEmpty)
                      _section(
                        icon: Icons.info_outline,
                        title: 'Description',
                        child: Text(d.summary, style: TextStyle(
                          fontFamily: FontFamily.sans, fontSize: 14, color: ColorsAmiin.mid, height: 1.5,
                        )),
                      ),

                    // Bénéficiaires
                    if (d.beneficiaires != null)
                      _section(
                        icon: Icons.people_outline,
                        title: 'Qui peut faire cette démarche ?',
                        child: Text(d.beneficiaires!, style: TextStyle(
                          fontFamily: FontFamily.sans, fontSize: 14, color: ColorsAmiin.mid, height: 1.5,
                        )),
                      ),

                    // Conditions
                    if (d.conditions != null)
                      _section(
                        icon: Icons.check_circle_outline,
                        title: 'Conditions requises',
                        child: Text(d.conditions!, style: TextStyle(
                          fontFamily: FontFamily.sans, fontSize: 14, color: ColorsAmiin.mid, height: 1.5,
                        )),
                      ),

                    // Documents
                    if (d.documents.isNotEmpty)
                      _section(
                        icon: Icons.folder_outlined,
                        title: 'Pièces justificatives',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final cas in docsByCas.keys) ...[
                              if (cas != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: ColorsAmiin.sand,
                                    borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                                  ),
                                  child: Text('Cas : $cas', style: TextStyle(
                                    fontFamily: FontFamily.geoBold, fontSize: 11, color: ColorsAmiin.mid,
                                  )),
                                ),
                                const SizedBox(height: 6),
                              ],
                              for (final doc in docsByCas[cas]!) ...[
                                _docRow(doc.name),
                                const SizedBox(height: 4),
                              ],
                            ],
                          ],
                        ),
                      ),

                    // Étapes
                    if (d.steps.isNotEmpty)
                      _section(
                        icon: Icons.list_alt_outlined,
                        title: 'Étapes de la procédure',
                        child: Column(
                          children: [
                            for (int i = 0; i < d.steps.length; i++)
                              _stepRow(d.steps[i], isLast: i == d.steps.length - 1),
                          ],
                        ),
                      ),

                    // Résultat
                    if (d.resultat != null)
                      _section(
                        icon: Icons.emoji_events_outlined,
                        title: 'Résultat attendu',
                        child: Text(d.resultat!, style: TextStyle(
                          fontFamily: FontFamily.sans, fontSize: 14, color: ColorsAmiin.mid, height: 1.5,
                        )),
                      ),

                    // Organisme
                    if (d.lieux.isNotEmpty)
                      _section(
                        icon: Icons.business_outlined,
                        title: d.lieux.length == 1 ? 'Organisme compétent' : 'Où faire la démarche ?',
                        child: _organismeBody(d),
                      ),

                    const SizedBox(height: Spacing.md),

                    // Bouton démarrer (uniquement pour les démarches, pas les infos)
                    if (!isInfo)
                      AmiinButton(
                        label: 'Démarrer cette procédure',
                        onPressed: _startDemarche,
                        loading: _starting,
                        fullWidth: true,
                        size: ButtonSize.lg,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInAnnuaire(DemarcheOrganisme org) async {
    final results = await annuaireService.searchSimilar(org.nom);
    if (!mounted) return;
    if (results.isNotEmpty) {
      context.go('/annuaire/${results.first.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('« ${org.nom} » introuvable dans l\'annuaire.')),
      );
      context.go('/annuaire');
    }
  }

  Widget _organismeBody(Demarche d) {
    final lieux = d.lieux;
    if (lieux.length == 1) return _organismeCard(lieux.first);

    final org = d.organisme!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (org.adresse != null && org.adresse!.isNotEmpty) ...[
          Row(children: [
            Icon(Icons.location_on_outlined, size: 13, color: ColorsAmiin.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.adresse!, style: TextStyle(
              fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid,
            ))),
          ]),
          const SizedBox(height: 4),
        ],
        if (org.horaires != null && org.horaires!.isNotEmpty) ...[
          Row(children: [
            Icon(Icons.schedule_outlined, size: 13, color: ColorsAmiin.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.horaires!, style: TextStyle(
              fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid,
            ))),
          ]),
          const SizedBox(height: Spacing.sm),
        ],
        for (int i = 0; i < lieux.length; i++) ...[
          if (i > 0) const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Divider(height: 1, color: ColorsAmiin.border),
          ),
          Row(children: [
            Expanded(child: Text(lieux[i].nom, style: TextStyle(
              fontFamily: FontFamily.geoBold, fontSize: 12, color: ColorsAmiin.ink,
            ))),
            TextButton(
              onPressed: () => _openInAnnuaire(lieux[i]),
              style: TextButton.styleFrom(
                foregroundColor: ColorsAmiin.ocre,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 12),
                minimumSize: Size.zero,
              ),
              child: const Text('Annuaire'),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _section({required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AmiinCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: ColorsAmiin.muted),
                const SizedBox(width: 6),
                Text(title.toUpperCase(), style: TextStyle(
                  fontFamily: FontFamily.geoBold,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: ColorsAmiin.muted,
                )),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String icon, String label) {
    final truncated = label.length > 50 ? '${label.substring(0, 47)}…' : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        border: Border.all(color: ColorsAmiin.border),
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Flexible(child: Text(truncated, style: TextStyle(
            fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid,
          ))),
        ],
      ),
    );
  }

  Widget _docRow(String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6, height: 6,
          margin: const EdgeInsets.only(top: 6, right: 8),
          decoration: const BoxDecoration(color: ColorsAmiin.ocre, shape: BoxShape.circle),
        ),
        Expanded(child: Text(name, style: TextStyle(
          fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.ink, height: 1.4,
        ))),
      ],
    );
  }

  Widget _stepRow(DemarcheStep step, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(color: ColorsAmiin.ocre, shape: BoxShape.circle),
                child: Center(child: Text('${step.order}', style: TextStyle(
                  fontFamily: FontFamily.geoBold, fontSize: 12, color: ColorsAmiin.white,
                ))),
              ),
              if (!isLast) Container(width: 2, height: 36, color: ColorsAmiin.border),
            ],
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: TextStyle(
                  fontFamily: FontFamily.geoBold, fontSize: 13, color: ColorsAmiin.ink,
                )),
                if (step.title != step.description) ...[
                  const SizedBox(height: 3),
                  Text(step.description, style: TextStyle(
                    fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid, height: 1.4,
                  )),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _organismeCard(DemarcheOrganisme org) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(org.nom, style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 13, color: ColorsAmiin.ink)),
        if (org.adresse != null && org.adresse!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 13, color: ColorsAmiin.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.adresse!, style: TextStyle(
              fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid,
            ))),
          ]),
        ],
        if (org.horaires != null && org.horaires!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.schedule_outlined, size: 13, color: ColorsAmiin.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.horaires!, style: TextStyle(
              fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid,
            ))),
          ]),
        ],
        if (org.contact != null && org.contact!.isNotEmpty) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              final c = org.contact!;
              if (c.startsWith('http')) {
                launchUrl(Uri.parse(c), mode: LaunchMode.externalApplication);
              } else if (c.contains('@')) {
                launchUrl(Uri.parse('mailto:$c'));
              }
            },
            child: Row(children: [
              Icon(Icons.contact_mail_outlined, size: 13, color: ColorsAmiin.ocre),
              const SizedBox(width: 4),
              Expanded(child: Text(org.contact!, style: TextStyle(
                fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.ocre,
              ))),
            ]),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        TextButton.icon(
          icon: const Icon(Icons.map_outlined, size: 14),
          label: const Text('Voir dans l\'annuaire'),
          style: TextButton.styleFrom(
            foregroundColor: ColorsAmiin.ocre,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 12),
          ),
          onPressed: () => _openInAnnuaire(org),
        ),
      ],
    );
  }
}

