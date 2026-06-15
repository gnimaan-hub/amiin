// ─── ChatController ──────────────────────────────────────────────────────────
//
// Cœur agentique d'Amiin, extrait de l'UI pour être testable et survivre
// au cycle de vie des widgets :
//   • envoi de message + boucle d'outils multi-passes (lecture locale Hive),
//   • exécution des outils d'écriture (agenda, notes, démarches, annuaire),
//   • confirmation utilisateur avant toute action destructive,
//   • system prompt : date fraîche + contexte météo/localisation préchargé
//     + mémoire des actions récentes,
//   • persistance et bornage de l'historique de conversation.
//
// L'écran (ChatScreen) ne garde que : STT/TTS, scroll, rendu.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/user_action.dart';
import 'agenda_service.dart';
import 'amiin_api_service.dart';
import 'annuaire_service.dart';
import 'connectivity_service.dart';
import 'demarches_service.dart';
import 'location_service.dart';
import 'memory_service.dart';
import 'notes_service.dart';

/// Signal global : l'accueil demande au chat de démarrer l'écoute vocale.
/// Incrémenté avant la navigation vers /chat ; le ChatScreen y réagit.
final ValueNotifier<int> chatListenRequest = ValueNotifier<int>(0);

/// Notification UI émise par le contrôleur (affichée en toast par l'écran).
class ChatNotice {
  final String message;
  final bool success;
  ChatNotice(this.message, {this.success = true});
}

/// Action destructive demandée par Amiin, en attente de confirmation.
class PendingDeletion {
  final AgentAction action;
  final String description;
  PendingDeletion(this.action, this.description);
}

typedef NoteResult = ({String id, String title, String content});
typedef EventResult = ({String id, String title, String date});

class ChatController extends ChangeNotifier {
  ChatController({AmiinApiService? api}) : _api = api ?? AmiinApiService() {
    _messages.addAll(
        MemoryService().getRecentMessages(limit: loadedHistoryLimit));
    unawaited(_refreshEnvContextIfStale());
    unawaited(_loadDemarchesCatalog());
  }

  final AmiinApiService _api;
  final _uuid = const Uuid();

  // ── Réglages ──────────────────────────────────────────────────────────────
  static const int loadedHistoryLimit = 100; // messages chargés au démarrage
  static const int promptHistoryLimit = 10; // messages envoyés à l'API
  static const int _maxPasses = 3; // bornes de la boucle d'outils
  static const Set<String> _readTools = {'get_events', 'get_notes', 'get_demarche_detail'};
  static const Duration _envTtl = Duration(minutes: 15);

  // ── État conversation ─────────────────────────────────────────────────────
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  bool _loading = false; // phase recherche (avant le 1er token)
  bool _streaming = false; // phase génération (tokens en cours)
  String _streamStatus = '';
  bool _cancelled = false;

  bool get isLoading => _loading;
  bool get isStreaming => _streaming;
  bool get isBusy => _loading || _streaming;
  String get streamStatus => _streamStatus;

  // Objets créés/modifiés par Amiin dans cette session (clé = message.id)
  final Map<String, NoteResult> noteResults = {};
  final Map<String, EventResult> eventResults = {};

  // Métriques d'usage par message (tokens Claude/Jina, outils) — clé = message.id
  final Map<String, Map<String, dynamic>> messageUsage = {};

  // Suggestion proactive de note (une seule à la fois)
  String? noteSuggestionMsgId;
  String? noteSuggestionText;
  String? _noteSuggestionContent;

  // Actions destructives en attente de confirmation (attachées à un message)
  String? pendingDeletionMsgId;
  final List<PendingDeletion> pendingDeletions = [];

  // Notifications UI (toasts)
  final _notices = StreamController<ChatNotice>.broadcast();
  Stream<ChatNotice> get notices => _notices.stream;
  void _notice(String message, {bool success = true}) {
    if (!_notices.isClosed) _notices.add(ChatNotice(message, success: success));
  }

  // Position GPS préchargée (météo gérée côté backend via OWM)
  double _lat = 11.5721;
  double _lon = 43.1456;
  bool _located = false;
  DateTime? _gpsRefreshedAt;
  bool _gpsFetching = false;

  // Catalogue des démarches (chargé une fois au démarrage)
  String _demarchesCatalog = '';

  Future<void> _loadDemarchesCatalog() async {
    try {
      _demarchesCatalog = await demarchesService.getCatalogSummaryForAmiin();
    } catch (_) {
      _demarchesCatalog = '';
    }
  }

  @override
  void dispose() {
    _notices.close();
    _api.cancelStream();
    super.dispose();
  }

  // ── Gestion des messages ──────────────────────────────────────────────────

  void _addMessage(ChatMessage message, {bool persist = true}) {
    _messages.add(message);
    if (persist) MemoryService().saveMessage(message);
    notifyListeners();
  }

  void _updateLastMessage(ChatMessage message, {bool persist = true}) {
    if (_messages.isEmpty) return;
    _messages.last = message;
    if (persist) MemoryService().saveMessage(message);
    notifyListeners();
  }

  /// Démarre une nouvelle conversation (efface l'historique).
  void clearConversation() {
    _api.cancelStream();
    _messages.clear();
    MemoryService().deleteAllMessages();
    noteResults.clear();
    eventResults.clear();
    _clearNoteSuggestion(notify: false);
    pendingDeletions.clear();
    pendingDeletionMsgId = null;
    _loading = false;
    _streaming = false;
    _streamStatus = '';
    notifyListeners();
  }

  // ── Annulation ────────────────────────────────────────────────────────────

  void cancel() {
    if (!isBusy) return;
    _cancelled = true;
    _api.cancelStream();
    // Persister le contenu partiel déjà affiché pour ne rien perdre
    if (_messages.isNotEmpty && _messages.last.role == 'agent' && _streaming) {
      MemoryService().saveMessage(_messages.last);
    }
    _loading = false;
    _streaming = false;
    _streamStatus = '';
    notifyListeners();
    _notice('Requête annulée');
  }

  // ── Envoi d'un message ────────────────────────────────────────────────────

  /// Envoie [text] à Amiin et orchestre la boucle d'outils.
  /// Retourne la réponse finale (pour le TTS), ou null si annulé / en erreur.
  Future<String?> sendMessage(String text) async {
    text = text.trim();
    if (text.isEmpty || isBusy) return null;

    if (!connectivityService.isOnline) {
      _notice('Vous êtes hors ligne — vérifiez votre connexion.',
          success: false);
      return null;
    }

    // Historique AVANT d'ajouter le nouveau message
    final history = _messages.length <= promptHistoryLimit
        ? _messages
        : _messages.sublist(_messages.length - promptHistoryLimit);
    final apiHistory = history
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList()
        .cast<Map<String, String>>();

    _addMessage(ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    ));
    _loading = true;
    _streaming = false;
    _streamStatus = '';
    _cancelled = false;
    notifyListeners();

    // Rafraîchir le contexte en tâche de fond pour le prochain message ;
    // celui-ci part immédiatement avec le contexte déjà disponible.
    unawaited(_refreshEnvContextIfStale());
    final systemPrompt = _buildSystemPrompt();

    final streamId = _uuid.v4();
    final msgTimestamp = DateTime.now();
    final allActions = <AgentAction>[];
    bool bubbleCreated = false;
    String base = ''; // texte des passes précédentes
    String content = ''; // texte cumulé affiché

    List<Map<String, dynamic>>? pendingReads;
    List<Map<String, dynamic>>? toolResults;
    ChatStreamDone? lastDone; // conserve le dernier done pour les métriques

    try {
      for (var pass = 1; pass <= _maxPasses; pass++) {
        final passBuffer = StringBuffer();
        ChatStreamDone? done;

        await for (final event in _api.sendMessageStream(
          message: text,
          history: apiHistory,
          system: systemPrompt,
          pendingToolUses: pendingReads,
          toolResults: toolResults,
          lat: _lat,
          lon: _lon,
        )) {
          if (_cancelled) break;

          if (event is ChatStreamStatus) {
            _streamStatus = event.text;
            notifyListeners();
          } else if (event is ChatStreamToken) {
            passBuffer.write(event.text);
            content = base + passBuffer.toString();
            final msg = ChatMessage(
              id: streamId,
              role: 'agent',
              content: content,
              timestamp: msgTimestamp,
            );
            if (!bubbleCreated) {
              bubbleCreated = true;
              _loading = false;
              _streaming = true;
              // persist:false pendant le stream (pas d'écriture Hive par token)
              _addMessage(msg, persist: false);
            } else {
              _updateLastMessage(msg, persist: false);
            }
          } else if (event is ChatStreamDone) {
            done = event;
            lastDone = event;
            break;
          } else if (event is ChatStreamError) {
            throw Exception(event.detail);
          }
        }

        if (_cancelled) break;

        final calls = done?.toolCalls ?? const <Map<String, dynamic>>[];
        final reads = calls
            .where((tc) => _readTools.contains(tc['name']))
            .toList();
        allActions.addAll(calls
            .where((tc) => !_readTools.contains(tc['name']))
            .map((tc) => AgentAction(
                  id: tc['id'] as String? ?? _uuid.v4(),
                  name: tc['name'] as String? ?? '',
                  input:
                      (tc['input'] as Map?)?.cast<String, dynamic>() ?? {},
                )));

        // Fin de boucle : stream coupé sans `done`, pas d'outils de lecture,
        // ou plafond de passes atteint.
        if (done == null || reads.isEmpty || pass == _maxPasses) break;

        // Passe suivante : conserver le texte déjà produit comme préambule
        // (pas de remplacement brutal de la bulle).
        base = content.isEmpty ? '' : '$content\n\n';
        _streaming = false;
        _loading = true;
        _streamStatus = 'Récupération des données…';
        notifyListeners();

        toolResults = await _executeReadToolCalls(reads);
        pendingReads = reads;
      }

      if (_cancelled) {
        _cancelled = false;
        return null;
      }

      // Stocker les métriques d'usage (tokens Claude/Jina) pour l'affichage
      if (lastDone?.usage != null) {
        messageUsage[streamId] = lastDone!.usage!;
      }

      // ── Finalisation inconditionnelle (même si la connexion est tombée) ──
      final reply = content;
      if (bubbleCreated) {
        _updateLastMessage(
          ChatMessage(
            id: streamId,
            role: 'agent',
            content: reply,
            timestamp: msgTimestamp,
            actions: allActions.isNotEmpty ? allActions : null,
          ),
          persist: true,
        );
      } else if (allActions.isEmpty) {
        // Aucun token ni action reçus : la connexion est probablement tombée
        _addMessage(ChatMessage(
          id: streamId,
          role: 'agent',
          content:
              'Désolé, la connexion a été interrompue avant que je puisse répondre. Réessayez.',
          timestamp: msgTimestamp,
        ));
      } else {
        // Claude n'a produit aucun texte mais a appelé des outils.
        // On persiste un message de confirmation pour que l'historique
        // soit complet — sans ça, Claude répète les mêmes outils au prochain
        // message car il croit que la demande n'a pas été traitée.
        _addMessage(ChatMessage(
          id: streamId,
          role: 'agent',
          content: _buildActionConfirmation(allActions),
          timestamp: msgTimestamp,
          actions: allActions,
        ));
      }
      _loading = false;
      _streaming = false;
      _streamStatus = '';
      notifyListeners();

      // Suggestion proactive de note
      final hasNoteAction = allActions
          .any((a) => a.name == 'create_note' || a.name == 'update_note');
      if (!hasNoteAction && _shouldSuggestNote(reply, text)) {
        noteSuggestionMsgId = streamId;
        noteSuggestionText = _getSuggestionText(reply);
        _noteSuggestionContent = reply;
        notifyListeners();
      }

      if (allActions.isNotEmpty) {
        await _executeActions(allActions, contextText: text, msgId: streamId);
      }

      return reply.isEmpty ? null : reply;
    } catch (e) {
      if (_cancelled ||
          (e is DioException && e.type == DioExceptionType.cancel)) {
        _cancelled = false;
        _loading = false;
        _streaming = false;
        _streamStatus = '';
        notifyListeners();
        return null;
      }
      debugPrint('Erreur sendMessage: $e');
      _addMessage(ChatMessage(
        id: _uuid.v4(),
        role: 'agent',
        content:
            "Désolé, je n'arrive pas à joindre le service Amiin pour le moment. "
            'Vérifiez votre connexion et réessayez.',
        timestamp: DateTime.now(),
      ));
      _loading = false;
      _streaming = false;
      _streamStatus = '';
      notifyListeners();
      return null;
    }
  }

  // ── Outils de lecture (exécutés localement sur Hive) ─────────────────────

  Future<List<Map<String, dynamic>>> _executeReadToolCalls(
      List<Map<String, dynamic>> toolCalls) async {
    final results = <Map<String, dynamic>>[];

    for (final tc in toolCalls) {
      final input = (tc['input'] as Map?)?.cast<String, dynamic>() ?? {};
      String content;
      try {
        switch (tc['name'] as String?) {
          case 'get_events':
            final now = DateTime.now();
            final fromDate = input['from_date'] as String? ??
                now.toIso8601String();
            final toDate = input['to_date'] as String? ??
                now.add(const Duration(days: 30)).toIso8601String();
            final events = await agendaService.getEvents(fromDate, toDate);
            if (events.isEmpty) {
              content = 'Aucun événement pour cette période.';
            } else {
              final buf = StringBuffer('Événements :\n');
              for (final e in events) {
                final start = DateTime.parse(e.startDate);
                buf.write(
                    '- [ID:${e.id}] ${e.title} (${DateFormat('dd/MM/yyyy HH:mm').format(start)})');
                if (e.location != null && e.location!.isNotEmpty) {
                  buf.write(' à ${e.location}');
                }
                if (e.description != null && e.description!.isNotEmpty) {
                  final desc = e.description!.length > 100
                      ? '${e.description!.substring(0, 100)}…'
                      : e.description!;
                  buf.write(' : $desc');
                }
                buf.write('\n');
              }
              content = buf.toString();
            }
          case 'get_notes':
            final query = input['query'] as String?;
            final tag = input['tag'] as String?;
            final notes = await notesService.getNotes(query: query, tag: tag);
            if (notes.isEmpty) {
              content = 'Aucune note trouvée.';
            } else {
              final buf = StringBuffer('Notes :\n');
              final maxNotes = notes.length > 30 ? 30 : notes.length;
              for (var i = 0; i < maxNotes; i++) {
                final n = notes[i];
                buf.write('- [ID:${n.id}] ${n.title}');
                if (n.content.isNotEmpty) {
                  final preview = n.content.length > 200
                      ? '${n.content.substring(0, 200)}…'
                      : n.content;
                  buf.write(' : $preview');
                }
                buf.write('\n');
              }
              if (notes.length > 30) {
                buf.write('(… et ${notes.length - 30} autres notes)\n');
              }
              content = buf.toString();
            }
          case 'get_demarche_detail':
            final demarcheId = input['demarche_id'] as String? ?? '';
            content = await demarchesService.getDemarcheDetailForAmiin(demarcheId);

          default:
            content = 'Outil inconnu : ${tc['name']}';
        }
      } catch (e) {
        content = 'Erreur lors de la récupération : $e';
      }

      results.add({
        'tool_use_id': tc['id'],
        'content': content,
      });
    }

    return results;
  }

  // ── Outils d'écriture ─────────────────────────────────────────────────────

  /// Libellé convivial d'un outil (affiché en chip dans la bulle).
  static String actionLabel(String name) {
    switch (name) {
      case 'create_event':
        return '📅 Événement créé';
      case 'update_event':
        return '📅 Événement modifié';
      case 'delete_event':
        return '🗑️ Événement supprimé';
      case 'create_note':
        return '📝 Note créée';
      case 'update_note':
        return '📝 Note modifiée';
      case 'delete_note':
        return '🗑️ Note supprimée';
      case 'start_demarche':
        return '📋 Démarche démarrée';
      case 'search_services':
        return '🔎 Recherche annuaire';
      case 'get_events':
        return '📅 Agenda consulté';
      case 'get_notes':
        return '📝 Notes consultées';
      case 'get_demarche_detail':
        return '📋 Démarche consultée';
      default:
        return name;
    }
  }

  String _buildActionConfirmation(List<AgentAction> actions) {
    const labels = {
      'create_event': 'Rendez-vous créé',
      'update_event': 'Rendez-vous mis à jour',
      'delete_event': 'Rendez-vous supprimé',
      'create_note': 'Note enregistrée',
      'update_note': 'Note mise à jour',
      'delete_note': 'Note supprimée',
      'start_demarche': 'Démarche démarrée',
      'search_services': 'Annuaire consulté',
    };
    final parts = actions
        .map((a) => labels[a.name] ?? a.name)
        .toSet() // déduplique si plusieurs fois le même outil
        .toList();
    return '${parts.join(' et ')}. C\'est fait !';
  }

  Future<void> _executeActions(List<AgentAction> actions,
      {String? contextText, String? msgId}) async {
    for (final action in actions) {
      try {
        switch (action.name) {
          case 'create_event':
            final payload = CreateEventPayload(
              title: action.input['title'] as String? ?? 'Événement',
              description: action.input['description'] as String?,
              startDate: action.input['start_date'] as String? ??
                  DateTime.now().toIso8601String(),
              endDate: action.input['end_date'] as String? ??
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
              category:
                  _categoryFromString(action.input['category'] as String?),
              location: action.input['location'] as String?,
              reminder: action.input['reminder_minutes'] as int?,
              createdByAgent: true,
              agentContext: contextText,
            );
            final event = await agendaService.createEvent(payload);
            MemoryService().recordAction(UserAction(
              type: 'event',
              objectId: event.id,
              summary: 'Rendez-vous : ${event.title} le ${event.startDate}',
              timestamp: DateTime.now(),
              context: contextText ?? 'Créé par Amiin',
            ));
            if (msgId != null) {
              eventResults[msgId] = (
                id: event.id,
                title: event.title,
                date: event.startDate,
              );
              notifyListeners();
            }
            _notice('Événement créé : ${event.title}');

          case 'update_event':
            final eventId = action.input['event_id'] as String;
            final updatePayload = <String, dynamic>{};
            if (action.input.containsKey('title')) {
              updatePayload['title'] = action.input['title'];
            }
            if (action.input.containsKey('description')) {
              updatePayload['description'] = action.input['description'];
            }
            if (action.input.containsKey('start_date')) {
              updatePayload['startDate'] = action.input['start_date'];
            }
            if (action.input.containsKey('end_date')) {
              updatePayload['endDate'] = action.input['end_date'];
            }
            if (action.input.containsKey('category')) {
              updatePayload['category'] =
                  _categoryFromString(action.input['category'] as String?);
            }
            if (action.input.containsKey('location')) {
              updatePayload['location'] = action.input['location'];
            }
            if (action.input.containsKey('reminder_minutes')) {
              updatePayload['reminder'] = action.input['reminder_minutes'];
            }
            final updatedEvent =
                await agendaService.updateEvent(eventId, updatePayload);
            MemoryService().recordAction(UserAction(
              type: 'event_update',
              objectId: updatedEvent.id,
              summary:
                  'Événement modifié : ${updatedEvent.title} le ${updatedEvent.startDate}',
              timestamp: DateTime.now(),
              context: contextText ?? 'Modifié par Amiin',
            ));
            if (msgId != null) {
              eventResults[msgId] = (
                id: updatedEvent.id,
                title: updatedEvent.title,
                date: updatedEvent.startDate,
              );
              notifyListeners();
            }
            _notice('Événement modifié : ${updatedEvent.title}');

          // ── Actions destructives : confirmation utilisateur requise ──────
          case 'delete_event':
            final eventId = action.input['event_id'] as String;
            try {
              final event = await agendaService.getEvent(eventId);
              pendingDeletions.add(PendingDeletion(
                  action, 'Événement « ${event.title} »'));
              pendingDeletionMsgId = msgId;
              notifyListeners();
            } catch (_) {
              _notice('Événement introuvable', success: false);
            }

          case 'delete_note':
            final noteId = action.input['note_id'] as String;
            try {
              final note = await notesService.getNote(noteId);
              pendingDeletions
                  .add(PendingDeletion(action, 'Note « ${note.title} »'));
              pendingDeletionMsgId = msgId;
              notifyListeners();
            } catch (_) {
              _notice('Note introuvable', success: false);
            }

          case 'create_note':
            final payload = CreateNotePayload(
              title: action.input['title'] as String? ?? "Note d'Amiin",
              content: action.input['content'] as String? ?? '',
              tags: (action.input['tags'] as List?)?.cast<String>(),
              isPinned: action.input['is_pinned'] as bool?,
              createdByAgent: true,
              agentContext: contextText,
            );
            final note = await notesService.createNote(payload);
            MemoryService().recordAction(UserAction(
              type: 'note',
              objectId: note.id,
              summary: 'Note : ${note.title}',
              timestamp: DateTime.now(),
              context: contextText ?? 'Créé par Amiin',
            ));
            if (msgId != null) {
              noteResults[msgId] = (
                id: note.id,
                title: note.title,
                content: note.content,
              );
              notifyListeners();
            } else {
              _notice('Note créée : ${note.title}');
            }

          case 'update_note':
            final noteId = action.input['note_id'] as String;
            final updatePayload = <String, dynamic>{};
            if (action.input.containsKey('title')) {
              updatePayload['title'] = action.input['title'];
            }
            if (action.input.containsKey('content')) {
              updatePayload['content'] = action.input['content'];
            }
            if (action.input.containsKey('tags')) {
              updatePayload['tags'] =
                  (action.input['tags'] as List?)?.cast<String>();
            }
            if (action.input.containsKey('is_pinned')) {
              updatePayload['isPinned'] = action.input['is_pinned'];
            }
            updatePayload['createdByAgent'] = true;
            updatePayload['agentContext'] = contextText;
            final updatedNote =
                await notesService.updateNote(noteId, updatePayload);
            MemoryService().recordAction(UserAction(
              type: 'note_update',
              objectId: updatedNote.id,
              summary: 'Note modifiée : ${updatedNote.title}',
              timestamp: DateTime.now(),
              context: contextText ?? 'Modifié par Amiin',
            ));
            noteResults[msgId ?? updatedNote.id] = (
              id: updatedNote.id,
              title: updatedNote.title,
              content: updatedNote.content,
            );
            notifyListeners();

          case 'start_demarche':
            final demarcheId = action.input['demarche_id'];
            final userDemarche =
                await demarchesService.startDemarche(demarcheId);
            MemoryService().recordAction(UserAction(
              type: 'demarche',
              objectId: userDemarche.id,
              summary: 'Démarche "${userDemarche.demarche.title}" démarrée',
              timestamp: DateTime.now(),
              context: contextText ?? 'Lancée par Amiin',
            ));
            _notice('Démarche « ${userDemarche.demarche.title} » démarrée');

          case 'search_services':
            final query = action.input['query'];
            final services = await annuaireService.search(query);
            if (services.isNotEmpty) {
              MemoryService().recordAction(UserAction(
                type: 'service_search',
                objectId: '',
                summary:
                    '${services.length} service(s) trouvé(s) pour "$query"',
                timestamp: DateTime.now(),
                context: contextText ?? 'Recherche par Amiin',
              ));
              _notice('${services.length} service(s) trouvé(s) pour « $query »');
            }
        }
      } catch (e) {
        debugPrint('Erreur action ${action.name}: $e');
        _notice('Erreur lors de l\'action : ${actionLabel(action.name)}',
            success: false);
      }
    }
  }

  // ── Confirmation des suppressions ─────────────────────────────────────────

  Future<void> confirmPendingDeletions() async {
    final items = List.of(pendingDeletions);
    pendingDeletions.clear();
    pendingDeletionMsgId = null;
    notifyListeners();

    for (final p in items) {
      try {
        switch (p.action.name) {
          case 'delete_event':
            final eventId = p.action.input['event_id'] as String;
            final event = await agendaService.getEvent(eventId);
            await agendaService.deleteEvent(eventId);
            MemoryService().recordAction(UserAction(
              type: 'event_delete',
              objectId: eventId,
              summary: 'Événement supprimé : ${event.title}',
              timestamp: DateTime.now(),
              context: 'Supprimé par Amiin (confirmé)',
            ));
            _notice('Événement supprimé : ${event.title}');
          case 'delete_note':
            final noteId = p.action.input['note_id'] as String;
            final note = await notesService.getNote(noteId);
            await notesService.deleteNote(noteId);
            MemoryService().recordAction(UserAction(
              type: 'note_delete',
              objectId: noteId,
              summary: 'Note supprimée : ${note.title}',
              timestamp: DateTime.now(),
              context: 'Supprimé par Amiin (confirmé)',
            ));
            _notice('Note supprimée : ${note.title}');
        }
      } catch (e) {
        debugPrint('Erreur suppression confirmée: $e');
        _notice('Impossible de supprimer ${p.description}', success: false);
      }
    }
  }

  void dismissPendingDeletions() {
    pendingDeletions.clear();
    pendingDeletionMsgId = null;
    notifyListeners();
    _notice('Suppression annulée');
  }

  // ── System prompt ─────────────────────────────────────────────────────────

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final buffer = StringBuffer()
      ..writeln(
          'Date et heure actuelles : ${DateFormat('EEEE d MMMM yyyy à HH:mm', 'fr').format(now)}');

    buffer.writeln(_located
        ? 'Localisation : ${_lat.toStringAsFixed(2)}, ${_lon.toStringAsFixed(2)}'
        : 'Localisation : Djibouti-ville (11.5721, 43.1456)');

    // Catalogue des démarches administratives
    if (_demarchesCatalog.isNotEmpty) {
      buffer.writeln('\n$_demarchesCatalog');
      buffer.writeln(
        'Pour obtenir le détail complet d\'une démarche (étapes, pièces, organisme, coût), '
        'utilise l\'outil get_demarche_detail avec son ID (ex: "egouv_102").',
      );
    }

    // Mémoire : actions récentes de l'utilisateur
    final actions = MemoryService().getRecentActions(limit: 8);
    if (actions.isNotEmpty) {
      buffer.writeln("\nActions récentes de l'utilisateur (mémoire) :");
      for (final a in actions) {
        buffer.writeln(
            '- ${DateFormat('dd/MM').format(a.timestamp)} : ${a.summary}');
      }
    }

    return buffer.toString();
  }

  Future<void> _refreshEnvContextIfStale() async {
    if (_gpsFetching) return;
    if (_gpsRefreshedAt != null &&
        DateTime.now().difference(_gpsRefreshedAt!) < _envTtl) {
      return;
    }
    _gpsFetching = true;
    try {
      final pos = await LocationService().getCurrentLocation();
      _lat = pos.latitude;
      _lon = pos.longitude;
      _located = true;
      _gpsRefreshedAt = DateTime.now();
    } catch (e) {
      debugPrint('GPS indisponible: $e');
    } finally {
      _gpsFetching = false;
    }
  }

  EventCategory _categoryFromString(String? str) {
    switch (str) {
      case 'admin':
        return EventCategory.admin;
      case 'personal':
        return EventCategory.personal;
      case 'health':
        return EventCategory.health;
      case 'education':
        return EventCategory.education;
      default:
        return EventCategory.other;
    }
  }

  // ── Suggestion proactive de note ──────────────────────────────────────────

  void _clearNoteSuggestion({bool notify = true}) {
    noteSuggestionMsgId = null;
    noteSuggestionText = null;
    _noteSuggestionContent = null;
    if (notify) notifyListeners();
  }

  void dismissNoteSuggestion() => _clearNoteSuggestion();

  Future<void> createNoteFromSuggestion(String msgId) async {
    final msgIndex = _messages.indexWhere((m) => m.id == msgId);
    final userMsgContent =
        msgIndex > 0 ? _messages[msgIndex - 1].content : '';
    final content = _noteSuggestionContent ?? '';
    final title = _extractNoteTitle(userMsgContent, content);

    _clearNoteSuggestion();

    try {
      final note = await notesService.createNote(CreateNotePayload(
        title: title,
        content: content,
        createdByAgent: true,
        agentContext: userMsgContent.isEmpty ? null : userMsgContent,
      ));
      MemoryService().recordAction(UserAction(
        type: 'note',
        objectId: note.id,
        summary: 'Note : ${note.title}',
        timestamp: DateTime.now(),
        context: userMsgContent.isEmpty ? 'Créé par Amiin' : userMsgContent,
      ));
      noteResults[msgId] = (
        id: note.id,
        title: note.title,
        content: note.content,
      );
      notifyListeners();
      _notice('Note créée : ${note.title}');
    } catch (_) {
      _notice('Impossible de créer la note', success: false);
    }
  }

  bool _shouldSuggestNote(String reply, String userMsg) {
    // Jamais si l'utilisateur a déjà demandé une note explicitement
    final lower = userMsg.toLowerCase();
    if (lower.contains('note') &&
        (lower.contains('crè') ||
            lower.contains('écris') ||
            lower.contains('garde') ||
            lower.contains('sauvegarde'))) {
      return false;
    }

    // Réponse > 600 chars = contenu suffisamment substantiel pour une note.
    if (reply.length > 600) return true;

    // Détection markdown structuré
    final hasTitle = RegExp(r'\n#{1,3} ').hasMatch(reply);
    final hasNumberedList = RegExp(r'\n\d+\.').hasMatch(reply);
    if (hasTitle && hasNumberedList) return true;

    return false;
  }

  String _getSuggestionText(String reply) {
    if (RegExp(r'\n#{1,3} ').hasMatch(reply)) {
      return 'Je peux créer une note avec ce plan détaillé, si tu veux ?';
    }
    if (RegExp(r'\n\d+\.').hasMatch(reply)) {
      return 'Je peux créer une note avec ces étapes, si tu veux ?';
    }
    if (reply.split('\n- ').length > 3) {
      return 'Je peux créer une note avec cette liste, si tu veux ?';
    }
    if (reply.length > 600) {
      return 'Je peux créer une note avec ce résumé, si tu veux ?';
    }
    return 'Je peux créer une note avec ces informations, si tu veux ?';
  }

  String _extractNoteTitle(String userMsg, String content) {
    // Extraire "sur X" / "de X" / "des X" depuis le message utilisateur
    final m = RegExp(
      r"(?:sur|de |des |du |à propos (?:du|de|des|d'))\s*(.{3,60})",
      caseSensitive: false,
    ).firstMatch(userMsg);
    if (m != null) {
      final candidate =
          m.group(1)!.trim().split(RegExp(r'[,\.\?\!]')).first.trim();
      if (candidate.length >= 3) {
        return candidate[0].toUpperCase() + candidate.substring(1);
      }
    }
    // Première ligne non vide du contenu (sans markdown)
    for (final line in content.split('\n')) {
      final clean = line
          .replaceAll(RegExp(r'^#{1,6}\s*'), '')
          .replaceAll('**', '')
          .trim();
      if (clean.length >= 3 && clean.length <= 80) return clean;
    }
    return "Note d'Amiin";
  }
}
