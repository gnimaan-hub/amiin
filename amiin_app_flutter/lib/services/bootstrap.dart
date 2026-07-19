// ─── Bootstrap — initialisations différées, exécutées pendant le splash ──────
//
// Historiquement tout ceci vivait dans main() AVANT runApp() : l'écran restait
// noir plusieurs secondes (secure storage, ouverture de 5 boxes Hive chiffrées,
// formats de date…). Désormais runApp() part immédiatement et le SplashScreen
// attend ensureBootstrap() pendant que son animation tourne.

import 'dart:async';

import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'api_client.dart';
import 'hive_utils.dart';
import 'memory_service.dart';
import 'agenda_service.dart';
import 'agenda_badge_notifier.dart';
import 'notes_service.dart';
import 'demarches_service.dart';
import 'notification_service.dart';
import 'connectivity_service.dart';
import 'settings_service.dart';
import 'widget_bridge.dart';

Future<void>? _bootstrapFuture;

/// Idempotent : le travail n'est fait qu'une fois, les appels suivants
/// retournent le même Future (hot reload, splash reconstruit…).
Future<void> ensureBootstrap() => _bootstrapFuture ??= _bootstrap();

Future<void> _bootstrap() async {
  await initializeDateFormatting('fr_FR', null);
  Intl.defaultLocale = 'fr_FR';

  await Hive.initFlutter();
  await initHiveCipher();

  // Boxes nécessaires dès le premier écran — ouvertes en parallèle
  await Future.wait([
    settingsService.init(),
    agendaService.init(),
    notesService.init(),
    demarchesService.init(),
    MemoryService().init(),
  ]);

  ApiClient.init();

  // Initialisations non critiques : en arrière-plan, sans retarder le démarrage
  unawaited(notificationService.init());
  unawaited(connectivityService.init());
  unawaited(WidgetBridge.init());

  // Badge agenda réactif : se met à jour dès qu'un événement change,
  // qu'il soit créé manuellement ou par Amiin.
  agendaService.listenable.addListener(refreshAgendaBadge);
  unawaited(refreshAgendaBadge());
}
