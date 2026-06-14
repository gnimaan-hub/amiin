// ─── Notes Service (local Hive) ─────────────────────────────────────────────

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'hive_utils.dart';
import 'memory_service.dart';
import '../models/user_action.dart';

typedef NoteTag = String;

class AmiinNote {
  final String id;
  final String title;
  final String content;
  final List<NoteTag> tags;
  final String createdAt;
  final String updatedAt;
  final bool? createdByAgent;
  final String? agentContext;
  final bool? isPinned;

  AmiinNote({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.createdByAgent,
    this.agentContext,
    this.isPinned,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdByAgent': createdByAgent,
        'agentContext': agentContext,
        'isPinned': isPinned,
      };

  factory AmiinNote.fromJson(Map<String, dynamic> json) => AmiinNote(
        id: json['id'],
        title: json['title'],
        content: json['content'],
        tags: List<String>.from(json['tags'] ?? []),
        createdAt: json['createdAt'],
        updatedAt: json['updatedAt'],
        createdByAgent: json['createdByAgent'],
        agentContext: json['agentContext'],
        isPinned: json['isPinned'],
      );
}

class CreateNotePayload {
  final String title;
  final String content;
  final List<NoteTag>? tags;
  final bool? isPinned;
  final bool? createdByAgent;
  final String? agentContext;

  CreateNotePayload({
    required this.title,
    required this.content,
    this.tags,
    this.isPinned,
    this.createdByAgent,
    this.agentContext,
  });
}

// Adaptateur Hive
class AmiinNoteAdapter extends TypeAdapter<AmiinNote> {
  @override
  final int typeId = 11;

  @override
  AmiinNote read(BinaryReader reader) {
    final map = reader.readMap();
    return AmiinNote.fromJson(map.cast<String, dynamic>());
  }

  @override
  void write(BinaryWriter writer, AmiinNote obj) {
    writer.writeMap(obj.toJson());
  }
}

class NotesService {
  static const String _boxName = 'notes_box';
  late Box<AmiinNote> _box;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(AmiinNoteAdapter());
    }
    _box = await openBoxSafe<AmiinNote>(_boxName);
    _initialized = true;
  }

  /// Notifie à chaque changement de la box — rafraîchissement automatique
  /// des écrans quand Amiin crée/modifie/supprime une note.
  ValueListenable<Box<AmiinNote>> get listenable => _box.listenable();

  // Normalisation accent-insensible pour le français (é→e, à→a, etc.)
  static String _norm(String s) => s.toLowerCase()
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('ñ', 'n');

  Future<List<AmiinNote>> getNotes({String? query, String? tag}) async {
    await _init();
    var notes = _box.values.toList();
    if (query != null && query.isNotEmpty) {
      final q = _norm(query);
      notes = notes.where((n) =>
          _norm(n.title).contains(q) ||
          _norm(n.content).contains(q)).toList();
    }
    if (tag != null && tag.isNotEmpty) {
      notes = notes.where((n) => n.tags.contains(tag)).toList();
    }
    notes.sort((a, b) => DateTime.parse(b.updatedAt).compareTo(DateTime.parse(a.updatedAt)));
    return notes;
  }

  Future<AmiinNote> getNote(String id) async {
    await _init();
    final note = _box.get(id);
    if (note == null) throw Exception('Note not found');
    return note;
  }

  Future<AmiinNote> createNote(CreateNotePayload payload) async {
    await _init();
    final now = DateTime.now().toIso8601String();
    final note = AmiinNote(
      id: const Uuid().v4(),
      title: payload.title,
      content: payload.content,
      tags: payload.tags ?? [],
      createdAt: now,
      updatedAt: now,
      createdByAgent: payload.createdByAgent ?? false,
      agentContext: payload.agentContext,
      isPinned: payload.isPinned ?? false,
    );
    await _box.put(note.id, note);

    MemoryService().recordAction(UserAction(
      type: 'note',
      objectId: note.id,
      summary: 'Note : ${note.title}',
      timestamp: DateTime.now(),
      context: 'Action manuelle depuis les notes',
    ));
    return note;
  }

  Future<AmiinNote> updateNote(String id, Map<String, dynamic> payload) async {
    await _init();
    final old = await getNote(id);
    final updated = AmiinNote(
      id: old.id,
      title: payload['title'] ?? old.title,
      content: payload['content'] ?? old.content,
      tags: payload['tags'] ?? old.tags,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      createdByAgent: payload['createdByAgent'] ?? old.createdByAgent,
      agentContext: payload['agentContext'] ?? old.agentContext,
      isPinned: payload['isPinned'] ?? old.isPinned,
    );
    await _box.put(id, updated);
    return updated;
  }

  Future<void> deleteNote(String id) async {
    await _init();
    await _box.delete(id);
  }

  Future<List<NoteTag>> getTags() async {
    await _init();
    final allTags = <NoteTag>{};
    for (var note in _box.values) {
      allTags.addAll(note.tags);
    }
    return allTags.toList();
  }

  // Méthode publique d'initialisation
  Future<void> init() async => _init();

}

final notesService = NotesService();