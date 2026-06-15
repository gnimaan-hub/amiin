// ─── GoRouter configuration with StatefulShellRoute (6 tabs) ─────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/home/home_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/agenda/agenda_screen.dart';
import '../screens/annuaire/annuaire_screen.dart';
import '../screens/demarches/demarches_screen.dart';
import '../screens/notes/notes_screen.dart';
import '../screens/agenda/event_detail_screen.dart';
import '../screens/agenda/create_event_screen.dart';
import '../screens/annuaire/service_detail_screen.dart';
import '../screens/demarches/demarche_detail_screen.dart';
import '../screens/demarches/user_demarche_tracking_screen.dart';
import '../screens/notes/note_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../widgets/connectivity_banner.dart';
import '../services/agenda_badge_notifier.dart';


final GlobalKey<NavigatorState> _homeNavKey      = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _chatNavKey      = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _agendaNavKey    = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _annuaireNavKey  = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _demarchesNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _notesNavKey     = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return Scaffold(
          body: ConnectivityBanner(
            child: _AnimatedShell(
              currentIndex: navigationShell.currentIndex,
              child: navigationShell,
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: navigationShell.currentIndex,
            onTap: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Accueil',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble),
                label: 'Amiin',
              ),
              BottomNavigationBarItem(
                icon: ValueListenableBuilder<int>(
                  valueListenable: agendaTodayCount,
                  builder: (_, count, __) => Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                activeIcon: ValueListenableBuilder<int>(
                  valueListenable: agendaTodayCount,
                  builder: (_, count, __) => Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.calendar_today),
                  ),
                ),
                label: 'Agenda',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.note_outlined),
                activeIcon: Icon(Icons.note),
                label: 'Notes',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Annuaire',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment_outlined),
                activeIcon: Icon(Icons.assignment),
                label: 'Démarches',
              ),
            ],
            selectedItemColor: const Color(0xFFB85530),
            unselectedItemColor: const Color(0xFF9C8E80),
            showUnselectedLabels: true,
            selectedFontSize: 11,
            unselectedFontSize: 11,
          ),
        );
      },
      branches: [
        // 0 — Accueil
        StatefulShellBranch(
          navigatorKey: _homeNavKey,
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // 1 — Amiin (chat)
        StatefulShellBranch(
          navigatorKey: _chatNavKey,
          routes: [
            GoRoute(
              path: '/chat',
              name: 'chat',
              builder: (context, state) => const ChatScreen(),
            ),
          ],
        ),
        // 2 — Agenda
        StatefulShellBranch(
          navigatorKey: _agendaNavKey,
          routes: [
            GoRoute(
              path: '/agenda',
              name: 'agenda',
              builder: (context, state) => const AgendaScreen(),
              routes: [
                GoRoute(
                  path: 'create',
                  name: 'createEvent',
                  builder: (context, state) {
                    final date = state.uri.queryParameters['date'];
                    return CreateEventScreen(initialDate: date);
                  },
                ),
                GoRoute(
                  path: 'event/:eventId',
                  name: 'eventDetail',
                  builder: (context, state) {
                    final eventId = state.pathParameters['eventId']!;
                    return EventDetailScreen(eventId: eventId);
                  },
                ),
              ],
            ),
          ],
        ),
        // 3 — Notes
        StatefulShellBranch(
          navigatorKey: _notesNavKey,
          routes: [
            GoRoute(
              path: '/notes',
              name: 'notes',
              builder: (context, state) => const NotesScreen(),
              routes: [
                GoRoute(
                  path: 'create',
                  name: 'createNote',
                  builder: (context, state) => const CreateNoteScreen(),
                ),
                GoRoute(
                  path: ':noteId',
                  name: 'noteDetail',
                  builder: (context, state) {
                    final noteId = state.pathParameters['noteId']!;
                    return NoteDetailScreen(noteId: noteId);
                  },
                ),
              ],
            ),
          ],
        ),
        // 4 — Annuaire
        StatefulShellBranch(
          navigatorKey: _annuaireNavKey,
          routes: [
            GoRoute(
              path: '/annuaire',
              name: 'annuaire',
              builder: (context, state) => const AnnuaireScreen(),
              routes: [
                GoRoute(
                  path: ':serviceId',
                  name: 'serviceDetail',
                  builder: (context, state) {
                    final serviceId = state.pathParameters['serviceId']!;
                    return ServiceDetailScreen(serviceId: serviceId);
                  },
                ),
              ],
            ),
          ],
        ),
        // 5 — Démarches
        StatefulShellBranch(
          navigatorKey: _demarchesNavKey,
          routes: [
            GoRoute(
              path: '/demarches',
              name: 'demarches',
              builder: (context, state) => const DemarchesScreen(),
              routes: [
                GoRoute(
                  path: 'user/:userDemarcheId',
                  name: 'userDemarche',
                  builder: (context, state) {
                    final userDemarcheId = state.pathParameters['userDemarcheId']!;
                    return UserDemarcheTrackingScreen(userDemarcheId: userDemarcheId);
                  },
                ),
                GoRoute(
                  path: ':demarcheId',
                  name: 'demarcheDetail',
                  builder: (context, state) {
                    final demarcheId = state.pathParameters['demarcheId']!;
                    return DemarcheDetailScreen(demarcheId: demarcheId);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // Routes globales hors shell
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
);

// ── Animated shell : slide + fade entre onglets ────────────────────────────
class _AnimatedShell extends StatefulWidget {
  final Widget child;
  final int currentIndex;

  const _AnimatedShell({required this.child, required this.currentIndex});

  @override
  State<_AnimatedShell> createState() => _AnimatedShellState();
}

class _AnimatedShellState extends State<_AnimatedShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _slide = Tween(begin: Offset.zero, end: Offset.zero).animate(_ctrl);
    _fade  = Tween(begin: 1.0, end: 1.0).animate(_ctrl);
    _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_AnimatedShell old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      final goingRight = widget.currentIndex > old.currentIndex;
      _slide = Tween(
        begin: Offset(goingRight ? 0.06 : -0.06, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _fade = Tween(begin: 0.75, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: child),
      ),
      child: widget.child,
    );
  }
}
