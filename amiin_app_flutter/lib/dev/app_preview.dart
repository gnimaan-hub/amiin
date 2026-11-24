// ─── Aperçu de développement de l'application ────────────────────────────────
//
// Affiche les écrans des onglets avec la vraie barre de navigation et des
// données d'exemple, sans backend ni connexion. Sert à vérifier la refonte
// « vitrine » écran par écran (docs/REFONTE_VITRINE.md).
//
// Build : flutter build web -t lib/dev/app_preview.dart --profile
//         --no-web-resources-cdn --no-tree-shake-icons
// (le dossier web/ n'a pas d'index.html versionné : en créer un temporaire)
// URL   : /#/agenda?theme=terre|nuit|lacte
// Ne fait pas partie de l'application livrée.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../navigation/app_router.dart' show AmiinNavBar;
import '../screens/agenda/agenda_screen.dart';
import '../screens/agenda/create_event_screen.dart';
import '../screens/agenda/event_detail_screen.dart';
import '../screens/annuaire/service_detail_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/demarches/demarche_detail_screen.dart';
import '../screens/notes/note_detail_screen.dart';
import '../screens/settings/settings_about_screen.dart';
import '../screens/settings/settings_account_screen.dart';
import '../screens/settings/settings_appearance_screen.dart';
import '../screens/settings/settings_assistant_screen.dart';
import '../screens/settings/settings_billing_screen.dart';
import '../screens/settings/settings_language_screen.dart';
import '../screens/settings/settings_notifications_screen.dart';
import '../screens/settings/settings_privacy_screen.dart';
import '../screens/settings/settings_profile_screen.dart';
import '../screens/settings/settings_security_screen.dart';
import '../screens/settings/settings_text_screen.dart';
import '../services/annuaire_service.dart';
import '../screens/annuaire/annuaire_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/demarches/demarches_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notes/notes_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/agenda_service.dart';
import '../services/auth_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/demarches_service.dart';
import '../services/hive_utils.dart';
import '../services/memory_service.dart';
import '../services/chat_controller.dart';
import '../services/home_brief_service.dart';
import '../services/notes_service.dart';
import '../services/settings_service.dart';
import '../theme/themes.dart';

// Identifiants d'exemple, résolus au démarrage (routes /x/…).
String _eventId = '', _noteId = '', _serviceId = '', _demarcheId = '';

const _tabs = ['/home', '/chat', '/agenda', '/notes', '/annuaire', '/demarches'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialisation sans réseau (le bootstrap complet attend des services
  // indisponibles dans le navigateur).
  await initializeDateFormatting('fr_FR', null);
  Intl.defaultLocale = 'fr_FR';
  await Hive.initFlutter();
  await initHiveCipher();
  await Future.wait([
    settingsService.init(),
    agendaService.init(),
    notesService.init(),
    MemoryService().init(),
  ]);
  ApiClient.init();
  // L'initialisation des démarches peut ne jamais aboutir dans le
  // navigateur (box chiffrée) : on ne l'attend pas.
  demarchesService.init().catchError((Object e) {
    debugPrint('[preview] démarches indisponibles : $e');
  });
  await _seed();

  final variant =
      AmiinThemeVariantExt.fromId(Uri.base.queryParameters['theme'] ?? 'terre');

  Widget screenFor(String path) => switch (path) {
        '/chat' => const ChatScreen(),
        '/agenda' => const AgendaScreen(),
        '/notes' => const NotesScreen(),
        '/annuaire' => const AnnuaireScreen(),
        '/demarches' => const DemarchesScreen(),
        _ => const HomeScreen(),
      };

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          final index = _tabs.indexOf(state.uri.path).clamp(0, _tabs.length - 1);
          return Scaffold(
            extendBody: true,
            body: child,
            bottomNavigationBar: AmiinNavBar(
              currentIndex: index,
              onTap: (i) => context.go(_tabs[i]),
            ),
          );
        },
        routes: [
          for (final p in _tabs)
            GoRoute(path: p, builder: (_, __) => screenFor(p)),
        ],
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      for (final e in <String, Widget>{
        'profile': const SettingsProfileScreen(),
        'account': const SettingsAccountScreen(),
        'security': const SettingsSecurityScreen(),
        'assistant': const SettingsAssistantScreen(),
        'appearance': const SettingsAppearanceScreen(),
        'text': const SettingsTextScreen(),
        'notifications': const SettingsNotificationsScreen(),
        'language': const SettingsLanguageScreen(),
        'privacy': const SettingsPrivacyScreen(),
        'billing': const SettingsBillingScreen(),
        'about': const SettingsAboutScreen(),
      }.entries)
        GoRoute(path: '/settings/${e.key}', builder: (_, __) => e.value),
      // Écrans de détail et de création, avec des données d'exemple.
      GoRoute(path: '/x/event', redirect: (_, __) => '/agenda/event/$_eventId'),
      GoRoute(path: '/x/note', redirect: (_, __) => '/notes/$_noteId'),
      GoRoute(path: '/x/service', redirect: (_, __) => '/annuaire/$_serviceId'),
      GoRoute(path: '/x/demarche', redirect: (_, __) => '/demarches/$_demarcheId'),
      GoRoute(path: '/agenda/create', builder: (_, __) => const CreateEventScreen()),
      GoRoute(path: '/agenda/event/:id',
          builder: (_, s) => EventDetailScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/notes/create', builder: (_, __) => const CreateNoteScreen()),
      GoRoute(path: '/notes/:id',
          builder: (_, s) => NoteDetailScreen(noteId: s.pathParameters['id']!)),
      GoRoute(path: '/annuaire/:id',
          builder: (_, s) => ServiceDetailScreen(serviceId: s.pathParameters['id']!)),
      GoRoute(path: '/demarches/:id',
          builder: (_, s) => DemarcheDetailScreen(demarcheId: s.pathParameters['id']!)),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    ],
  );

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChatController()),
      ChangeNotifierProvider.value(value: settingsService),
      ChangeNotifierProvider.value(value: authService),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AmiinThemes.forVariant(variant, 'default'),
      routerConfig: router,
    ),
  ));

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
  await _seedData();
  final now = DateTime.now();
  final events = await agendaService.getEvents(
      now.subtract(const Duration(days: 1)).toIso8601String(),
      now.add(const Duration(days: 30)).toIso8601String());
  if (events.isNotEmpty) _eventId = events.first.id;
  final notes = await notesService.getNotes();
  if (notes.isNotEmpty) _noteId = notes.last.id;
  try {
    final data = await annuaireService.loadLocal();
    if (data.entries.isNotEmpty) _serviceId = data.entries.first.id;
  } catch (e) {
    debugPrint('[preview] annuaire indisponible : $e');
  }
  demarchesService.getCatalog().then((catalog) {
    if (catalog.isNotEmpty) _demarcheId = catalog.first.id;
  }).catchError((Object e) {
    debugPrint('[preview] catalogue des démarches indisponible : $e');
  });
}

Future<void> _seedData() async {
  final existing = await notesService.getNotes();
  if (existing.isNotEmpty) return;

  final now = DateTime.now();
  DateTime at(int days, int h, int m) =>
      DateTime(now.year, now.month, now.day + days, h, m);

  Future<void> event(String title, DateTime start, EventCategory c,
          {bool agent = false, String? location}) =>
      agendaService.createEvent(CreateEventPayload(
        title: title,
        startDate: start.toIso8601String(),
        endDate: start.add(const Duration(hours: 1)).toIso8601String(),
        category: c,
        location: location,
        createdByAgent: agent,
      ));

  await event('Rendez-vous Direction de la Population', at(0, 23, 0),
      EventCategory.admin, agent: true, location: 'Plateau du Serpent');
  await event('Visite médicale CNSS', at(1, 9, 30), EventCategory.health);
  await event('Réunion parents d\'élèves', at(3, 17, 0), EventCategory.education);
  await event('Déjeuner en famille', at(5, 13, 0), EventCategory.personal);

  Future<void> note(String title, String content, List<String> tags, {bool pinned = false}) =>
      notesService.createNote(CreateNotePayload(
          title: title, content: content, tags: tags, isPinned: pinned));

  await note('Pièces pour le passeport',
      'Acte de naissance, certificat de nationalité, 2 photos, ancien passeport et timbre fiscal de 15 000 FDJ.',
      ['démarches'], pinned: true);
  await note('Numéros utiles',
      'CNSS : 21 35 xx xx · Mairie de Djibouti : 21 35 xx xx · Hôpital Peltier : 21 35 xx xx',
      ['contacts']);
  await note('Idées week-end', 'Plage de la Siesta, lac Assal, déjeuner à Tadjourah.', ['perso']);
}
