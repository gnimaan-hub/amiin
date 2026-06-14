import 'package:hive/hive.dart';

part 'user_action.g.dart';

@HiveType(typeId: 0)
class UserAction {
  @HiveField(0)
  final String type; // "event", "note", "demarche", "service_search"

  @HiveField(1)
  final String objectId; // ID de l'événement, note, etc. (vide pour recherche)

  @HiveField(2)
  final String summary; // Titre ou résumé lisible

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String? context; // Phrase du chat ou "action manuelle"

  UserAction({
    required this.type,
    required this.objectId,
    required this.summary,
    required this.timestamp,
    this.context,
  });
}