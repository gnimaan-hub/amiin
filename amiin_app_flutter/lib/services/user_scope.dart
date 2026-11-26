// ─── UserScope — données locales propres à chaque compte ─────────────────────
//
// Avant : toutes les données personnelles (conversations, mémoire, notes,
// agenda, démarches suivies, profil) vivaient dans des boxes Hive communes à
// tous les comptes. En changeant de compte sur le même téléphone, on voyait
// les données du compte précédent.
//
// Désormais chaque compte a ses propres boxes, suffixées par son identifiant
// (`notes_box_u_<id>`…), toutes chiffrées. Hors connexion, l'app pointe sur un
// espace « invité » vide. Les données d'un compte restent sur l'appareil après
// sa déconnexion et réapparaissent à sa reconnexion — jamais pour un autre.
//
// Restent communs à l'appareil : thème, taille du texte, police, langue de
// l'interface, voix, réglages des notifications, catalogue des démarches,
// brief d'accueil (météo, prières, taux).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/chat_message.dart';
import '../models/user_action.dart';
import 'agenda_service.dart';
import 'bootstrap.dart';
import 'demarches_service.dart';
import 'hive_utils.dart';
import 'memory_service.dart';
import 'notes_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'widget_bridge.dart';

/// Box Hive propre au compte actif. Se rouvre d'elle-même sur la box du
/// nouveau compte au premier accès après un changement de compte.
class ScopedBox<T> {
  ScopedBox(this.baseName);

  final String baseName;

  /// Listenable stable : les écrans s'y abonnent une fois ; il relaie les
  /// changements de la box courante et notifie aussi au changement de compte.
  final BoxChanges changes = BoxChanges();

  Box<T>? _box;
  String? _key;
  Future<Box<T>>? _pending;
  String? _pendingKey;

  /// Box du compte actif si elle est déjà ouverte (accès synchrone).
  Box<T>? get current =>
      (_box != null && _box!.isOpen && _key == userScope.key) ? _box : null;

  /// Box du compte actif, ouverte au besoin.
  Future<Box<T>> get box async {
    final key = userScope.key;
    final cur = current;
    if (cur != null) return cur;
    if (_pending != null) {
      final b = await _pending!;
      if (_pendingKey == key || _key == key) return b;
      return box; // le compte a changé pendant l'ouverture
    }
    _pendingKey = key;
    _pending = _open(key).whenComplete(() => _pending = null);
    return _pending!;
  }

  Future<Box<T>> _open(String key) async {
    final old = _box;
    _box = null;
    if (old != null && old.isOpen) await old.close();
    final b = await openBoxSafe<T>(userScope.boxName(baseName, key));
    _box = b;
    _key = key;
    changes.bind(b);
    return b;
  }
}

/// Relaie les événements d'une box Hive vers des écouteurs stables.
class BoxChanges extends ChangeNotifier {
  ValueListenable<dynamic>? _source;

  void bind(Box<dynamic> box) {
    _source?.removeListener(_relay);
    _source = box.listenable()..addListener(_relay);
    notifyListeners(); // nouveau compte : les écrans rechargent
  }

  void _relay() => notifyListeners();
}

/// Enregistre une fois tous les adaptateurs Hive des données utilisateur.
void registerUserDataAdapters() {
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserActionAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(AgentActionAdapter());
  if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(AmiinEventAdapter());
  if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(AmiinNoteAdapter());
  if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(DemarcheAdapter());
  if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(UserDemarcheAdapter());
}

class UserScope extends ChangeNotifier {
  UserScope._();

  static const _guestKey = 'invite';

  /// Boxes personnelles (nom de base, avant suffixe du compte).
  static const personalBoxes = [
    'chat_messages', 'user_actions', 'notes_box', 'agenda_events', 'user_demarches',
  ];

  String _key = _guestKey;
  Future<void> _queue = Future.value();

  /// Attente de l'initialisation de Hive (remplacée dans les tests).
  @visibleForTesting
  Future<void> Function() ensureReady = ensureBootstrap;

  /// Clé du compte actif : `u_<id>` ou 'invite' hors connexion.
  String get key => _key;
  bool get isGuest => _key == _guestKey;

  String boxName(String base, [String? key]) => '${base}_${key ?? _key}';

  static String keyFor(String? userId) => userId == null
      ? _guestKey
      : 'u_${userId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';

  /// Bascule le stockage local sur le compte [userId] (null : hors connexion).
  /// Les appels sont exécutés l'un après l'autre. [atStartup] : appelé par
  /// AuthService.init() avec le compte retrouvé au lancement de l'app.
  Future<void> activate(String? userId, {bool atStartup = false}) {
    final run = _queue.then((_) => _activate(userId, atStartup));
    _queue = run.catchError((Object e) => debugPrint('UserScope : $e'));
    return run;
  }

  Future<void> _activate(String? userId, bool atStartup) async {
    await ensureReady(); // Hive initialisé, clé de chiffrement prête
    registerUserDataAdapters();
    final key = keyFor(userId);
    await _migrateLegacyData(userId == null ? null : key, atStartup);

    final changed = key != _key;
    _key = key;
    await settingsService.openAccount(key);
    await Future.wait([
      MemoryService().init(),
      agendaService.init(),
      notesService.init(),
      demarchesService.init(),
    ]);
    if (changed) {
      notifyListeners();
      if (!atStartup) unawaited(_resyncDeviceSideEffects());
    }
  }

  /// Notifications programmées et widget d'accueil : ils appartiennent au
  /// système, pas à une box — on les remet aux couleurs du nouveau compte.
  Future<void> _resyncDeviceSideEffects() async {
    try {
      await notificationService.cancelAll();
      if (!isGuest) {
        await agendaService.rescheduleAllReminders();
        await demarchesService.rescheduleAllFollowUps();
      }
      await demarchesService.syncWidget();
      await WidgetBridge.pushEvents();
    } catch (e) {
      debugPrint('Resynchronisation notifications/widget : $e');
    }
  }

  // ── Migration des données d'avant la séparation par compte ────────────────
  //
  // Les anciennes boxes communes sont attribuées au compte connecté au premier
  // lancement de cette version (c'est presque toujours le propriétaire du
  // téléphone). Si personne n'est connecté à ce moment-là, on ne peut pas
  // savoir à qui elles appartiennent : elles sont effacées plutôt que
  // risquer de les montrer au mauvais compte.

  static const _stateBox = 'app_state';
  static const _migratedFlag = 'per_account_storage_v1';

  Future<void> _migrateLegacyData(String? targetKey, bool atStartup) async {
    final state = await Hive.openBox<dynamic>(_stateBox);
    if (state.get(_migratedFlag) == true) return;
    final claim = targetKey != null && atStartup;

    for (final name in personalBoxes) {
      if (!await _exists(name)) continue;
      try {
        final src = name == 'user_demarches'
            ? await _openLegacyDemarches()
            : await openBoxSafe<dynamic>(name);
        if (claim && src.isNotEmpty) {
          final dst = await openBoxSafe<dynamic>(boxName(name, targetKey));
          await dst.putAll(Map<dynamic, dynamic>.from(src.toMap()));
          await dst.close();
        }
        await _drop(src, name);
      } catch (e) {
        debugPrint('Migration de "$name" : $e');
      }
    }
    await settingsService.moveLegacyAccountSettings(claim ? targetKey : null);
    await state.put(_migratedFlag, true);
  }

  Future<bool> _exists(String name) async {
    try {
      return await Hive.boxExists(name);
    } catch (_) {
      return false;
    }
  }

  /// L'ancienne box des démarches suivies peut encore être en clair.
  Future<Box<dynamic>> _openLegacyDemarches() async {
    final flags = await Hive.openBox<dynamic>('demarches_settings');
    return openBoxMigratingToEncrypted<dynamic>(
      'user_demarches',
      migrated: flags.get('user_box_encrypted') == true,
      markMigrated: () => flags.put('user_box_encrypted', true),
    );
  }

  /// Vide et ferme une box ; la supprime du disque hors web (sur le web, la
  /// suppression juste après ouverture peut bloquer, cf. hive_utils).
  Future<void> _drop(Box<dynamic> box, String name) async {
    await box.clear();
    await box.close();
    if (!kIsWeb) await Hive.deleteBoxFromDisk(name);
  }
}

final userScope = UserScope._();

/// Efface les données du compte actif sur cet appareil (conversations,
/// mémoire, notes, agenda, démarches suivies, profil et préférences du
/// compte), ainsi que les préférences de l'appareil et le brief en cache.
/// Le catalogue des démarches et la clé de chiffrement sont conservés.
Future<void> wipeLocalUserData() async {
  await userScope.ensureReady();
  registerUserDataAdapters();
  // Via les services : leurs boxes sont typées (Hive.box<dynamic> lèverait).
  await Future.wait([
    MemoryService().clearAll(),
    notesService.clearAll(),
    agendaService.clearAll(),
    demarchesService.clearUserData(),
  ]);
  await settingsService.clearAll();
  for (final name in ['home_brief']) {
    if (Hive.isBoxOpen(name)) {
      await Hive.box<dynamic>(name).clear();
    } else {
      await Hive.deleteBoxFromDisk(name);
    }
  }
  await notificationService.cancelAll();
}
