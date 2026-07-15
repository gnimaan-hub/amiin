// ─── UserDemarcheTrackingScreen ───────────────────────────────────────────────
//
// Suivi pas-à-pas d'une démarche en cours :
//   • Timeline des étapes avec validation individuelle
//   • Notes par étape
//   • Prise de rendez-vous dans l'agenda pour une étape
//   • Rappel local par notification
//   • Informations pratiques : pièces, organisme, coût

import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/toast.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/button.dart';
import '../../services/demarches_service.dart';
import '../../services/notification_service.dart';
import '../../services/annuaire_service.dart';

class UserDemarcheTrackingScreen extends StatefulWidget {
  final String userDemarcheId;
  const UserDemarcheTrackingScreen({super.key, required this.userDemarcheId});

  @override
  State<UserDemarcheTrackingScreen> createState() => _UserDemarcheTrackingScreenState();
}

class _UserDemarcheTrackingScreenState extends State<UserDemarcheTrackingScreen> {
  UserDemarche? _ud;
  bool _loading = true;
  int? _expandedStep;
  final Map<int, TextEditingController> _noteControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _noteControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ud = await demarchesService.getUserDemarche(widget.userDemarcheId);
      if (mounted) setState(() { _ud = ud; _loading = false; });
    } catch (e) {
      if (mounted) {
        AmiinToast.show(context, 'Démarche introuvable.');
        context.pop();
      }
    }
  }

  Future<void> _toggleStep(int stepOrder) async {
    if (_ud == null) return;
    final st = _ud!.statusForStep(stepOrder);
    UserDemarche updated;
    if (st.isDone) {
      updated = await demarchesService.uncompleteStep(widget.userDemarcheId, stepOrder);
    } else {
      updated = await demarchesService.completeStep(widget.userDemarcheId, stepOrder);
    }
    if (mounted) setState(() => _ud = updated);

    if (!st.isDone && updated.status == DemarcheStatus.terminee) {
      if (mounted) _showCompletionDialog();
    }
  }

  Future<void> _saveStepNote(int stepOrder) async {
    final ctrl = _noteControllers[stepOrder];
    if (ctrl == null) return;
    await demarchesService.addStepNote(widget.userDemarcheId, stepOrder, ctrl.text);
    if (mounted) {
      AmiinToast.show(context, 'Note enregistrée.');
    }
  }

  Future<void> _scheduleStepEvent(int stepOrder) async {
    if (_ud == null) return;
    final step = _ud!.demarche.steps.firstWhere((s) => s.order == stepOrder);
    final org = _ud!.demarche.organisme;
    final result = await context.push<String>('/agenda/create?prefill_title=${Uri.encodeComponent(step.title)}&prefill_description=${Uri.encodeComponent(_ud!.demarche.title)}&prefill_location=${Uri.encodeComponent(org?.adresse ?? '')}');
    if (result != null && mounted) {
      await demarchesService.setStepAgendaEvent(widget.userDemarcheId, stepOrder, result);
      final updated = await demarchesService.getUserDemarche(widget.userDemarcheId);
      if (mounted) setState(() => _ud = updated);
      if (mounted) AmiinToast.show(context, 'Rendez-vous ajouté à l\'agenda.');
    }
  }

  Future<void> _setStepReminder(int stepOrder) async {
    if (_ud == null) return;
    final step = _ud!.demarche.steps.firstWhere((s) => s.order == stepOrder);
    final picked = await showDateTimePicker(context);
    if (picked == null || !mounted) return;
    await NotificationService().scheduleReminder(
      id: 'demarche_${widget.userDemarcheId}_$stepOrder',
      title: 'Démarche : ${_ud!.demarche.title}',
      body: 'Étape ${step.order} — ${step.title}',
      scheduledAt: picked,
    );
    if (mounted) {
      AmiinToast.show(context, 'Rappel fixé le ${DateFormat('dd/MM/yyyy à HH:mm', 'fr').format(picked)}');
    }
  }

  Future<void> _deleteDemarche() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la démarche ?'),
        content: const Text('Cette action supprime votre suivi de démarche. Le catalogue n\'est pas affecté.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await demarchesService.deleteDemarche(widget.userDemarcheId);
      if (mounted) context.pop();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 Félicitations !'),
        content: Text('Vous avez complété toutes les étapes de la démarche « ${_ud?.demarche.title} ».'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: context.ac.infoAccent)));
    }
    if (_ud == null) return const SizedBox();

    final ud = _ud!;
    final d = ud.demarche;
    final isFinished = ud.status == DemarcheStatus.terminee;

    // Grouper les docs par cas
    final Map<String?, List<DemarcheDocument>> docsByCas = {};
    for (final doc in d.documents) { docsByCas.putIfAbsent(doc.cas, () => []).add(doc); }

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(title: d.title, back: true, rightAction: IconButton(
              icon: Icon(Icons.more_vert, color: context.ac.midTone),
              onPressed: _showMenu,
            )),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: context.ac.infoAccent,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Progression globale ──────────────────────────────
                      _progressCard(ud),
                      const SizedBox(height: Spacing.md),

                      // ── Info rapide ──────────────────────────────────────
                      if (d.duration != null || d.cost != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.md),
                          child: Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: [
                              if (d.duration != null) _infoChip(Icons.schedule_outlined, d.duration!),
                              if (d.cost != null) _infoChip(Icons.payments_outlined, d.cost!),
                            ],
                          ),
                        ),

                      // ── Pièces à préparer ────────────────────────────────
                      if (d.documents.isNotEmpty)
                        _sectionCard(
                          icon: Icons.folder_outlined,
                          title: 'Pièces à préparer (${ud.checkedDocuments.length}/${d.documents.length})',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final cas in docsByCas.keys) ...[
                                if (cas != null) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(color: context.ac.surface2, borderRadius: BorderRadius.circular(4)),
                                    child: Text(cas, style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 10, color: context.ac.midTone)),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                for (final doc in docsByCas[cas]!) _docCheckRow(doc, ud),
                              ],
                            ],
                          ),
                        ),

                      // ── Étapes ───────────────────────────────────────────
                      _sectionHeader('Étapes de la démarche'),
                      const SizedBox(height: Spacing.sm),
                      for (int i = 0; i < d.steps.length; i++)
                        _stepCard(d.steps[i], ud, isLast: i == d.steps.length - 1),

                      // ── Organisme ────────────────────────────────────────
                      if (d.lieux.isNotEmpty) ...[
                        const SizedBox(height: Spacing.md),
                        _sectionCard(
                          icon: Icons.business_outlined,
                          title: d.lieux.length == 1 ? 'Où faire la démarche ?' : 'Où faire la démarche ? (${d.lieux.length} lieux)',
                          child: _organismeBody(d),
                        ),
                      ],

                      // ── Notes globales ───────────────────────────────────
                      const SizedBox(height: Spacing.md),
                      _globalNotesCard(ud),

                      const SizedBox(height: Spacing.xl),

                      // ── Bouton terminer / rouvrir ────────────────────────
                      if (!isFinished && ud.completedSteps == ud.totalSteps && ud.totalSteps > 0)
                        AmiinButton(
                          label: 'Marquer comme terminée',
                          onPressed: () async {
                            await demarchesService.updateStatus(widget.userDemarcheId, DemarcheStatus.terminee);
                            await _load();
                          },
                          fullWidth: true,
                          size: ButtonSize.lg,
                        ),
                      if (isFinished) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(Spacing.lg),
                          decoration: BoxDecoration(
                            color: context.ac.successLight,
                            borderRadius: BorderRadius.circular(RadiusAmiin.md),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('✓', style: TextStyle(fontSize: 18, color: context.ac.success)),
                              const SizedBox(width: Spacing.sm),
                              Text('Démarche terminée', style: TextStyle(
                                fontFamily: FontFamily.geoBold, fontSize: 15, color: context.ac.success,
                              )),
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextButton(
                          onPressed: () async {
                            await demarchesService.updateStatus(widget.userDemarcheId, DemarcheStatus.enCours);
                            await _load();
                          },
                          child: Text('Rouvrir la démarche', style: TextStyle(color: context.ac.midTone)),
                        ),
                      ],
                      const SizedBox(height: Spacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _progressCard(UserDemarche ud) {
    final pct = (ud.progress * 100).toInt();
    return AmiinCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(
                ud.status == DemarcheStatus.terminee
                    ? 'Démarche terminée ✓'
                    : 'En cours — ${ud.completedSteps} sur ${ud.totalSteps} étapes',
                style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 13, color: context.ac.ink),
              )),
              Text('$pct %', style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 14, color: context.ac.infoAccent)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ud.progress,
              backgroundColor: context.ac.border,
              color: ud.status == DemarcheStatus.terminee ? context.ac.success : context.ac.infoAccent,
              minHeight: 8,
            ),
          ),
          ...[
            const SizedBox(height: 6),
            Text(
              '${ud.demarche.category.icon} ${ud.demarche.category.label}',
              style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: context.ac.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepCard(DemarcheStep step, UserDemarche ud, {required bool isLast}) {
    final st = ud.statusForStep(step.order);
    final isExpanded = _expandedStep == step.order;
    final isDone = st.isDone;

    // Init contrôleur de note
    if (!_noteControllers.containsKey(step.order)) {
      _noteControllers[step.order] = TextEditingController(text: st.note ?? '');
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : Spacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusAmiin.md),
        child: Container(
          decoration: BoxDecoration(
            color: context.ac.surface,
            borderRadius: BorderRadius.circular(RadiusAmiin.md),
            border: Border.all(color: context.ac.border),
          ),
          child: Column(
          children: [
            // Header de l'étape — cercle hors InkWell pour éviter le conflit de gestes
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  // Cercle de validation — tap target indépendant
                  GestureDetector(
                    onTap: () => _toggleStep(step.order),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: isDone ? context.ac.infoAccent : context.ac.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDone ? context.ac.infoAccent : context.ac.border,
                          width: 2,
                        ),
                      ),
                      child: Center(child: isDone
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text('${step.order}', style: TextStyle(
                            fontFamily: FontFamily.geoBold, fontSize: 13,
                            color: context.ac.midTone,
                          )),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  // Titre + flèche — zone expand/collapse
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _expandedStep = isExpanded ? null : step.order),
                      borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.title, style: TextStyle(
                                  fontFamily: isDone ? FontFamily.sans : FontFamily.geoBold,
                                  fontSize: 14,
                                  color: isDone ? context.ac.muted : context.ac.ink,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                )),
                                if (isDone && st.completedAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Validé le ${_formatDate(st.completedAt!)}',
                                    style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: context.ac.muted),
                                  ),
                                ] else if (st.agendaEventId != null) ...[
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.event, size: 12, color: context.ac.infoAccent),
                                    const SizedBox(width: 3),
                                    Text('RDV programmé', style: TextStyle(fontSize: 11, color: context.ac.infoAccent)),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: context.ac.muted, size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Corps expandé
            if (isExpanded) ...[
              Divider(height: 1, color: context.ac.border),
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description complète
                    if (step.title != step.description)
                      Text(step.description, style: TextStyle(
                        fontFamily: FontFamily.sans, fontSize: 13, color: context.ac.midTone, height: 1.5,
                      )),
                    if (step.lieu != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.location_on_outlined, size: 14, color: context.ac.muted),
                        const SizedBox(width: 4),
                        Text(step.lieu!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone)),
                      ]),
                    ],

                    const SizedBox(height: Spacing.md),

                    // Note pour cette étape
                    Text('Ma note', style: TextStyle(
                      fontFamily: FontFamily.geoBold, fontSize: 11,
                      letterSpacing: 0.8, color: context.ac.muted,
                    )),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteControllers[step.order],
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Numéro de dossier, remarques, observations…',
                        hintStyle: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: context.ac.muted),
                        filled: true,
                        fillColor: context.ac.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                          borderSide: BorderSide(color: context.ac.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                          borderSide: BorderSide(color: context.ac.border),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: context.ac.ink),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.save_outlined, size: 15),
                          label: const Text('Enregistrer'),
                          style: TextButton.styleFrom(foregroundColor: context.ac.midTone, textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 12)),
                          onPressed: () => _saveStepNote(step.order),
                        ),
                        const Spacer(),
                        // Rappel
                        TextButton.icon(
                          icon: const Icon(Icons.notifications_outlined, size: 15),
                          label: const Text('Rappel'),
                          style: TextButton.styleFrom(foregroundColor: context.ac.infoAccent, textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 12)),
                          onPressed: () => _setStepReminder(step.order),
                        ),
                        const SizedBox(width: 4),
                        // Rendez-vous
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined, size: 15),
                          label: const Text('RDV'),
                          style: TextButton.styleFrom(foregroundColor: context.ac.infoAccent, textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 12)),
                          onPressed: () => _scheduleStepEvent(step.order),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),      // Column
      ),        // Container
    ),          // ClipRRect
  );            // Padding
  }

  Widget _sectionCard({required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AmiinCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: context.ac.muted),
              const SizedBox(width: 6),
              Text(title.toUpperCase(), style: TextStyle(
                fontFamily: FontFamily.geoBold, fontSize: 10, letterSpacing: 1.2, color: context.ac.muted,
              )),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(title, style: TextStyle(
    fontFamily: FontFamily.geoBold, fontSize: 13, color: context.ac.ink,
  ));

  Future<void> _toggleDocCheck(String docName) async {
    if (_ud == null) return;
    final updated = await demarchesService.toggleDocumentCheck(widget.userDemarcheId, docName);
    if (!mounted) return;
    setState(() => _ud = updated);
    final allDocs = updated.demarche.documents;
    if (allDocs.isNotEmpty && allDocs.every((d) => updated.checkedDocuments.contains(d.name))) {
      _autoCompleteDocsStep(updated);
    }
  }

  void _autoCompleteDocsStep(UserDemarche ud) {
    const keywords = ['rassembl', 'prépari', 'réunir', 'constitu', 'pièce', 'document', 'dossier'];
    final docsStep = ud.demarche.steps.where((s) {
      final t = s.title.toLowerCase();
      return keywords.any((k) => t.contains(k));
    }).firstOrNull;
    if (docsStep != null && !ud.statusForStep(docsStep.order).isDone) {
      _toggleStep(docsStep.order);
    }
  }

  Widget _docCheckRow(DemarcheDocument doc, UserDemarche ud) {
    final isChecked = ud.checkedDocuments.contains(doc.name);
    return GestureDetector(
      onTap: () => _toggleDocCheck(doc.name),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: isChecked ? context.ac.success : context.ac.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(doc.name, style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: 13,
                color: isChecked ? context.ac.muted : context.ac.ink,
                decoration: isChecked ? TextDecoration.lineThrough : null,
                height: 1.4,
              )),
              if (doc.description != null && doc.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _firstSentence(doc.description!),
                  style: TextStyle(fontSize: 11, color: context.ac.muted, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          )),
        ]),
      ),
    );
  }

  String _firstSentence(String text) {
    final s = text.split('.').first.trim();
    return s.length > 80 ? '${s.substring(0, 77)}…' : s;
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
            Icon(Icons.location_on_outlined, size: 13, color: context.ac.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.adresse!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone))),
          ]),
          const SizedBox(height: 4),
        ],
        if (org.horaires != null && org.horaires!.isNotEmpty) ...[
          Row(children: [
            Icon(Icons.schedule_outlined, size: 13, color: context.ac.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(org.horaires!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone))),
          ]),
          const SizedBox(height: Spacing.sm),
        ],
        for (int i = 0; i < lieux.length; i++) ...[
          if (i > 0) Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Divider(height: 1, color: context.ac.border),
          ),
          Row(children: [
            Expanded(child: Text(lieux[i].nom, style: TextStyle(
              fontFamily: FontFamily.geoBold, fontSize: 12, color: context.ac.ink,
            ))),
            TextButton(
              onPressed: () => _openInAnnuaire(lieux[i]),
              style: TextButton.styleFrom(
                foregroundColor: context.ac.infoAccent,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
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

  Widget _infoChip(IconData icon, String label) {
    final truncated = label.length > 45 ? '${label.substring(0, 42)}…' : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.ac.surface,
        border: Border.all(color: context.ac.border),
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: context.ac.muted),
        const SizedBox(width: 5),
        Flexible(child: Text(truncated, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone))),
      ]),
    );
  }

  Widget _organismeCard(DemarcheOrganisme org) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(org.nom, style: TextStyle(fontFamily: FontFamily.geoBold, fontSize: 13, color: context.ac.ink)),
      if (org.adresse != null && org.adresse!.isNotEmpty) ...[
        const SizedBox(height: 5),
        Row(children: [
          Icon(Icons.location_on_outlined, size: 13, color: context.ac.muted),
          const SizedBox(width: 4),
          Expanded(child: Text(org.adresse!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone))),
        ]),
      ],
      if (org.horaires != null && org.horaires!.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.schedule_outlined, size: 13, color: context.ac.muted),
          const SizedBox(width: 4),
          Expanded(child: Text(org.horaires!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: context.ac.midTone))),
        ]),
      ],
      const SizedBox(height: Spacing.sm),
      // Bouton navigation
      TextButton.icon(
        icon: const Icon(Icons.map_outlined, size: 15),
        label: const Text('Voir dans l\'annuaire'),
        style: TextButton.styleFrom(
          foregroundColor: context.ac.infoAccent,
          textStyle: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 13),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _openInAnnuaire(org),
      ),
    ],
  );

  Widget _globalNotesCard(UserDemarche ud) {
    return AmiinCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sticky_note_2_outlined, size: 14, color: context.ac.muted),
            const SizedBox(width: 6),
            Text('NOTES GÉNÉRALES', style: TextStyle(
              fontFamily: FontFamily.geoBold, fontSize: 10, letterSpacing: 1.2, color: context.ac.muted,
            )),
          ]),
          const SizedBox(height: 10),
          Text(ud.notes?.isNotEmpty == true ? ud.notes! : 'Aucune note. Appuyez pour ajouter.',
            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: context.ac.muted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Modifier les notes'),
            style: TextButton.styleFrom(foregroundColor: context.ac.midTone, padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: TextStyle(fontFamily: FontFamily.sans, fontSize: 12)),
            onPressed: () => _editGlobalNotes(ud),
          ),
        ],
      ),
    );
  }

  Future<void> _editGlobalNotes(UserDemarche ud) async {
    final ctrl = TextEditingController(text: ud.notes ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes générales'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Numéro de dossier, contacts, échéances…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (result != null && mounted) {
      await demarchesService.updateGlobalNotes(widget.userDemarcheId, result);
      await _load();
    }
  }

  Future<void> _openInAnnuaire(DemarcheOrganisme org) async {
    final results = await annuaireService.searchSimilar(org.nom);
    if (!mounted) return;
    if (results.isNotEmpty) {
      context.go('/annuaire/${results.first.id}');
    } else {
      AmiinToast.show(context, '« ${org.nom} » introuvable dans l\'annuaire.');
      context.go('/annuaire');
    }
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: context.ac.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.description_outlined, color: context.ac.midTone),
              title: const Text('Voir la fiche démarche'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/demarches/${_ud!.demarcheId}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Supprimer ce suivi', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteDemarche();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy', 'fr').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}

// ── Picker date+heure (helper) ────────────────────────────────────────────────

Future<DateTime?> showDateTimePicker(BuildContext context) async {
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime.now().add(const Duration(days: 1)),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    locale: const Locale('fr'),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: const TimeOfDay(hour: 9, minute: 0),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

