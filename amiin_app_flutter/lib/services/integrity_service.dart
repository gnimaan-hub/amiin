// ─── IntegrityService — Google Play Integrity ────────────────────────────────
// Demande à Google Play un jeton prouvant que la requête vient de l'app
// officielle, sur un appareil intègre (MainActivity.kt). Envoyé dans l'en-tête
// X-Amiin-Integrity à l'inscription et à la connexion ; vérifié par le serveur
// (integrity.py). Hors Android, sans numéro de projet Google Cloud
// (--dart-define=AMIIN_CLOUD_PROJECT_NUMBER) ou en cas d'échec : aucun jeton,
// et c'est le serveur qui décide selon son mode (off / report / enforce).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _cloudProjectNumber = int.fromEnvironment('AMIIN_CLOUD_PROJECT_NUMBER');

class IntegrityService {
  IntegrityService._();

  static const _channel = MethodChannel('dj.amiin.app/integrity');

  /// Jeton pour [action] ('register' ou 'login') et [email], ou null.
  static Future<String?> token(String action, String email) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _cloudProjectNumber == 0) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('token', {
        'cloudProjectNumber': _cloudProjectNumber,
        // Même empreinte que integrity.request_hash côté serveur
        'requestData': '$action:${email.trim().toLowerCase()}',
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Play Integrity indisponible : $e');
      return null;
    }
  }

  /// En-têtes à joindre à la requête (vide si aucun jeton).
  static Future<Map<String, String>> headers(String action, String email) async {
    final t = await token(action, email);
    return t == null ? const {} : {'X-Amiin-Integrity': t};
  }
}
