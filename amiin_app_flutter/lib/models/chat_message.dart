import 'package:hive/hive.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 1)
class ChatMessage {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String role;
  @HiveField(2)
  final String content;
  @HiveField(3)
  final DateTime timestamp;
  @HiveField(4)
  final List<AgentAction>? actions;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.actions,
  });
}

@HiveType(typeId: 2)
class AgentAction {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final Map<String, dynamic> input;

  AgentAction({
    required this.id,
    required this.name,
    required this.input,
  });
}