// ─── CreateEventScreen (création + édition) ─────────────────────────────────

import 'package:flutter/material.dart';
import '../../widgets/horizon_line.dart';
import '../../widgets/toast.dart';
import 'package:intl/intl.dart';
import '../../theme/colors.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/button.dart';
import '../../services/agenda_service.dart';

class CreateEventScreen extends StatefulWidget {
  final AmiinEvent? initialEvent; // si fourni, mode édition
  final String? initialDate;
  
  const CreateEventScreen({super.key, this.initialEvent, this.initialDate});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  late DateTime _startDate;
  late DateTime _endDate;
  EventCategory _category = EventCategory.admin;
  int _reminder = 30;
  bool _loading = false;

  List<({EventCategory category, String label, Color color})> get _categories => [
    (category: EventCategory.admin, label: 'Administratif', color: context.ac.secretariatAccent),
    (category: EventCategory.personal, label: 'Personnel', color: context.ac.success),
    (category: EventCategory.health, label: 'Santé', color: context.ac.secretariatAccent),
    (category: EventCategory.education, label: 'Éducation', color: CategoryColors.education),
    (category: EventCategory.other, label: 'Autre', color: context.ac.muted),
  ];

  final List<({int value, String label})> _reminders = [
    (value: 0, label: 'Au moment'),
    (value: 15, label: '15 min avant'),
    (value: 30, label: '30 min avant'),
    (value: 60, label: '1 h avant'),
    (value: 1440, label: '1 jour avant'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialEvent != null) {
      // Mode édition : pré-remplir
      _titleController.text = widget.initialEvent!.title;
      _descController.text = widget.initialEvent!.description ?? '';
      _locationController.text = widget.initialEvent!.location ?? '';
      _startDate = DateTime.parse(widget.initialEvent!.startDate);
      _endDate = DateTime.parse(widget.initialEvent!.endDate);
      _category = widget.initialEvent!.category;
      _reminder = widget.initialEvent!.reminder ?? 30;
    } else {
      // Mode création
      final now = DateTime.now();
      _startDate = widget.initialDate != null ? DateTime.parse(widget.initialDate!) : now;
      _endDate = _startDate.add(const Duration(hours: 1));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(bool isStart) async {
    final now = isStart ? _startDate : _endDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedTime == null || !mounted) return;
    final newDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      if (isStart) {
        _startDate = newDate;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        _endDate = newDate;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AmiinToast.show(context, 'Le titre est requis.', success: false);
      return;
    }
    if (!_endDate.isAfter(_startDate)) {
      AmiinToast.show(context, 'La date de fin doit être après la date de début.', success: false);
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.initialEvent != null) {
        // Mise à jour
        await agendaService.updateEvent(widget.initialEvent!.id, {
          'title': _titleController.text.trim(),
          'description': _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          'startDate': _startDate.toIso8601String(),
          'endDate': _endDate.toIso8601String(),
          'category': _category,
          'location': _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
          'reminder': _reminder,
        });
        if (mounted) {
          AmiinToast.show(context, 'Événement modifié');
        }
      } else {
        // Création
        await agendaService.createEvent(CreateEventPayload(
          title: _titleController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          startDate: _startDate.toIso8601String(),
          endDate: _endDate.toIso8601String(),
          category: _category,
          location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
          reminder: _reminder,
        ));
        if (mounted) {
          AmiinToast.show(context, 'Événement créé');
        }
      }
      if (mounted) { Navigator.pop(context); }
    } catch (e) {
      if (mounted) {
        AmiinToast.show(context, 'Erreur : ${e.toString()}', success: false);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEvent != null;
    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              mode: AmiinMode.secretariat,
              title: isEditing ? 'Modifier événement' : 'Nouvel événement',
              back: true,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  children: [
                    _buildField('Titre *', TextField(
                      controller: _titleController,
                      decoration: _inputDecoration('Ex. Rendez-vous DGPN'),
                    )),
                    const SizedBox(height: Spacing.lg),
                    _buildField('Description', TextField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: _inputDecoration('Détails optionnels…'),
                    )),
                    const SizedBox(height: Spacing.lg),
                    _buildField('Lieu', TextField(
                      controller: _locationController,
                      decoration: _inputDecoration("Ex. Ministère de l'Intérieur"),
                    )),
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(child: _buildField('Début', GestureDetector(
                          onTap: () => _selectDateTime(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                            decoration: _boxDecoration(),
                            child: Text(DateFormat('yyyy-MM-dd HH:mm').format(_startDate)),
                          ),
                        ))),
                        const SizedBox(width: Spacing.md),
                        Expanded(child: _buildField('Fin', GestureDetector(
                          onTap: () => _selectDateTime(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                            decoration: _boxDecoration(),
                            child: Text(DateFormat('yyyy-MM-dd HH:mm').format(_endDate)),
                          ),
                        ))),
                      ],
                    ),
                    const SizedBox(height: Spacing.lg),
                    _buildField('Catégorie', Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: _categories.map((cat) => FilterChip(
                        label: Text(cat.label),
                        selected: _category == cat.category,
                        onSelected: (_) => setState(() => _category = cat.category),
                        backgroundColor: Colors.white,
                        selectedColor: cat.color,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _category == cat.category ? Colors.white : context.ac.midTone,
                          fontFamily: FontFamily.geoMedium,
                        ),
                      )).toList(),
                    )),
                    const SizedBox(height: Spacing.lg),
                    _buildField('Rappel', Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: _reminders.map((rem) => FilterChip(
                        label: Text(rem.label),
                        selected: _reminder == rem.value,
                        onSelected: (_) => setState(() => _reminder = rem.value),
                        backgroundColor: Colors.white,
                        selectedColor: context.ac.secretariatAccent,
                        labelStyle: TextStyle(
                          color: _reminder == rem.value ? Colors.white : context.ac.midTone,
                          fontFamily: FontFamily.geoMedium,
                        ),
                      )).toList(),
                    )),
                    const SizedBox(height: Spacing.xl),
                    AmiinButton(
                      label: isEditing ? 'Mettre à jour' : 'Enregistrer',
                      onPressed: _save,
                      loading: _loading,
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

  Widget _buildField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: FontFamily.geoBold,
            fontSize: 10,
            letterSpacing: 1.2,
            color: context.ac.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: context.ac.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RadiusAmiin.md),
      borderSide: BorderSide(color: context.ac.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RadiusAmiin.md),
      borderSide: BorderSide(color: context.ac.border),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
  );

  BoxDecoration _boxDecoration() => BoxDecoration(
    color: context.ac.surface,
    borderRadius: BorderRadius.circular(RadiusAmiin.md),
    border: Border.all(color: context.ac.border),
  );
}
