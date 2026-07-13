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
