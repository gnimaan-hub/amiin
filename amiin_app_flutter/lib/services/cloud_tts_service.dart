// ─── CloudTtsService ──────────────────────────────────────────────────────────
// Synthèse vocale via Edge TTS (Microsoft, gratuit).
// Le backend streame le MP3 dès les premiers frames — just_audio joue en temps
// réel sans attendre le téléchargement complet ni écrire de fichier temporaire.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart' show api;
import 'settings_service.dart';

// ── Source audio streaming ────────────────────────────────────────────────────
// just_audio appelle request() puis lit les bytes au fur et à mesure.
// Chaque appel à request() déclenche une nouvelle requête POST /tts,
// ce qui permet à just_audio de réessayer automatiquement si besoin.
class _TtsStreamSource extends StreamAudioSource {
  final Map<String, dynamic> _body;

  _TtsStreamSource(this._body);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final response = await api.post<ResponseBody>(
      '/tts',
      data: _body,
      options: Options(responseType: ResponseType.stream),
    );
    return StreamAudioResponse(
      sourceLength: null,
      contentLength: null,
      offset: 0,
      contentType: 'audio/mpeg',
      stream: response.data!.stream,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class CloudTtsService {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  String? _playingMsgId;

  bool get isPlaying => _isPlaying;
  String? get playingMsgId => _playingMsgId;

  /// Génère et joue [text] en streaming.
  /// La lecture démarre dès les premiers frames audio reçus du serveur.
  Future<void> speak(String text, {String? msgId}) async {
    if (_isPlaying) await stop();
    if (text.trim().isEmpty) return;

    _isPlaying = true;
    _playingMsgId = msgId;

    try {
      final speed = settingsService.ttsSpeed;
      final pct = ((speed - 1.0) * 100).round();
      final rate = pct >= 0 ? '+$pct%' : '$pct%';

      final source = _TtsStreamSource({
        'text': text,
        'voice': settingsService.ttsVoice,
        'rate': rate,
      });

      await _player.setAudioSource(source);
      await _player.play(); // démarre dès les premiers frames
    } catch (e) {
      debugPrint('[CloudTts] erreur : $e');
      rethrow;
    } finally {
      _isPlaying = false;
      _playingMsgId = null;
      try { await _player.stop(); } catch (_) {}
    }
  }

  Future<void> stop() async {
    try { await _player.stop(); } catch (_) {}
    _isPlaying = false;
    _playingMsgId = null;
  }

  void dispose() {
    _player.dispose();
  }
}

final cloudTtsService = CloudTtsService();
