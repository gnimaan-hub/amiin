// ─── AuthService — JWT + refresh token via flutter_secure_storage ────────────

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

  AuthUser? get currentUser  => _user;
  bool      get isLoggedIn   => _user != null;
  bool      get initialized  => _initialized;

  // ── Initialisation (appelée au démarrage depuis SplashScreen) ────────────

  Future<void> init() async {
    final accessToken  = await _storage.read(key: _kAccessToken);
    final refreshToken = await _storage.read(key: _kRefreshToken);

    if (accessToken == null || refreshToken == null) {
      _initialized = true;
      notifyListeners();
      return;
    }

    try {
      final resp = await _authDio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      _user = _parseUser(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _tryRefresh(refreshToken);
      } else {
        // Pas de réseau → utiliser le cache local si dispo
        _user = await _cachedUser();
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _tryRefresh(String refreshToken) async {
    try {
      final resp = await _authDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccess  = resp.data['access_token']  as String;
      final newRefresh = resp.data['refresh_token'] as String;
      await _storeTokens(accessToken: newAccess, refreshToken: newRefresh);

      final meResp = await _authDio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $newAccess'}),
      );
      _user = _parseUser(meResp.data as Map<String, dynamic>);
      await _cacheUser(_user!);
    } catch (_) {
      await _clearAll();
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

  bool _isRefreshing = false;

  Future<String?> refreshAccessToken() async {
    if (_isRefreshing) return null;
    _isRefreshing = true;
    try {
      final refreshToken = await _storage.read(key: _kRefreshToken);
      if (refreshToken == null) return null;

      final resp = await _authDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccess  = resp.data['access_token']  as String;
      final newRefresh = resp.data['refresh_token'] as String;
      await _storeTokens(accessToken: newAccess, refreshToken: newRefresh);
      return newAccess;
    } catch (_) {
      _user = null;
      await _clearAll();
      notifyListeners();
      return null;
    } finally {
      _isRefreshing = false;
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

  Future<void> _clearAll() => _storage.deleteAll();

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
