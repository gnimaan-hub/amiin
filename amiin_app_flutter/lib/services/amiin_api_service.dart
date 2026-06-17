import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_client.dart';

// ── Événements SSE du stream ──────────────────────────────────────────────────

sealed class ChatStreamEvent {}

/// Progression avant les premiers tokens ("Recherche…", "Amiin réfléchit…")
class ChatStreamStatus extends ChatStreamEvent {
  final String text;
  ChatStreamStatus(this.text);
}

/// Un fragment de texte généré par Claude
class ChatStreamToken extends ChatStreamEvent {
  final String text;
  ChatStreamToken(this.text);
}

/// Fin du stream : tool calls + sources + durée + métriques usage
class ChatStreamDone extends ChatStreamEvent {
  final List<Map<String, dynamic>> toolCalls;
  final List<Map<String, dynamic>> sources;
  final double processingTime;
  final Map<String, dynamic>? usage;

  ChatStreamDone({
    required this.toolCalls,
    required this.sources,
    required this.processingTime,
    this.usage,
  });
}

/// Erreur renvoyée par le serveur dans le stream
class ChatStreamError extends ChatStreamEvent {
  final String detail;
  ChatStreamError(this.detail);
}

// ── Parsing d'une ligne SSE ───────────────────────────────────────────────────

/// Parse une ligne SSE (`data: {...}`) en événement typé.
/// Retourne null pour les lignes vides, malformées ou de type inconnu.
/// Fonction pure → testable unitairement.
ChatStreamEvent? parseSseLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('data: ')) return null;
  final payload = trimmed.substring(6).trim();
  if (payload.isEmpty) return null;

  try {
    final json = jsonDecode(payload);
    if (json is! Map<String, dynamic>) return null;
    switch (json['type'] as String?) {
      case 'status':
        return ChatStreamStatus(json['text'] as String? ?? '');
      case 'token':
        return ChatStreamToken(json['text'] as String? ?? '');
      case 'done':
        return ChatStreamDone(
          toolCalls:
              (json['tool_calls'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          sources:
              (json['sources'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          processingTime: (json['processing_time'] as num?)?.toDouble() ?? 0.0,
          usage: json['usage'] as Map<String, dynamic>?,
        );
      case 'error':
        return ChatStreamError(json['detail'] as String? ?? 'Erreur inconnue');
      default:
        return null;
    }
  } catch (_) {
    // Ligne SSE mal formée — ignorée
    return null;
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class AmiinApiService {
  final Dio _dio = api;

  /// Token d'annulation du stream courant.
  CancelToken? _activeCancelToken;

  /// Sans données pendant ce délai, le stream est considéré comme mort
  /// (réseau coupé en cours de génération) et se termine proprement :
  /// l'appelant finalise alors avec le contenu déjà reçu.
  static const Duration _inactivityTimeout = Duration(seconds: 45);

  // ── API non-streaming (conservée pour compatibilité / fallback) ───────────

  Future<({String reply, List<Map<String, dynamic>> toolCalls})> sendMessage({
    required String message,
    required List<Map<String, String>> history,
    String? system,
    bool expand = true,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post(
      '/chat',
      data: {
        'message': message,
        'history': history,
        'system': system,
        'expand': expand,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode != 200) {
      throw Exception('Erreur API: ${response.statusCode}');
    }
    final data = response.data as Map<String, dynamic>;
    return (
      reply: data['reply'] as String,
      toolCalls: (data['tool_calls'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }

  // ── Annulation du stream actif ────────────────────────────────────────────

  void cancelStream() {
    _activeCancelToken?.cancel('Annulé par l\'utilisateur');
    _activeCancelToken = null;
  }

  // ── API streaming SSE (dio) ───────────────────────────────────────────────

  /// Envoie le message et reçoit la réponse en SSE.
  ///
  /// Séquence d'événements :
  ///   [ChatStreamStatus] "Recherche…"
  ///   [ChatStreamStatus] "Amiin réfléchit…"
  ///   [ChatStreamToken]  × N  (fragments de texte)
  ///   [ChatStreamDone]   (tool_calls, sources, processing_time)
  ///
  /// Le stream peut se terminer SANS [ChatStreamDone] si la connexion tombe :
  /// l'appelant doit toujours finaliser son état après la boucle.
  /// Appeler [cancelStream] pour annuler à tout moment.
  Stream<ChatStreamEvent> sendMessageStream({
    required String message,
    required List<Map<String, String>> history,
    String? system,
    bool expand = true,
    List<Map<String, dynamic>>? pendingToolUses,
    List<Map<String, dynamic>>? toolResults,
    double? lat,
    double? lon,
    Map<String, dynamic>? userPreferences,
  }) async* {
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    try {
      final body = <String, dynamic>{
        'message': message,
        'history': history,
        'system': system,
        'expand': expand,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (userPreferences != null) 'user_preferences': userPreferences,
      };
      if (pendingToolUses != null) body['pending_tool_uses'] = pendingToolUses;
      if (toolResults != null) body['tool_results'] = toolResults;

      final response = await _dio.post<ResponseBody>(
        '/chat/stream',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
        cancelToken: cancelToken,
      );

      // utf8.decoder gère les caractères multi-octets coupés entre deux
      // chunks TCP (é, à, …) ; LineSplitter reconstitue les lignes SSE.
      // timeout : clôt le flux proprement si plus rien n'arrive.
      final lines = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_inactivityTimeout, onTimeout: (sink) => sink.close());

      await for (final line in lines) {
        final event = parseSseLine(line);
        if (event != null) yield event;
        if (event is ChatStreamDone) return;
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return; // annulation volontaire : silencieux
      rethrow;
    } finally {
      if (_activeCancelToken == cancelToken) _activeCancelToken = null;
    }
  }
}
