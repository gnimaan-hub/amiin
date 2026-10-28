// ─── Export des données utilisateur ─────────────────────────────────────────
// Rassemble tout ce qu'Amiin conserve sur l'appareil (conversations, notes,
// agenda, démarches suivies, profil et préférences) dans un fichier JSON
// lisible, puis ouvre la feuille de partage du système pour l'enregistrer ou
// l'envoyer (droit d'accès / portabilité des données).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'agenda_service.dart';
import 'auth_service.dart';
import 'demarches_service.dart';
import 'memory_service.dart';
import 'notes_service.dart';
import 'settings_service.dart';

class ExportService {
  Future<Map<String, dynamic>> buildExport() async {
    final user = authService.currentUser;
    final events = await agendaService.getEvents('1970-01-01T00:00:00', '2100-12-31T23:59:59');
    final notes = await notesService.getNotes();
    final demarches = await demarchesService.getUserDemarches();

    return {
      'format': 'amiin-export-v1',
      'exported_at': DateTime.now().toIso8601String(),
      'account': user == null
          ? null
          : {'id': user.id, 'email': user.email, 'display_name': user.displayName},
      'profile': settingsService.profileContextPayload,
      'preferences': settingsService.userPreferencesPayload,
      'conversations': [
        for (final m in MemoryService().getAllMessages())
          {
            'role': m.role,
            'content': m.content,
            'timestamp': m.timestamp.toIso8601String(),
          },
      ],
      'notes': [for (final n in notes) n.toJson()],
      'agenda': [for (final e in events) e.toJson()],
      'demarches': [for (final d in demarches) d.toJson()],
    };
  }

  /// Écrit le fichier dans le dossier temporaire puis ouvre le partage.
  Future<void> exportAndShare() async {
    final data = await buildExport();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/amiin-mes-donnees-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Mes données Amiin',
    );
  }
}

final exportService = ExportService();
