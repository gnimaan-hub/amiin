import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/user_action.dart';
import 'settings_service.dart';
import 'user_scope.dart';

class MemoryService {
  static final MemoryService _instance = MemoryService._internal();
  factory MemoryService() => _instance;
  MemoryService._internal();

  // Boxes du compte actif (voir user_scope.dart). Accès synchrones : tant
  // qu'elles ne sont pas ouvertes, lectures vides et écritures ignorées.
  final _chat = ScopedBox<ChatMessage>('chat_messages');
  final _actions = ScopedBox<UserAction>('user_actions');
  Box<ChatMessage>? get _chatBox => _chat.current;
  Box<UserAction>? get _actionBox => _actions.current;

  /// Bornes de rétention : évite que les boxes grossissent sans limite
  /// (démarrage lent, mémoire) après des mois d'utilisation.
  static const int maxStoredMessages = 500;
  static const int maxStoredActions = 200;

  /// Ouvre les boxes du compte actif (appelé par UserScope).
  Future<void> init() async {
    registerUserDataAdapters();
    await Future.wait([_chat.box, _actions.box]);
  }

  // ----- Messages -----

  List<ChatMessage> getAllMessages() {
    final messages = _chatBox?.values.toList() ?? <ChatMessage>[];
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  /// Les [limit] messages les plus récents, en ordre chronologique.
  /// Évite de charger tout l'historique en mémoire au démarrage.
  List<ChatMessage> getRecentMessages({int limit = 100}) {
    final all = getAllMessages();
    return all.length <= limit ? all : all.sublist(all.length - limit);
  }

  void saveMessage(ChatMessage message) {
    final box = _chatBox;
    if (box == null) return;
    box.put(message.id, message);
    _pruneMessages();
  }

  void deleteAllMessages() {
    _chatBox?.clear();
  }

  /// Efface conversations et mémoire d'actions du compte actif.
  Future<void> clearAll() async {
    await init();
    await Future.wait([_chatBox!.clear(), _actionBox!.clear()]);
  }

  void _pruneMessages() {
    final box = _chatBox;
    if (box == null || box.length <= maxStoredMessages) return;
    final all = getAllMessages();
    final excess = all.length - maxStoredMessages;
    for (var i = 0; i < excess; i++) {
      box.delete(all[i].id);
    }
  }

  // ----- Actions utilisateur -----

  List<UserAction> getAllActions() {
    final actions = _actionBox?.values.toList() ?? <UserAction>[];
    actions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return actions;
  }

  /// Les [limit] actions les plus récentes (la plus récente d'abord).
  /// Injectées dans le system prompt pour donner une mémoire à Amiin.
  List<UserAction> getRecentActions({int limit = 8}) {
    final all = getAllActions();
    return all.length <= limit ? all : all.sublist(0, limit);
  }

  void recordAction(UserAction action) {
    final box = _actionBox;
    // Mémoire long terme désactivée dans les réglages : rien n'est retenu.
    if (box == null || !settingsService.memoryEnabled) return;
    box.put(const Uuid().v4(), action);
    _pruneActions();
  }

  void _pruneActions() {
    final box = _actionBox;
    if (box == null || box.length <= maxStoredActions) return;
    // Supprimer les plus anciennes
    final entries = box.toMap().entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
    final excess = entries.length - maxStoredActions;
    for (var i = 0; i < excess; i++) {
      box.delete(entries[i].key);
    }
  }

  // Pour la recherche simple (phase 1)
  List<UserAction> searchActionsByKeyword(String keyword) {
    return getAllActions().where((a) =>
      a.summary.toLowerCase().contains(keyword.toLowerCase()) ||
      a.type.toLowerCase().contains(keyword.toLowerCase())
    ).toList();
  }
}
