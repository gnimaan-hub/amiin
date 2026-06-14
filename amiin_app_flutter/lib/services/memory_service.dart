import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/user_action.dart';
import 'hive_utils.dart';

class MemoryService {
  static final MemoryService _instance = MemoryService._internal();
  factory MemoryService() => _instance;
  MemoryService._internal();

  late Box<ChatMessage> _chatBox;
  late Box<UserAction> _actionBox;

  /// Bornes de rétention : évite que les boxes grossissent sans limite
  /// (démarrage lent, mémoire) après des mois d'utilisation.
  static const int maxStoredMessages = 500;
  static const int maxStoredActions = 200;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(AgentActionAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserActionAdapter());
    _chatBox = await openBoxSafe<ChatMessage>('chat_messages');
    _actionBox = await openBoxSafe<UserAction>('user_actions');
  }

  // ----- Messages -----

  List<ChatMessage> getAllMessages() {
    final messages = _chatBox.values.toList();
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
    _chatBox.put(message.id, message);
    _pruneMessages();
  }

  void deleteAllMessages() {
    _chatBox.clear();
  }

  void _pruneMessages() {
    if (_chatBox.length <= maxStoredMessages) return;
    final all = getAllMessages();
    final excess = all.length - maxStoredMessages;
    for (var i = 0; i < excess; i++) {
      _chatBox.delete(all[i].id);
    }
  }

  // ----- Actions utilisateur -----

  List<UserAction> getAllActions() {
    final actions = _actionBox.values.toList();
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
    _actionBox.put(const Uuid().v4(), action);
    _pruneActions();
  }

  void _pruneActions() {
    if (_actionBox.length <= maxStoredActions) return;
    // Supprimer les plus anciennes
    final entries = _actionBox.toMap().entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
    final excess = entries.length - maxStoredActions;
    for (var i = 0; i < excess; i++) {
      _actionBox.delete(entries[i].key);
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
