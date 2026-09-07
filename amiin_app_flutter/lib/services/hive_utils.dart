// ─── Utilitaires Hive : chiffrement AES des boxes ───────────────────────────
//
// La clé AES-256 est générée une seule fois puis conservée dans le stockage
// sécurisé de la plateforme (Keystore Android / Keychain iOS).
// Toutes les boxes contenant des données utilisateur (conversations, notes,
// événements) sont ouvertes avec ce cipher.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

const _kHiveKeyName = 'amiin_hive_key';

/// Cipher global, initialisé dans main() avant l'ouverture des boxes.
/// Null uniquement si le stockage sécurisé est indisponible (on dégrade
/// alors en boxes non chiffrées plutôt que de bloquer l'application).
HiveAesCipher? amiinCipher;

Future<void> initHiveCipher() async {
  try {
    // Namespace dédié, distinct du stockage utilisé par AuthService : un
    // AuthService._clearAll() (déconnexion / refresh de token échoué) ne
    // doit jamais pouvoir effacer cette clé — sinon toutes les boxes Hive
    // (chat, agenda, notes) deviennent indéchiffrables et sont recréées
    // vides au prochain démarrage.
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        sharedPreferencesName: 'amiin_hive_keystore',
      ),
      iOptions: IOSOptions(accountName: 'amiin_hive_keystore'),
    );
    final stored = await storage.read(key: _kHiveKeyName);
    if (stored != null) {
      amiinCipher = HiveAesCipher(base64Url.decode(stored));
      return;
    }
    final key = Hive.generateSecureKey();
    await storage.write(key: _kHiveKeyName, value: base64UrlEncode(key));
    amiinCipher = HiveAesCipher(key);
  } catch (e) {
    debugPrint('Stockage sécurisé indisponible, Hive non chiffré : $e');
    amiinCipher = null;
  }
}

/// Ouvre une box avec le cipher global. Si la box existante n'est pas
/// déchiffrable (ancienne box non chiffrée, clé perdue…), elle est
/// supprimée puis recréée — préférable à une app qui ne démarre plus.
Future<Box<T>> openBoxSafe<T>(String name) async {
  try {
    return await Hive.openBox<T>(name, encryptionCipher: amiinCipher);
  } catch (e) {
    debugPrint('Box "$name" illisible (migration chiffrement ?) : $e');
    await Hive.deleteBoxFromDisk(name);
    return Hive.openBox<T>(name, encryptionCipher: amiinCipher);
  }
}
