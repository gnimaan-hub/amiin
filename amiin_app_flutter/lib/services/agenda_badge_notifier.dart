import 'package:flutter/foundation.dart';
import 'agenda_service.dart';

final ValueNotifier<int> agendaTodayCount = ValueNotifier(0);

Future<void> refreshAgendaBadge() async {
  try {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final events = await agendaService.getEvents(
      start.toIso8601String(),
      end.toIso8601String(),
    );
    agendaTodayCount.value = events.length;
  } catch (_) {}
}
