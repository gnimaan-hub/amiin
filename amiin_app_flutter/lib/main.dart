import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/api_client.dart';
import 'services/hive_utils.dart';
import 'services/memory_service.dart';
import 'services/agenda_service.dart';
import 'services/agenda_badge_notifier.dart';
import 'services/notes_service.dart';
import 'services/demarches_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  Intl.defaultLocale = 'fr_FR';

  await Hive.initFlutter();
  await initHiveCipher();

  // Boxes nécessaires dès le premier écran
  await agendaService.init();
  await notesService.init();
  await demarchesService.init();
  await MemoryService().init();

  ApiClient.init();

  // Initialisations non critiques : en arrière-plan, sans retarder le démarrage
  unawaited(notificationService.init());
  unawaited(connectivityService.init());

  // Badge agenda réactif : se met à jour dès qu'un événement change,
  // qu'il soit créé manuellement ou par Amiin.
  agendaService.listenable.addListener(refreshAgendaBadge);
  unawaited(refreshAgendaBadge());

  runApp(const MyApp());
}
