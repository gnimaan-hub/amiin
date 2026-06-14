// ─── EventDetailScreen ───────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import './create_event_screen.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import '../../widgets/tag.dart';
import '../../services/agenda_service.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  AmiinEvent? _event;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    setState(() => _loading = true);
    try {
      final event = await agendaService.getEvent(widget.eventId);
      if (mounted) {
        setState(() {
          _event = event;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de charger l’événement.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer'),
        content: const Text('Êtes-vous sûr de vouloir supprimer cet événement ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await agendaService.deleteEvent(widget.eventId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Événement supprimé'), backgroundColor: ColorsAmiin.olive),
          );
          Navigator.pop(context); // retour à l'agenda
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de la suppression : $e'), backgroundColor: ColorsAmiin.terra),
          );
        }
      }
    }
  }

  String _categoryLabel(EventCategory category) {
    switch (category) {
      case EventCategory.admin:
        return 'Administratif';
      case EventCategory.personal:
        return 'Personnel';
      case EventCategory.health:
        return 'Santé';
      case EventCategory.education:
        return 'Éducation';
      default:
        return 'Autre';
    }
  }

  String _reminderText(int? minutes) {
    if (minutes == null) return 'Aucun';
    if (minutes == 0) return 'Au moment';
    if (minutes < 60) return '$minutes min avant';
    if (minutes == 1440) return '1 jour avant';
    return '${minutes ~/ 60}h avant';
  }

  void _editEvent() {
    if (_event == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEventScreen(initialEvent: _event),
      ),
    ).then((_) => _loadEvent()); // recharger après modification
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: ColorsAmiin.terra)));
    }
    if (_event == null) return const SizedBox();

    final start = DateTime.parse(_event!.startDate);
    final end = DateTime.parse(_event!.endDate);

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: 'Événement',
              back: true,
              rightAction: SizedBox(
                width: 88,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: ColorsAmiin.terra),
                      onPressed: _editEvent,
                      tooltip: 'Modifier',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: ColorsAmiin.terra),
                      onPressed: _deleteEvent,
                      tooltip: 'Supprimer',
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _event!.title,
                            style: TextStyle(
                              fontFamily: FontFamily.serif,
                              fontSize: 24,
                              color: ColorsAmiin.ink,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (_event!.createdByAgent == true)
                          const AmiinTag(label: 'Créé par Amiin', variant: TagVariant.terra),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    AmiinCard(
                      child: Column(
                        children: [
                          _infoRow('📅', DateFormat('EEEE d MMMM yyyy', 'fr').format(start)),
                          const SizedBox(height: Spacing.sm),
                          _infoRow('🕐', '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}'),
                          if (_event!.location != null) ...[
                            const SizedBox(height: Spacing.sm),
                            _infoRow('📍', _event!.location!),
                          ],
                          const SizedBox(height: Spacing.sm),
                          _infoRow('🏷', _categoryLabel(_event!.category)),
                          const SizedBox(height: Spacing.sm),
                          _infoRow('🔔', _reminderText(_event!.reminder)),
                        ],
                      ),
                    ),
                    if (_event!.description != null) ...[
                      const SizedBox(height: Spacing.md),
                      AmiinCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description',
                              style: TextStyle(
                                fontFamily: FontFamily.sansBold,
                                fontSize: 10,
                                letterSpacing: 1.2,
                                color: ColorsAmiin.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _event!.description!,
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 14,
                                color: ColorsAmiin.mid,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_event!.agentContext != null) ...[
                      const SizedBox(height: Spacing.md),
                      AmiinCard(
                        variant: CardVariant.default_,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contexte Amiin',
                              style: TextStyle(
                                fontFamily: FontFamily.sansBold,
                                fontSize: 10,
                                letterSpacing: 1.2,
                                color: ColorsAmiin.terraDk,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _event!.agentContext!,
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 13,
                                color: ColorsAmiin.terraDk,
                                height: 1.5,
                              ),
                            ),
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

  Widget _infoRow(String icon, String label) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FontFamily.sans,
              fontSize: 14,
              color: ColorsAmiin.ink,
            ),
          ),
        ),
      ],
    );
  }
}