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
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/button.dart';
import '../../services/demarches_service.dart';
import '../../services/notification_service.dart';

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
    for (final c in _noteControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ud = await demarchesService.getUserDemarche(widget.userDemarcheId);
      if (mounted) setState(() { _ud = ud; _loading = false; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Démarche introuvable.')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note enregistrée.')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rendez-vous ajouté à l\'agenda.')));
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rappel fixé le ${DateFormat('dd/MM/yyyy à HH:mm', 'fr').format(picked)}')),
    );
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
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: ColorsAmiin.terra)));
    }
    if (_ud == null) return const SizedBox();

    final ud = _ud!;
    final d = ud.demarche;
    final isFinished = ud.status == DemarcheStatus.terminee;

    // Grouper les docs par cas
    final Map<String?, List<DemarcheDocument>> docsByCas = {};
    for (final doc in d.documents) docsByCas.putIfAbsent(doc.cas, () => []).add(doc);

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(title: d.title, back: true, rightAction: IconButton(
              icon: const Icon(Icons.more_vert, color: ColorsAmiin.mid),
              onPressed: _showMenu,
            )),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: ColorsAmiin.terra,
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
                          title: 'Pièces à préparer',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final cas in docsByCas.keys) ...[
                                if (cas != null) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(color: ColorsAmiin.sand, borderRadius: BorderRadius.circular(4)),
                                    child: Text(cas, style: TextStyle(fontFamily: FontFamily.sansBold, fontSize: 10, color: ColorsAmiin.mid)),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                for (final doc in docsByCas[cas]!) _docCheckRow(doc.name),
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
                      if (d.organisme != null) ...[
                        const SizedBox(height: Spacing.md),
                        _sectionCard(
                          icon: Icons.business_outlined,
                          title: 'Où faire la démarche ?',
                          child: _organismeCard(d.organisme!),
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
                            color: ColorsAmiin.oliveLt,
                            borderRadius: BorderRadius.circular(RadiusAmiin.md),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('✓', style: TextStyle(fontSize: 18, color: ColorsAmiin.olive)),
                              const SizedBox(width: Spacing.sm),
                              Text('Démarche terminée', style: TextStyle(
                                fontFamily: FontFamily.sansBold, fontSize: 15, color: ColorsAmiin.olive,
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
                          child: Text('Rouvrir la démarche', style: TextStyle(color: ColorsAmiin.mid)),
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
                style: TextStyle(fontFamily: FontFamily.sansBold, fontSize: 13, color: ColorsAmiin.ink),
              )),
              Text('$pct %', style: TextStyle(fontFamily: FontFamily.sansBold, fontSize: 14, color: ColorsAmiin.terra)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ud.progress,
              backgroundColor: ColorsAmiin.border,
              color: ud.status == DemarcheStatus.terminee ? ColorsAmiin.olive : ColorsAmiin.terra,
              minHeight: 8,
            ),
          ),
          ...[
            const SizedBox(height: 6),
            Text(
              '${ud.demarche.category.icon} ${ud.demarche.category.label}',
              style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted),
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
            color: ColorsAmiin.white,
            borderRadius: BorderRadius.circular(RadiusAmiin.md),
            border: Border.all(color: ColorsAmiin.border),
          ),
          child: Column(
          children: [
            // Header de l'étape
            InkWell(
              onTap: () => setState(() => _expandedStep = isExpanded ? null : step.order),
              borderRadius: BorderRadius.circular(RadiusAmiin.md),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    // Checkbox validation
                    GestureDetector(
                      onTap: () => _toggleStep(step.order),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: isDone ? ColorsAmiin.terra : ColorsAmiin.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDone ? ColorsAmiin.terra : ColorsAmiin.border,
                            width: 2,
                          ),
                        ),
                        child: Center(child: isDone
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : Text('${step.order}', style: TextStyle(
                              fontFamily: FontFamily.sansBold, fontSize: 13,
                              color: ColorsAmiin.mid,
                            )),
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title, style: TextStyle(
                            fontFamily: isDone ? FontFamily.sans : FontFamily.sansBold,
                            fontSize: 14,
                            color: isDone ? ColorsAmiin.muted : ColorsAmiin.ink,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                          )),
                          if (isDone && st.completedAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Validé le ${_formatDate(st.completedAt!)}',
                              style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted),
                            ),
                          ] else if (st.agendaEventId != null) ...[
                            const SizedBox(height: 2),
                            Row(children: [
                              Icon(Icons.event, size: 12, color: ColorsAmiin.indigo),
                              const SizedBox(width: 3),
                              Text('RDV programmé', style: TextStyle(fontSize: 11, color: ColorsAmiin.indigo)),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: ColorsAmiin.muted, size: 20,
                    ),
                  ],
                ),
              ),
            ),
            // Corps expandé
            if (isExpanded) ...[
              const Divider(height: 1, color: ColorsAmiin.border),
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description complète
                    if (step.title != step.description)
                      Text(step.description, style: TextStyle(
                        fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.mid, height: 1.5,
                      )),
                    if (step.lieu != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.location_on_outlined, size: 14, color: ColorsAmiin.muted),
                        const SizedBox(width: 4),
                        Text(step.lieu!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid)),
                      ]),
                    ],

                    const SizedBox(height: Spacing.md),

                    // Note pour cette étape
                    Text('Ma note', style: TextStyle(
                      fontFamily: FontFamily.sansBold, fontSize: 11,
                      letterSpacing: 0.8, color: ColorsAmiin.muted,
                    )),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteControllers[step.order],
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Numéro de dossier, remarques, observations…',
                        hintStyle: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.muted),
                        filled: true,
                        fillColor: ColorsAmiin.ecru,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                          borderSide: const BorderSide(color: ColorsAmiin.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                          borderSide: const BorderSide(color: ColorsAmiin.border),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.ink),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.save_outlined, size: 15),
                          label: const Text('Enregistrer'),
                          style: TextButton.styleFrom(foregroundColor: ColorsAmiin.mid, textStyle: TextStyle(fontFamily: FontFamily.sansMedium, fontSize: 12)),
                          onPressed: () => _saveStepNote(step.order),
                        ),
                        const Spacer(),
                        // Rappel
                        TextButton.icon(
                          icon: const Icon(Icons.notifications_outlined, size: 15),
                          label: const Text('Rappel'),
                          style: TextButton.styleFrom(foregroundColor: ColorsAmiin.indigo, textStyle: TextStyle(fontFamily: FontFamily.sansMedium, fontSize: 12)),
                          onPressed: () => _setStepReminder(step.order),
                        ),
                        const SizedBox(width: 4),
                        // Rendez-vous
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined, size: 15),
                          label: const Text('RDV'),
                          style: TextButton.styleFrom(foregroundColor: ColorsAmiin.terra, textStyle: TextStyle(fontFamily: FontFamily.sansMedium, fontSize: 12)),
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
              Icon(icon, size: 14, color: ColorsAmiin.muted),
              const SizedBox(width: 6),
              Text(title.toUpperCase(), style: TextStyle(
                fontFamily: FontFamily.sansBold, fontSize: 10, letterSpacing: 1.2, color: ColorsAmiin.muted,
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
    fontFamily: FontFamily.sansBold, fontSize: 13, color: ColorsAmiin.ink,
  ));

  Widget _docCheckRow(String name) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 6, right: 8),
        decoration: const BoxDecoration(color: ColorsAmiin.terra, shape: BoxShape.circle)),
      Expanded(child: Text(name, style: TextStyle(
        fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.ink, height: 1.4,
      ))),
    ]),
  );

  Widget _infoChip(IconData icon, String label) {
    final truncated = label.length > 45 ? '${label.substring(0, 42)}…' : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        border: Border.all(color: ColorsAmiin.border),
        borderRadius: BorderRadius.circular(RadiusAmiin.sm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: ColorsAmiin.muted),
        const SizedBox(width: 5),
        Flexible(child: Text(truncated, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid))),
      ]),
    );
  }

  Widget _organismeCard(DemarcheOrganisme org) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(org.nom, style: TextStyle(fontFamily: FontFamily.sansBold, fontSize: 13, color: ColorsAmiin.ink)),
      if (org.adresse != null && org.adresse!.isNotEmpty) ...[
        const SizedBox(height: 5),
        Row(children: [
          Icon(Icons.location_on_outlined, size: 13, color: ColorsAmiin.muted),
          const SizedBox(width: 4),
          Expanded(child: Text(org.adresse!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid))),
        ]),
      ],
      if (org.horaires != null && org.horaires!.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.schedule_outlined, size: 13, color: ColorsAmiin.muted),
          const SizedBox(width: 4),
          Expanded(child: Text(org.horaires!, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 12, color: ColorsAmiin.mid))),
        ]),
      ],
      const SizedBox(height: Spacing.sm),
      // Bouton navigation
      TextButton.icon(
        icon: const Icon(Icons.map_outlined, size: 15),
        label: const Text('Voir dans l\'annuaire'),
        style: TextButton.styleFrom(
          foregroundColor: ColorsAmiin.terra,
          textStyle: TextStyle(fontFamily: FontFamily.sansMedium, fontSize: 13),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => context.push('/annuaire?q=${Uri.encodeComponent(org.nom)}'),
      ),
    ],
  );

  Widget _globalNotesCard(UserDemarche ud) {
    return AmiinCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sticky_note_2_outlined, size: 14, color: ColorsAmiin.muted),
            const SizedBox(width: 6),
            Text('NOTES GÉNÉRALES', style: TextStyle(
              fontFamily: FontFamily.sansBold, fontSize: 10, letterSpacing: 1.2, color: ColorsAmiin.muted,
            )),
          ]),
          const SizedBox(height: 10),
          Text(ud.notes?.isNotEmpty == true ? ud.notes! : 'Aucune note. Appuyez pour ajouter.',
            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.muted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Modifier les notes'),
            style: TextButton.styleFrom(foregroundColor: ColorsAmiin.mid, padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: ColorsAmiin.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: ColorsAmiin.mid),
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
