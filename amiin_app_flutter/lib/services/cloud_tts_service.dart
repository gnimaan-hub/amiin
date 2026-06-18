// ─── CloudTtsService ──────────────────────────────────────────────────────────
// Synthèse vocale via Edge TTS (Microsoft, gratuit).
// Appelle POST /v1/tts sur le backend → reçoit des bytes MP3 → joue via just_audio.
// Garde le même contrat d'état que flutter_tts pour une intégration transparente.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart' show api;
import 'settings_service.dart';

class CloudTtsService {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  String? _playingMsgId;

  bool get isPlaying => _isPlaying;
  String? get playingMsgId => _playingMsgId;

  /// Génère et joue [text] avec la voix et la vitesse des réglages courants.
  /// Retourne quand la lecture est terminée (ou interrompue par [stop]).
  Future<void> speak(String text, {String? msgId}) async {
    if (_isPlaying) await stop();
    if (text.trim().isEmpty) return;

    _isPlaying = true;
    _playingMsgId = msgId;

    try {
      // Convertit ttsSpeed (0.5–2.0) → format edge-tts ("+50%", "-25%", "+0%")
      final speed = settingsService.ttsSpeed;
      final pct = ((speed - 1.0) * 100).round();
      final rate = pct >= 0 ? '+$pct%' : '$pct%';

      final response = await api.post<List<int>>(
        '/tts',
        data: {
          'text': text,
          'voice': settingsService.ttsVoice,
          'rate': rate,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return;

      // Sauvegarde dans un fichier temporaire — just_audio lit depuis un chemin.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/amiin_cloud_tts.mp3');
      await file.writeAsBytes(bytes, flush: true);

      await _player.setFilePath(file.path);
      await _player.play(); // attend la fin de la lecture
    } catch (e) {
      debugPrint('[CloudTts] erreur : $e');
      rethrow; // le caller peut décider de fallback vers flutter_tts
    } finally {
      _isPlaying = false;
      _playingMsgId = null;
      // Remet le player à zéro pour la prochaine lecture
      try { await _player.stop(); } catch (_) {}
    }
  }

  /// Interrompt la lecture en cours.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _playingMsgId = null;
  }

  void dispose() {
    _player.dispose();
  }
}

/// Singleton global — partagé entre ChatScreen et les Settings.
final cloudTtsService = CloudTtsService();
