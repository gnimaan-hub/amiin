// ─── CloudSttService ──────────────────────────────────────────────────────────
// Reconnaissance vocale cloud via Groq Whisper (large-v3), utilisée quand la
// langue de réponse n'est pas gérée par le moteur natif du téléphone —
// typiquement le somali, absent des reconnaisseurs Android/iOS.
//
// Flux : start() enregistre un fichier audio (AAC/m4a) ; stopAndTranscribe()
// arrête l'enregistrement, envoie le fichier à POST /stt (multipart) et
// retourne le texte transcrit. cancel() abandonne sans transcrire.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'api_client.dart' show api;

class CloudSttService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Permission micro accordée ? (déclenche la demande système si besoin.)
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Démarre l'enregistrement. Lève une exception si la permission est refusée.
  Future<void> start() async {
    if (_isRecording) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Permission microphone refusée.');
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/amiin_stt_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      // WAV/PCM non compressé (pas d'artefacts de codec comme avec AAC) à
      // 16 kHz — la fréquence native attendue par Whisper, inutile de capter
      // plus haut. Réduction de bruit + gain auto + anti-écho pour nettoyer
      // le signal avant transcription (best-effort, ignoré si le
      // périphérique ne le supporte pas).
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        // Source dédiée à la reconnaissance vocale : Android désactive la
        // compression dynamique appliquée aux autres sources (mic, appels)
        // qui dégrade la reconnaissance, tout en gardant AEC/NS/AGC actifs.
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
      path: path,
    );
    _isRecording = true;
  }

  /// Arrête l'enregistrement, envoie l'audio à /stt et retourne le texte.
  /// Retourne une chaîne vide si rien n'a été capté.
  Future<String> stopAndTranscribe({String lang = 'so'}) async {
    if (!_isRecording) return '';
    String? path;
    try {
      path = await _recorder.stop();
    } finally {
      _isRecording = false;
    }
    if (path == null) return '';

    try {
      final form = FormData.fromMap({
        'lang': lang,
        'file': await MultipartFile.fromFile(path, filename: 'audio.wav'),
      });
      final resp = await api.post<Map<String, dynamic>>('/stt', data: form);
      return (resp.data?['text'] as String?)?.trim() ?? '';
    } on DioException catch (e) {
      debugPrint('[CloudStt] échec transcription : ${e.error ?? e.message}');
      rethrow;
    }
  }

  /// Abandonne l'enregistrement en cours sans transcrire.
  Future<void> cancel() async {
    if (!_isRecording) return;
    try {
      await _recorder.cancel();
    } catch (_) {}
    _isRecording = false;
  }

  void dispose() => _recorder.dispose();
}

final cloudSttService = CloudSttService();
