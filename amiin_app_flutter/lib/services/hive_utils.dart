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
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
