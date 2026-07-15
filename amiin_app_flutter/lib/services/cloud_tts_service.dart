// ─── CloudTtsService ──────────────────────────────────────────────────────────
// Synthèse vocale via Edge TTS (Microsoft, gratuit).
//
// v2 — pipeline par phrases : le texte est découpé en morceaux (la première
// phrase seule, puis des groupes de phrases), le 1er morceau part en synthèse
// immédiatement et le suivant est pré-chargé pendant la lecture du courant.
// La voix démarre donc en ~1 s même sur une longue réponse, au lieu
// d'attendre la génération du MP3 complet.
//
// ResponseType.bytes : compatible avec l'intercepteur Dio (refresh 401).
// Lecture depuis la mémoire sans écriture disque (_BytesAudioSource).
// Annulation : stop() invalide la session (les fetchs en cours sont annulés
// et la boucle de lecture s'arrête au prochain point de contrôle).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart' show api;
import 'settings_service.dart';

// ── Source audio en mémoire ───────────────────────────────────────────────────
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      contentType: 'audio/mpeg',
      stream: Stream.value(_bytes.sublist(s, e)),
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class CloudTtsService {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  String? _playingMsgId;
  CancelToken? _cancelToken;

  /// Identifiant de session : incrémenté à chaque speak()/stop(), il invalide
  /// les boucles de lecture précédentes sans dépendre d'un flag partagé.
  int _session = 0;

  // ── État de session streaming (voix pendant le stream SSE) ────────────────
  int _rawConsumed = 0;          // offset du texte brut déjà découpé
  String _pendingChunk = '';     // phrases complètes en attente de groupage
  bool _firstChunkSent = false;
  bool _sessionEnded = false;
  bool _producedAudio = false;
  String _rate = '+0%';
  String Function(String)? _cleaner;
  final List<Future<Uint8List>> _fetchQueue = [];
  Completer<void>? _wakeDrain;
  Future<void>? _drainFuture;

  bool get isPlaying => _isPlaying;
  String? get playingMsgId => _playingMsgId;

  /// Taille cible des morceaux suivants (le 1er reste une phrase seule pour
  /// démarrer vite ; les suivants sont groupés pour une prosodie naturelle).
  static const _groupTarget = 260;

  /// Découpe [text] en morceaux : première phrase seule, puis groupes de
  /// phrases d'environ [_groupTarget] caractères.
  @visibleForTesting
  static List<String> splitForTts(String text) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return [];
    if (sentences.length == 1) return sentences;

    final chunks = <String>[sentences.first];
    final buf = StringBuffer();
    for (final s in sentences.skip(1)) {
      if (buf.isNotEmpty && buf.length + s.length > _groupTarget) {
        chunks.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }

  Future<Uint8List> _fetch(String chunk, String rate, CancelToken token) async {
    final response = await api.post<List<int>>(
      '/tts',
      data: {'text': chunk, 'voice': settingsService.ttsVoice, 'rate': rate},
      options: Options(responseType: ResponseType.bytes),
      cancelToken: token,
    );
    return Uint8List.fromList(response.data ?? []);
  }

  /// Joue [bytes] et attend la fin réelle de la lecture (ou l'invalidation
  /// de la session).
  Future<void> _playToEnd(Uint8List bytes, int session) async {
    if (bytes.isEmpty || session != _session) return;
    await _player.setAudioSource(_BytesAudioSource(bytes));
    if (session != _session) return;
    _player.play();
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
  }

  // ── Session streaming ───────────────────────────────────────────────────────
  //
  // Usage : beginSession() au départ de la requête, feedText(texteComplet)
  // à chaque token SSE (le service n'extrait que les phrases COMPLÈTES et
  // lance leur synthèse immédiatement), puis endSession() à la fin du stream
  // (vide le reliquat et attend la fin de la lecture).
  // La première phrase part seule → la voix démarre pendant que le reste
  // de la réponse s'écrit encore à l'écran.

  void beginSession({String? msgId, String Function(String)? cleaner}) {
    // Invalide toute lecture en cours sans attendre.
    _session++;
    _cancelToken?.cancel('nouvelle session');
    unawaited(_player.stop().catchError((_) {}));

    final session = ++_session;
    _isPlaying = true;
    _playingMsgId = msgId;
    _cancelToken = CancelToken();
    _rawConsumed = 0;
    _pendingChunk = '';
    _firstChunkSent = false;
    _sessionEnded = false;
    _producedAudio = false;
    _cleaner = cleaner;
    _fetchQueue.clear();

    final speed = settingsService.ttsSpeed;
    final pct = ((speed - 1.0) * 100).round();
    _rate = pct >= 0 ? '+$pct%' : '$pct%';

    _drainFuture = _drain(session);
  }

  /// Associe (dès qu'il est connu) l'id du message lu — pour l'icône
  /// haut-parleur de la bulle.
  void setSessionMsgId(String id) => _playingMsgId = id;

  /// Reçoit le texte brut COMPLET accumulé du message en cours de stream.
  /// Idempotent : seules les nouvelles phrases complètes sont synthétisées.
  void feedText(String fullRawText) {
    if (_sessionEnded || _cancelToken == null) return;
    _extractAndEnqueue(fullRawText, flush: false);
  }

  /// Fin du stream : synthétise le reliquat puis attend la fin de la lecture.
  /// Retourne true si au moins un morceau audio a été joué (sinon l'appelant
  /// peut basculer sur le moteur local).
  Future<bool> endSession(String fullRawText) async {
    if (_cancelToken == null) return _producedAudio;
    _extractAndEnqueue(fullRawText, flush: true);
    _sessionEnded = true;
    if (_wakeDrain != null && !_wakeDrain!.isCompleted) _wakeDrain!.complete();
    await _drainFuture;
    return _producedAudio;
  }

  /// Extrait de [fullRaw] (à partir de l'offset consommé) les phrases
  /// complètes ; la 1re part seule, les suivantes sont groupées.
  /// Balaye [fullRaw] depuis [consumed] et retourne les phrases complètes
  /// trouvées + le nouvel offset. Fonction pure (testable).
  @visibleForTesting
  static (List<String>, int) extractCompleteSentences(
      String fullRaw, int consumed) {
    if (consumed > fullRaw.length) return (const [], consumed);
    final boundary = RegExp(r'[.!?…](\s|$)');
    final out = <String>[];
    var offset = consumed;
    while (true) {
      final tail = fullRaw.substring(offset);
      final m = boundary.firstMatch(tail);
      if (m == null) break;
      final sentence = tail.substring(0, m.end).trim();
      offset += m.end;
      if (sentence.isNotEmpty) out.add(sentence);
    }
    return (out, offset);
  }

  void _extractAndEnqueue(String fullRaw, {required bool flush}) {
    final (sentences, offset) =
        extractCompleteSentences(fullRaw, _rawConsumed);
    _rawConsumed = offset;
    for (final s in sentences) {
      _pushSentence(s, flush: false);
    }

    if (flush) {
      if (_rawConsumed <= fullRaw.length) {
        final rest = fullRaw.substring(_rawConsumed).trim();
        _rawConsumed = fullRaw.length;
        if (rest.isNotEmpty) _pushSentence(rest, flush: false);
      }
      // vide le groupe en attente
      if (_pendingChunk.isNotEmpty) {
        _enqueueChunk(_pendingChunk);
        _pendingChunk = '';
      }
    }
  }

  void _pushSentence(String sentence, {required bool flush}) {
    if (!_firstChunkSent) {
      _firstChunkSent = true;
      _enqueueChunk(sentence);
      return;
    }
    _pendingChunk = _pendingChunk.isEmpty ? sentence : '$_pendingChunk $sentence';
    if (_pendingChunk.length >= 180) {
      _enqueueChunk(_pendingChunk);
      _pendingChunk = '';
    }
  }

  void _enqueueChunk(String rawChunk) {
    final token = _cancelToken;
    if (token == null) return;
    final cleaned = (_cleaner?.call(rawChunk) ?? rawChunk).trim();
    if (cleaned.isEmpty) return;
    // La synthèse démarre dès l'enfilage (parallèle à la lecture en cours).
    _fetchQueue.add(_fetch(cleaned, _rate, token));
    if (_wakeDrain != null && !_wakeDrain!.isCompleted) _wakeDrain!.complete();
  }

  /// Boucle de lecture : joue les morceaux dans l'ordre au fur et à mesure
  /// que leurs synthèses aboutissent.
  Future<void> _drain(int session) async {
    try {
      while (_session == session) {
        if (_fetchQueue.isEmpty) {
          if (_sessionEnded) break;
          _wakeDrain = Completer<void>();
          await _wakeDrain!.future;
          continue;
        }
        final inflight = _fetchQueue.removeAt(0);
        Uint8List bytes;
        try {
          bytes = await inflight;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) return;
          debugPrint('[CloudTts] morceau perdu : $e');
          continue; // on tente le morceau suivant
        }
        if (_session != session) return;
        if (bytes.isNotEmpty) _producedAudio = true;
        await _playToEnd(bytes, session);
      }
    } catch (e) {
      debugPrint('[CloudTts] drain : $e');
    } finally {
      if (_session == session) {
        _isPlaying = false;
        _playingMsgId = null;
        _cancelToken = null;
        try {
          await _player.stop();
        } catch (_) {}
      }
    }
  }

  Future<void> speak(String text, {String? msgId}) async {
    await stop();
    if (text.trim().isEmpty) return;

    final session = ++_session;
    _isPlaying = true;
    _playingMsgId = msgId;
    final token = _cancelToken = CancelToken();

    try {
      final speed = settingsService.ttsSpeed;
      final pct = ((speed - 1.0) * 100).round();
      final rate = pct >= 0 ? '+$pct%' : '$pct%';

      final chunks = splitForTts(text);
      if (chunks.isEmpty) return;

      // Pipeline : pendant que le morceau i se joue, le i+1 se télécharge.
      Future<Uint8List> next = _fetch(chunks.first, rate, token);
      for (var i = 0; i < chunks.length; i++) {
        final bytes = await next;
        if (session != _session) return;
        if (i + 1 < chunks.length) {
          next = _fetch(chunks[i + 1], rate, token);
        }
        await _playToEnd(bytes, session);
        if (session != _session) return;
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      debugPrint('[CloudTts] erreur Dio : $e');
      rethrow;
    } catch (e) {
      debugPrint('[CloudTts] erreur : $e');
      rethrow;
    } finally {
      // Ne nettoie que si aucune session plus récente n'a pris la main.
      if (session == _session) {
        _isPlaying = false;
        _playingMsgId = null;
        _cancelToken = null;
        try {
          await _player.stop();
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    _session++;
    _sessionEnded = true;
    if (_wakeDrain != null && !_wakeDrain!.isCompleted) _wakeDrain!.complete();
    _cancelToken?.cancel('stopped');
    _cancelToken = null;
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _playingMsgId = null;
  }

  void dispose() => _player.dispose();
}

final cloudTtsService = CloudTtsService();
