// ─── CloudTtsService ──────────────────────────────────────────────────────────
// Synthèse vocale via Edge TTS (Microsoft, gratuit).
// ResponseType.bytes : compatible avec l'intercepteur Dio (refresh 401).
// Lecture depuis la mémoire sans écriture disque (_BytesAudioSource).
// CancelToken : stop() interrompt aussi le téléchargement en cours.

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

  bool get isPlaying => _isPlaying;
  String? get playingMsgId => _playingMsgId;

  Future<void> speak(String text, {String? msgId}) async {
    if (_isPlaying) await stop();
    if (text.trim().isEmpty) return;

    _isPlaying = true;
    _playingMsgId = msgId;
    _cancelToken = CancelToken();

    try {
      final speed = settingsService.ttsSpeed;
      final pct = ((speed - 1.0) * 100).round();
      final rate = pct >= 0 ? '+$pct%' : '$pct%';

      final response = await api.post<List<int>>(
        '/tts',
        data: {'text': text, 'voice': settingsService.ttsVoice, 'rate': rate},
        options: Options(responseType: ResponseType.bytes),
        cancelToken: _cancelToken,
      );

      final bytes = Uint8List.fromList(response.data ?? []);
      if (bytes.isEmpty) throw Exception('[CloudTts] réponse vide');

      await _player.setAudioSource(_BytesAudioSource(bytes));
      await _player.play();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      debugPrint('[CloudTts] erreur Dio : $e');
      rethrow;
    } catch (e) {
      debugPrint('[CloudTts] erreur : $e');
      rethrow;
    } finally {
      _isPlaying = false;
      _playingMsgId = null;
      _cancelToken = null;
      try { await _player.stop(); } catch (_) {}
    }
  }

  Future<void> stop() async {
    _cancelToken?.cancel('stopped');
    _cancelToken = null;
    try { await _player.stop(); } catch (_) {}
    _isPlaying = false;
    _playingMsgId = null;
  }

  void dispose() => _player.dispose();
}

final cloudTtsService = CloudTtsService();
