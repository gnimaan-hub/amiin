// ─── DemarcheDetailScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/button.dart';
import '../../services/demarches_service.dart';

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
      if (mounted) {
        setState(() {
        _demarche = d;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de charger cette démarche.')));
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _startDemarche() async {
    setState(() => _starting = true);
    try {
      await demarchesService.startDemarche(widget.demarcheId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Démarche démarrée. Retrouvez-la dans "Mes démarches".')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: ColorsAmiin.terra)));
    }
    if (_demarche == null) return const SizedBox();

    final d = _demarche!;
    final requiredDocs = d.documents.where((doc) => doc.isRequired).toList();
    final optionalDocs = d.documents.where((doc) => !doc.isRequired).toList();

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
                    Text(d.title, style: TextStyle(
                      fontFamily: FontFamily.serif,
                      fontSize: 22,
                      color: ColorsAmiin.ink,
                      height: 1.3,
                    )),
                    const SizedBox(height: Spacing.sm),
                    Text(d.summary, style: TextStyle(
                      fontFamily: FontFamily.sans,
                      fontSize: 14,
                      color: ColorsAmiin.mid,
                      height: 1.4,
                    )),
                    const SizedBox(height: Spacing.md),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        if (d.duration != null) _metaChip('⏱', d.duration!),
                        if (d.cost != null) _metaChip('💰', d.cost!),
                        _metaChip('📄', '${d.documents.length} pièce${d.documents.length > 1 ? 's' : ''}'),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    // Documents
                    AmiinCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pièces requises', style: TextStyle(
                            fontFamily: FontFamily.sansBold,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: ColorsAmiin.muted,
                          )),
                          const SizedBox(height: 8),
                          for (var doc in requiredDocs) ...[
                            _docRow(doc.name, doc.description, required: true),
                            const SizedBox(height: 4),
                          ],
                          if (optionalDocs.isNotEmpty) ...[
                            const Divider(color: ColorsAmiin.border),
                            const SizedBox(height: 4),
                            Text('Pièces optionnelles', style: TextStyle(
                              fontFamily: FontFamily.sansBold,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: ColorsAmiin.muted,
                            )),
                            const SizedBox(height: 8),
                            for (var doc in optionalDocs) ...[
                              _docRow(doc.name, doc.description, required: false),
                              const SizedBox(height: 4),
                            ],
                          ],
                        ],
                      ),
                    ),
                    // Steps
                    if (d.steps.isNotEmpty) ...[
                      const SizedBox(height: Spacing.md),
                      AmiinCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Étapes', style: TextStyle(
                              fontFamily: FontFamily.sansBold,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: ColorsAmiin.muted,
                            )),
                            const SizedBox(height: 12),
                            ...d.steps.map((step) => _stepRow(step, d.steps.last)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.md),
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

  Widget _metaChip(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        border: Border.all(color: ColorsAmiin.border),
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid)),
        ],
      ),
    );
  }

  Widget _docRow(String name, String? description, {required bool required}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(required ? '①②③④' : '○', style: TextStyle(
          fontFamily: FontFamily.sansBold,
          fontSize: 13,
          color: required ? ColorsAmiin.terra : ColorsAmiin.muted,
        )),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(
                fontFamily: FontFamily.sansMedium,
                fontSize: 13,
                color: required ? ColorsAmiin.ink : ColorsAmiin.muted,
              )),
              if (description != null)
                Text(description, style: TextStyle(
                  fontFamily: FontFamily.sans,
                  fontSize: 12,
                  color: ColorsAmiin.muted,
                )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepRow(DemarcheStep step, DemarcheStep lastStep) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(
                  color: ColorsAmiin.terra,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${step.order}', style: TextStyle(
                    fontFamily: FontFamily.sansBold,
                    fontSize: 13,
                    color: ColorsAmiin.white,
                  )),
                ),
              ),
              if (step.order != lastStep.order)
                Container(
                  width: 2,
                  height: 40,
                  color: ColorsAmiin.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: step.order != lastStep.order ? Spacing.lg : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: TextStyle(
                  fontFamily: FontFamily.sansBold,
                  fontSize: 14,
                  color: ColorsAmiin.ink,
                )),
                const SizedBox(height: 3),
                Text(step.description, style: TextStyle(
                  fontFamily: FontFamily.sans,
                  fontSize: 13,
                  color: ColorsAmiin.mid,
                  height: 1.4,
                )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}