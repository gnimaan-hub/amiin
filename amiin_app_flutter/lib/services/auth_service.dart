// ─── AuthService — JWT + refresh token via flutter_secure_storage ────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

// Base URL partagée sans importer api_client (évite la dépendance circulaire)
const _kBaseUrl = String.fromEnvironment(
  'AMIIN_API_URL',
  defaultValue: 'https://amiin.onrender.com/v1',
);

const _kAccessToken  = 'access_token';
const _kRefreshToken = 'refresh_token';
const _kUserId       = 'user_id';
const _kEmail        = 'user_email';
const _kDisplayName  = 'user_display_name';

// ── Modèle utilisateur ────────────────────────────────────────────────────────

class AuthUser {
  final String id;
  final String email;
  final String displayName;
  const AuthUser({required this.id, required this.email, required this.displayName});
}

// ── Service ───────────────────────────────────────────────────────────────────

class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Dio dédié aux appels auth — pas d'intercepteurs pour éviter les boucles
  static final _authDio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  AuthUser? _user;
  bool _initialized = false;

  // Positionné à true uniquement dans l'isolate WorkManager (widget de fond).
  // Cet isolate ne doit jamais pouvoir effacer la session de l'app au premier
  // plan : un refresh échoué en tâche de fond doit juste abandonner ce cycle,
  // pas déconnecter l'utilisateur.
  static bool _isBackgroundIsolate = false;
  static void markBackgroundIsolate() => _isBackgroundIsolate = true;

  AuthUser? get currentUser  => _user;
  bool      get isLoggedIn   => _user != null;
  bool      get initialized  => _initialized;

  // ── Initialisation (appelée au démarrage depuis SplashScreen) ────────────

  Future<void> init() async {
    if (_initialized) {
      debugPrint('[AUTH] init() ignoré : déjà initialisé (isLoggedIn=$isLoggedIn)');
      return;
    }

    final accessToken  = await _storage.read(key: _kAccessToken);
    final refreshToken = await _storage.read(key: _kRefreshToken);
    debugPrint('[AUTH] init() : accessToken=${accessToken != null} refreshToken=${refreshToken != null}');

    // Seul refreshToken conditionne la session : accessToken peut être
    // absent (JWT à courte durée de vie non renouvelé depuis longtemps) sans
    // que la session soit invalide pour autant — _validateSession tentera un
    // refresh dans ce cas plutôt que de forcer un retour au login.
    if (refreshToken == null) {
      _initialized = true;
      debugPrint('[AUTH] init() : pas de refresh token → non connecté');
      notifyListeners();
      return;
    }

    // Offline-first : si un utilisateur est en cache, on le considère connecté
    // tout de suite et on valide la session en arrière-plan. Le backend
    // (Render free tier) peut mettre 30 s à se réveiller — hors de question
    // de bloquer le démarrage là-dessus.
    _user = await _cachedUser();
    _initialized = true;
    debugPrint('[AUTH] init() : cachedUser=${_user != null} → isLoggedIn=$isLoggedIn');
    notifyListeners();

    if (_user != null) {
      unawaited(_validateSession(accessToken, refreshToken));
    } else {
      // Tokens présents mais pas de cache : il faut le réseau pour savoir
      await _validateSession(accessToken, refreshToken);
    }
  }

  /// Vérifie la session auprès du backend. Sur 401 (ou pas d'accessToken du
  /// tout) → tentative de refresh (échec = déconnexion). Sur erreur réseau →
  /// on garde la session locale.
  Future<void> _validateSession(String? accessToken, String refreshToken) async {
    if (accessToken == null) {
      await _tryRefresh(refreshToken);
      notifyListeners();
      return;
    }
    try {
      final resp = await _authDio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      _user = _parseUser(resp.data as Map<String, dynamic>);
      await _cacheUser(_user!);
      debugPrint('[AUTH] _validateSession : OK (${_user!.email})');
    } on DioException catch (e) {
      debugPrint('[AUTH] _validateSession : DioException status=${e.response?.statusCode} type=${e.type}');
      if (e.response?.statusCode == 401) {
        await _tryRefresh(refreshToken);
      }
      // Pas de réseau / serveur endormi → on conserve l'état local
    } catch (e) {
      debugPrint('[AUTH] _validateSession : erreur inattendue $e');
      // Jamais de crash au démarrage pour une erreur de validation
    }
    notifyListeners();
  }

  // Passe systématiquement par refreshAccessToken() (verrou partagé, voir
  // plus bas) au lieu de dupliquer l'appel /auth/refresh ici : c'était la
  // source d'une course avec l'intercepteur ApiClient — deux appels
  // simultanés pouvaient consommer le même refresh token à usage unique et
  // se faire mutuellement invalider, provoquant une déconnexion + purge des
  // données locales alors que la session était en fait valide.
  Future<void> _tryRefresh(String refreshToken) async {
    final newAccess = await refreshAccessToken();
    if (newAccess == null) {
      debugPrint('[AUTH] _tryRefresh : refresh échoué ou déjà géré par un autre appel');
      return;
    }
    try {
      final meResp = await _authDio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $newAccess'}),
      );
      _user = _parseUser(meResp.data as Map<String, dynamic>);
      await _cacheUser(_user!);
      debugPrint('[AUTH] _tryRefresh : OK, nouvelle session pour ${_user!.email}');
    } catch (e) {
      debugPrint('[AUTH] _tryRefresh : /auth/me après refresh a échoué : $e');
    }
  }

  // ── Actions publiques ─────────────────────────────────────────────────────

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final resp = await _authDio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'display_name': displayName,
    });
    await _handleTokens(resp.data as Map<String, dynamic>);
  }

  Future<void> login({required String email, required String password}) async {
    final resp = await _authDio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    await _handleTokens(resp.data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: _kRefreshToken);
    if (refreshToken != null) {
      try {
        await _authDio.post('/auth/logout', data: {'refresh_token': refreshToken});
      } catch (_) {}
    }
    _user = null;
    await _clearAll();
    notifyListeners();
  }

  // ── Appelé par l'intercepteur ApiClient pour gérer un 401 ────────────────

  // Verrou partagé par TOUS les appelants (intercepteur ApiClient sur 401,
  // et _validateSession au démarrage) : un refresh déjà en cours est
  // réutilisé au lieu d'en déclencher un second en parallèle, ce qui
  // évitait auparavant deux requêtes /auth/refresh simultanées avec le même
  // refresh token à usage unique (l'une des deux étant systématiquement
  // rejetée par le backend).
  Future<String?>? _refreshInFlight;

  Future<String?> refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
    // La tâche de fond du widget tourne dans un isolate WorkManager séparé :
    // son AuthService/_refreshInFlight est une instance distincte, sans
    // aucun verrou partagé avec l'app au premier plan. Si elle tentait un
    // refresh en même temps que l'app, les deux consommeraient le même
    // refresh token à usage unique et l'une des deux corromprait la session
    // de l'autre (accessToken écrasé/supprimé alors que refreshToken
    // survit). Elle n'utilise donc que le token courant, best-effort ; en
    // cas de 401 elle abandonne simplement ce cycle et réessaiera dans
    // l'heure, une fois l'app au premier plan aura naturellement rafraîchi.
    if (_isBackgroundIsolate) return null;

    final refreshToken = await _storage.read(key: _kRefreshToken);
    if (refreshToken == null) return null;

    try {
      final resp = await _authDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccess  = resp.data['access_token']  as String;
      final newRefresh = resp.data['refresh_token'] as String;
      await _storeTokens(accessToken: newAccess, refreshToken: newRefresh);
      return newAccess;
    } catch (e) {
      // Le refresh tourne désormais à chaque démarrage (l'accessToken ne
      // survit pas toujours au redémarrage du process). Une erreur réseau
      // (hors ligne, backend endormi, timeout) ne prouve absolument pas que
      // le refresh token est invalide — seul un vrai rejet du serveur
      // (401/403) le prouve. Ne jamais déconnecter sur une simple absence
      // de réseau, sous peine de forcer un login à chaque ouverture hors
      // connexion (contraire au mode offline-first voulu par l'app).
      final isAuthRejection = e is DioException &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 403);
      if (!isAuthRejection) {
        debugPrint('[AUTH] _doRefresh : échec réseau (pas d\'auth rejetée) → session conservée : $e');
        return null;
      }

      // Si un autre runtime a déjà tourné le refresh token entre-temps, la
      // session est en fait valide, il ne faut surtout pas l'effacer.
      final current = await _storage.read(key: _kRefreshToken);
      if (current == refreshToken) {
        _user = null;
        await _clearAll();
        notifyListeners();
      }
      return null;
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  // ── Helpers privés ────────────────────────────────────────────────────────

  Future<void> _handleTokens(Map<String, dynamic> data) async {
    final accessToken  = data['access_token']  as String;
    final refreshToken = data['refresh_token'] as String;
    await _storeTokens(accessToken: accessToken, refreshToken: refreshToken);

    final meResp = await _authDio.get(
      '/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    _user = _parseUser(meResp.data as Map<String, dynamic>);
    await _cacheUser(_user!);
    notifyListeners();
  }

  Future<void> _storeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccessToken,  value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  Future<void> _cacheUser(AuthUser u) async {
    await _storage.write(key: _kUserId,      value: u.id);
    await _storage.write(key: _kEmail,       value: u.email);
    await _storage.write(key: _kDisplayName, value: u.displayName);
  }

  Future<AuthUser?> _cachedUser() async {
    final id    = await _storage.read(key: _kUserId);
    final email = await _storage.read(key: _kEmail);
    final name  = await _storage.read(key: _kDisplayName);
    if (id == null || email == null) return null;
    return AuthUser(id: id, email: email, displayName: name ?? email.split('@')[0]);
  }

  // Supprime uniquement les clés d'auth, jamais deleteAll() : ce storage est
  // partagé avec d'autres services (voir hive_utils.dart) et un deleteAll()
  // effacerait des données qui n'ont rien à voir avec la session.
  Future<void> _clearAll() => Future.wait([
    _storage.delete(key: _kAccessToken),
    _storage.delete(key: _kRefreshToken),
    _storage.delete(key: _kUserId),
    _storage.delete(key: _kEmail),
    _storage.delete(key: _kDisplayName),
  ]);

  AuthUser _parseUser(Map<String, dynamic> d) => AuthUser(
    id:          d['id']           as String,
    email:       d['email']        as String,
    displayName: d['display_name'] as String,
  );
}

// Singleton global
final authService = AuthService();

// Helper : message lisible depuis une DioException
String authErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['detail'] is String) return data['detail'] as String;
  switch (e.response?.statusCode) {
    case 409: return 'Cet email est déjà utilisé.';
    case 401: return 'Email ou mot de passe incorrect.';
    case 422: return 'Données invalides. Vérifiez les champs.';
    default:  return 'Erreur de connexion. Vérifiez votre réseau.';
  }
}
