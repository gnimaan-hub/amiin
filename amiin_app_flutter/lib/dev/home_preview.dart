// ─── Aperçu de développement de l'écran d'accueil ────────────────────────────
//
// Affiche l'accueil avec des données d'exemple, sans backend ni connexion.
// Usage : flutter run -d chrome -t lib/dev/home_preview.dart
// Paramètre d'URL : ?theme=terre|ocean|foret|nuit
// Le dossier web/ n'a pas d'index.html versionné : en créer un pour un build web.
// Ne fait pas partie de l'application livrée.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../navigation/app_router.dart' show AmiinNavBar;
import '../screens/home/home_screen.dart';
import '../services/agenda_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/hive_utils.dart';
import '../services/memory_service.dart';
import '../services/settings_service.dart';
import '../services/chat_controller.dart';
import '../services/home_brief_service.dart';
import '../services/notes_service.dart';
import '../theme/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialisation minimale (le bootstrap complet ouvre des boxes inutiles ici).
  await initializeDateFormatting('fr_FR', null);
  Intl.defaultLocale = 'fr_FR';
  await Hive.initFlutter();
  await initHiveCipher();
  await Future.wait([settingsService.init(), agendaService.init(), notesService.init(), MemoryService().init()]);
  ApiClient.init();
  await _seed();

  final params = Uri.base.queryParameters;
  final variant = AmiinThemeVariantExt.fromId(params['theme'] ?? 'terre');

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: child,
          bottomNavigationBar: AmiinNavBar(currentIndex: 0, onTap: (_) {}),
        ),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomeScreen(),
          ),
          for (final p in ['/chat', '/agenda', '/notes', '/annuaire', '/demarches', '/settings'])
            GoRoute(path: p, builder: (_, __) => const SizedBox.shrink()),
        ],
      ),
    ],
  );

  runApp(ChangeNotifierProvider(
    create: (_) => ChatController(),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AmiinThemes.forVariant(variant, 'default'),
      routerConfig: router,
    ),
  ));

  // Après le premier refresh (qui échoue sans backend), injecte un brief.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  homeBriefService.brief.value = HomeBrief(
    date: DateTime.now().toIso8601String(),
    weather: HomeBriefWeather(temp: 29, feelsLike: 32, desc: 'Ensoleillé', icon: '01d'),
    prayers: HomeBriefPrayers(
        fajr: '04:52', dhuhr: '11:58', asr: '15:20', maghrib: '17:41', isha: '18:55'),
    fx: HomeBriefFx(usdFdj: 177.7, eurFdj: 193.4),
  );
}

Future<void> _seed() async {
  final existing = await notesService.getNotes();
  if (existing.isNotEmpty) return;

  final now = DateTime.now();
  DateTime at(int days, int h, int m) =>
      DateTime(now.year, now.month, now.day + days, h, m);

  Future<void> event(String title, DateTime start, EventCategory c, {bool agent = false}) =>
      agendaService.createEvent(CreateEventPayload(
        title: title,
        startDate: start.toIso8601String(),
        endDate: start.add(const Duration(hours: 1)).toIso8601String(),
        category: c,
        createdByAgent: agent,
      ));

  await event('Rendez-vous Direction de la Population', at(0, 23, 0), EventCategory.admin, agent: true);
  await event('Visite médicale CNSS', at(1, 9, 30), EventCategory.health);
  await event('Réunion parents d\'élèves', at(3, 17, 0), EventCategory.education);

  await notesService.createNote(CreateNotePayload(
    title: 'Pièces pour le passeport',
    content: 'Acte de naissance, certificat de nationalité, 2 photos, ancien passeport et timbre fiscal de 15 000 FDJ.',
  ));
  await notesService.createNote(CreateNotePayload(
    title: 'Numéros utiles',
    content: 'CNSS : 21 35 xx xx · Mairie de Djibouti : 21 35 xx xx · Hôpital Peltier : 21 35 xx xx',
  ));
  await notesService.createNote(CreateNotePayload(
    title: 'Idées week-end',
    content: 'Plage de la Siesta, lac Assal, déjeuner à Tadjourah.',
  ));
}
