// ─── GoRouter configuration with StatefulShellRoute (6 tabs) ─────────────────

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../screens/splash/splash_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/settings_profile_screen.dart';
import '../screens/settings/settings_account_screen.dart';
import '../screens/settings/settings_security_screen.dart';
import '../screens/settings/settings_assistant_screen.dart';
import '../screens/settings/settings_appearance_screen.dart';
import '../screens/settings/settings_text_screen.dart';
import '../screens/settings/settings_notifications_screen.dart';
import '../screens/settings/settings_language_screen.dart';
import '../screens/settings/settings_privacy_screen.dart';
import '../screens/settings/settings_billing_screen.dart';
import '../screens/settings/settings_about_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../widgets/connectivity_banner.dart';
import '../config/demo.dart';
import '../services/agenda_badge_notifier.dart';
import '../services/auth_service.dart';
import '../theme/typography.dart';
import '../theme/themes.dart';

final GlobalKey<NavigatorState> _homeNavKey      = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _chatNavKey      = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _agendaNavKey    = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _annuaireNavKey  = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _demarchesNavKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _notesNavKey     = GlobalKey<NavigatorState>();

// ── Transitions de pages de la marque ─────────────────────────────────────────
// Sous-écrans (détail, création, réglages) : glissement montant + fondu,
// 260 ms, courbe décélérée — le même langage de mouvement que le widget
// d'accueil et les toasts.

CustomTransitionPage<T> _amiinPage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  refreshListenable: authService,
  redirect: (context, state) {
    final loc      = state.matchedLocation;
    final loggedIn = authService.isLoggedIn;

    // Splash gère elle-même la navigation après init
    if (loc == '/splash') return null;

    // Démo : inscription fermée (accès sur invitation).
    if (kAmiinDemo && loc == '/register') return '/login';

    // Écrans auth : redirige les utilisateurs connectés vers /home
    if (loc == '/login' || loc == '/register') {
      return loggedIn ? '/home' : null;
    }

    // Routes protégées : redirige si non connecté
    if (!loggedIn) return '/login';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        // Retour physique (bouton ou swipe) depuis n'importe quel onglet :
        // - accueil → ferme l'app (canPop: true)
        // - autre onglet (à sa racine) → revient à l'accueil
        // Les sous-routes d'un onglet sont gérées par le navigator de la branche
        // avant que ce PopScope ne soit consulté.
        return PopScope(
          canPop: navigationShell.currentIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) navigationShell.goBranch(0);
          },
          child: Scaffold(
            // La barre d'onglets flotte : le contenu défile dessous.
            extendBody: true,
            body: ConnectivityBanner(
              child: _AnimatedShell(
                currentIndex: navigationShell.currentIndex,
                child: navigationShell,
              ),
            ),
            bottomNavigationBar: AmiinNavBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            ),
          ),
        );
      },
      branches: [
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
                  pageBuilder: (context, state) {
                    final date = state.uri.queryParameters['date'];
                    return _amiinPage(state, CreateEventScreen(initialDate: date));
                  },
                ),
                GoRoute(
                  path: 'event/:eventId',
                  name: 'eventDetail',
                  pageBuilder: (context, state) {
                    final eventId = state.pathParameters['eventId']!;
                    return _amiinPage(state, EventDetailScreen(eventId: eventId));
                  },
                ),
              ],
            ),
          ],
        ),
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
                  pageBuilder: (context, state) =>
                      _amiinPage(state, const CreateNoteScreen()),
                ),
                GoRoute(
                  path: ':noteId',
                  name: 'noteDetail',
                  pageBuilder: (context, state) {
                    final noteId = state.pathParameters['noteId']!;
                    return _amiinPage(state, NoteDetailScreen(noteId: noteId));
                  },
                ),
              ],
            ),
          ],
        ),
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
                  pageBuilder: (context, state) {
                    final serviceId = state.pathParameters['serviceId']!;
                    return _amiinPage(state, ServiceDetailScreen(serviceId: serviceId));
                  },
                ),
              ],
            ),
          ],
        ),
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
                  pageBuilder: (context, state) {
                    final userDemarcheId = state.pathParameters['userDemarcheId']!;
                    return _amiinPage(state, UserDemarcheTrackingScreen(userDemarcheId: userDemarcheId));
                  },
                ),
                GoRoute(
                  path: ':demarcheId',
                  name: 'demarcheDetail',
                  pageBuilder: (context, state) {
                    final demarcheId = state.pathParameters['demarcheId']!;
                    return _amiinPage(state, DemarcheDetailScreen(demarcheId: demarcheId));
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) =>
          _amiinPage(state, const SettingsScreen()),
      routes: [
        GoRoute(path: 'profile',       name: 'settingsProfile',       pageBuilder: (c, s) => _amiinPage(s, const SettingsProfileScreen())),
        GoRoute(path: 'account',       name: 'settingsAccount',       pageBuilder: (c, s) => _amiinPage(s, const SettingsAccountScreen())),
        GoRoute(path: 'security',      name: 'settingsSecurity',      pageBuilder: (c, s) => _amiinPage(s, const SettingsSecurityScreen())),
        GoRoute(path: 'assistant',     name: 'settingsAssistant',     pageBuilder: (c, s) => _amiinPage(s, const SettingsAssistantScreen())),
        GoRoute(path: 'appearance',    name: 'settingsAppearance',    pageBuilder: (c, s) => _amiinPage(s, const SettingsAppearanceScreen())),
        GoRoute(path: 'text',          name: 'settingsText',          pageBuilder: (c, s) => _amiinPage(s, const SettingsTextScreen())),
        GoRoute(path: 'notifications', name: 'settingsNotifications', pageBuilder: (c, s) => _amiinPage(s, const SettingsNotificationsScreen())),
        GoRoute(path: 'language',      name: 'settingsLanguage',      pageBuilder: (c, s) => _amiinPage(s, const SettingsLanguageScreen())),
        GoRoute(path: 'privacy',       name: 'settingsPrivacy',       pageBuilder: (c, s) => _amiinPage(s, const SettingsPrivacyScreen())),
        GoRoute(path: 'billing',       name: 'settingsBilling',       pageBuilder: (c, s) => _amiinPage(s, const SettingsBillingScreen())),
        GoRoute(path: 'about',         name: 'settingsAbout',         pageBuilder: (c, s) => _amiinPage(s, const SettingsAboutScreen())),
      ],
    ),
  ],
);

// ── Barre d'onglets flottante en verre dépoli ────────────────────────────────
// Détachée des bords, elle flotte au-dessus du contenu qui défile dessous,
// flouté. Une capsule teintée de la couleur du mode (encre pour l'accueil,
// turquoise pour le secrétariat, ocre pour l'information) glisse d'un onglet
// à l'autre.

/// Barre d'onglets principale (publique pour l'aperçu de développement).
class AmiinNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AmiinNavBar({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined,           activeIcon: Icons.home_rounded,        label: 'Accueil'),
    _NavItem(icon: Icons.chat_bubble_outline,     activeIcon: Icons.chat_bubble_rounded, label: 'Amiin'),
    _NavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today,      label: 'Agenda',    hasBadge: true),
    _NavItem(icon: Icons.edit_note_outlined,      activeIcon: Icons.edit_note,           label: 'Notes'),
    _NavItem(icon: Icons.people_outline,          activeIcon: Icons.people,              label: 'Annuaire'),
    _NavItem(icon: Icons.assignment_outlined,     activeIcon: Icons.assignment_rounded,  label: 'Démarches'),
  ];

  static const double _height = 62;
  static const double _radius = 26;
  static const _curve = Cubic(0.2, 0.8, 0.2, 1);
  static const _duration = Duration(milliseconds: 340);

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final dark = ac.brightness == Brightness.dark;
    final modeColor = _tabColor(context, currentIndex);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : _duration;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DecoratedBox(
          // Ombre portée hors du découpage : la barre flotte au-dessus du contenu.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: (dark ? Colors.black : ac.ink).withValues(alpha: dark ? 0.45 : 0.14),
                blurRadius: 32,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: _height,
                decoration: BoxDecoration(
                  // Verre : voile de surface translucide, plus clair en haut.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ac.surface.withValues(alpha: dark ? 0.66 : 0.72),
                      ac.surface.withValues(alpha: dark ? 0.52 : 0.58),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const inset = 5.0;
                    final slot = (constraints.maxWidth - 2 * inset) / _items.length;
                    return Stack(
                      children: [
                        // Capsule de sélection qui glisse
                        AnimatedPositioned(
                          duration: duration,
                          curve: _curve,
                          left: inset + slot * currentIndex + 2,
                          width: slot - 4,
                          top: inset,
                          bottom: inset,
                          child: AnimatedContainer(
                            duration: duration,
                            curve: _curve,
                            decoration: BoxDecoration(
                              color: modeColor.withValues(alpha: dark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(_radius - inset),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: inset),
                          child: Row(
                            children: [
                              for (var i = 0; i < _items.length; i++)
                                Expanded(
                                  child: _NavButton(
                                    item: _items[i],
                                    selected: i == currentIndex,
                                    color: i == currentIndex ? modeColor : ac.muted,
                                    duration: duration,
                                    onTap: () {
                                      if (i != currentIndex) HapticFeedback.selectionClick();
                                      onTap(i);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Couleur du mode de l'onglet : encre (accueil), turquoise (secrétariat),
/// ocre (information).
Color _tabColor(BuildContext context, int index) {
  if (index >= 4) return context.ac.infoAccent;
  if (index >= 1) return context.ac.secretariatAccent;
  return context.ac.ink;
}

class _NavButton extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final Color color;
  final Duration duration;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.color,
    required this.duration,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final icon = Icon(
      widget.selected ? item.activeIcon : item.icon,
      size: 22,
      color: widget.color,
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              item.hasBadge
                  ? ValueListenableBuilder<int>(
                      valueListenable: agendaTodayCount,
                      builder: (_, count, __) => Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count', style: const TextStyle(fontSize: 9)),
                        backgroundColor: context.ac.alertColor,
                        child: icon,
                      ),
                    )
                  : icon,
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: widget.duration,
                style: TextStyle(
                  fontFamily: FontFamily.geo,
                  fontSize: 10,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.color,
                  letterSpacing: -0.1,
                ),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.visible, softWrap: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool hasBadge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.hasBadge = false,
  });
}

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
      duration: const Duration(milliseconds: 200),
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
        begin: Offset(goingRight ? 0.05 : -0.05, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _fade = Tween(begin: 0.8, end: 1.0)
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
