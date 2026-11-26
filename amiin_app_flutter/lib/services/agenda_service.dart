// ─── Agenda Service (local Hive) ────────────────────────────────────────────

import 'package:flutter/foundation.dart' show Listenable;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'user_scope.dart';
import 'memory_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import '../models/user_action.dart';

enum EventCategory {
  admin,
  personal,
  health,
  education,
  other,
}

class AmiinEvent {
  final String id;
  final String title;
  final String? description;
  final String startDate; // ISO 8601
  final String endDate;
  final EventCategory category;
  final String? location;
  final int? reminder;
  final bool? createdByAgent;
  final String? agentContext;

  AmiinEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.category,
    this.location,
    this.reminder,
    this.createdByAgent,
    this.agentContext,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'startDate': startDate,
        'endDate': endDate,
        'category': category.name,
        'location': location,
        'reminder': reminder,
        'createdByAgent': createdByAgent,
        'agentContext': agentContext,
      };

  factory AmiinEvent.fromJson(Map<String, dynamic> json) => AmiinEvent(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        startDate: json['startDate'],
        endDate: json['endDate'],
        category: EventCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => EventCategory.other,
        ),
        location: json['location'],
        reminder: json['reminder'],
        createdByAgent: json['createdByAgent'],
        agentContext: json['agentContext'],
      );
}

class CreateEventPayload {
  final String title;
  final String? description;
  final String startDate;
  final String endDate;
  final EventCategory category;
  final String? location;
  final int? reminder;
  final bool createdByAgent;
  final String? agentContext;

  CreateEventPayload({
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.category,
    this.location,
    this.reminder,
    this.createdByAgent = false,
    this.agentContext,
  });
}

// Adaptateur Hive manuel (pas besoin de build_runner)
class AmiinEventAdapter extends TypeAdapter<AmiinEvent> {
  @override
  final int typeId = 10;

  @override
  AmiinEvent read(BinaryReader reader) {
    final map = reader.readMap();
    return AmiinEvent.fromJson(map.cast<String, dynamic>());
  }

  @override
  void write(BinaryWriter writer, AmiinEvent obj) {
    writer.writeMap(obj.toJson());
  }
}

class AgendaService {
  // Box du compte actif (voir user_scope.dart) : rouverte sur celle du
  // nouveau compte au premier accès après un changement de compte.
  final _scoped = ScopedBox<AmiinEvent>('agenda_events');
  late Box<AmiinEvent> _box;

  Future<void> _init() async {
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(AmiinEventAdapter());
    }
    _box = await _scoped.box;
  }

  /// Notifie à chaque changement de la box — permet aux écrans (Home, Agenda,
  /// badge) de se rafraîchir automatiquement, y compris quand Amiin crée
  /// un événement depuis le chat — et au changement de compte.
  Listenable get listenable => _scoped.changes;

  /// Événements dont la période [startDate, endDate] chevauche [from, to].
  /// Un événement multi-jours apparaît ainsi sur chacun de ses jours.
  Future<List<AmiinEvent>> getEvents(String from, String to) async {
    await _init();
    final fromDate = DateTime.parse(from);
    final toDate = DateTime.parse(to);
    return _box.values.where((e) {
      final start = DateTime.parse(e.startDate);
      DateTime end;
      try {
        end = DateTime.parse(e.endDate);
      } catch (_) {
        end = start;
      }
      if (end.isBefore(start)) end = start;
      return !start.isAfter(toDate) && !end.isBefore(fromDate);
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Future<AmiinEvent> getEvent(String id) async {
    await _init();
    final event = _box.get(id);
    if (event == null) throw Exception('Event not found');
    return event;
  }

  Future<AmiinEvent> createEvent(CreateEventPayload payload) async {
    await _init();
    final event = AmiinEvent(
      id: const Uuid().v4(),
      title: payload.title,
      description: payload.description,
      startDate: payload.startDate,
      endDate: payload.endDate,
      category: payload.category,
      location: payload.location,
      reminder: payload.reminder,
      createdByAgent: payload.createdByAgent,
      agentContext: payload.agentContext,
    );
    await _box.put(event.id, event);

    _scheduleNotification(event);

    MemoryService().recordAction(UserAction(
      type: 'event',
      objectId: event.id,
      summary: 'Rendez-vous : ${event.title} le ${event.startDate}',
      timestamp: DateTime.now(),
      context: 'Action manuelle depuis l\'agenda',
    ));
    return event;
  }

  Future<AmiinEvent> updateEvent(String id, Map<String, dynamic> payload) async {
    await _init();
    final old = await getEvent(id);
    final updated = AmiinEvent(
      id: old.id,
      title: payload['title'] ?? old.title,
      description: payload['description'] ?? old.description,
      startDate: payload['startDate'] ?? old.startDate,
      endDate: payload['endDate'] ?? old.endDate,
      category: payload['category'] ?? old.category,
      location: payload['location'] ?? old.location,
      reminder: payload['reminder'] ?? old.reminder,
      createdByAgent: old.createdByAgent,
      agentContext: old.agentContext,
    );
    await _box.put(id, updated);
    // Reprogrammer la notification après modification
    await notificationService.cancelReminder(id);
    _scheduleNotification(updated);
    return updated;
  }

  Future<void> deleteEvent(String id) async {
    await _init();
    await notificationService.cancelReminder(id);
    await _box.delete(id);
  }

  void _scheduleNotification(AmiinEvent event) {
    if (event.reminder == null || event.reminder! < 0) return;
    if (!settingsService.notifMaster || !settingsService.notifAgenda) return;
    final start = DateTime.parse(event.startDate);
    final notifAt = start.subtract(Duration(minutes: event.reminder!));
    notificationService.scheduleReminder(
      id: event.id,
      title: event.title,
      body: event.reminder == 0
          ? 'Votre événement commence maintenant.'
          : 'Rappel dans ${event.reminder} min.',
      scheduledAt: notifAt,
    );
  }

  /// Annule tous les rappels d'agenda (notifications désactivées).
  Future<void> cancelAllReminders() async {
    await _init();
    for (final e in _box.values) {
      await notificationService.cancelReminder(e.id);
    }
  }

  /// Reprogramme les rappels des événements à venir (changement de compte :
  /// les notifications de l'ancien compte ont été annulées).
  Future<void> rescheduleAllReminders() async {
    await _init();
    final now = DateTime.now();
    for (final e in _box.values) {
      final start = DateTime.tryParse(e.startDate);
      if (start != null && start.isAfter(now)) _scheduleNotification(e);
    }
  }

  // Méthode publique d'initialisation
  Future<void> init() async => _init();

  /// Efface tout l'agenda du compte actif.
  Future<void> clearAll() async {
    await _init();
    await _box.clear();
  }

}

final agendaService = AgendaService();