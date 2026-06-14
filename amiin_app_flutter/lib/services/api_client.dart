// ─── API client ─────────────────────────────────────────────────────────────
// Configuration BASE_URL et interceptors.
//
// DEV local :
//   flutter run --dart-define=AMIIN_API_URL=http://172.25.25.54:8000/v1
//
// PRODUCTION (Render) :
//   flutter build apk --dart-define=AMIIN_API_URL=https://amiin.onrender.com/v1
//
// La valeur par défaut pointe vers le backend Render (production).
// Passer --dart-define=AMIIN_API_URL=http://... pour développer en local.

import 'package:dio/dio.dart';

class ApiClient {
  static const String baseUrl = String.fromEnvironment(
    'AMIIN_API_URL',
    defaultValue: 'https://amiin.onrender.com/v1',
  );

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 90),
    headers: {
      'Content-Type': 'application/json',
      'Accept-Language': 'fr',
    },
  ));

  // Constructeur privé pour singleton
  ApiClient._internal();

  static final ApiClient _instance = ApiClient._internal();

  factory ApiClient() {
    return _instance;
  }

  Dio get dio => _dio;

  static void init() {
    // Request interceptor: inject auth token (TODO)
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // TODO: récupérer token JWT stocké localement
        // final token = await storage.read(key: 'auth_token');
        // if (token != null) options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      },
      onError: (DioException error, handler) {
        // Normaliser les erreurs — `data` peut être une Map JSON, une String
        // (page d'erreur HTML d'un proxy) ou null : ne jamais indexer à l'aveugle.
        String message;
        final data = error.response?.data;
        if (data is Map && data['message'] is String) {
          message = data['message'] as String;
        } else if (error.response != null) {
          message = 'Erreur serveur (${error.response?.statusCode})';
        } else {
          message = error.message ?? 'Une erreur est survenue.';
        }
        return handler.reject(DioException(
          requestOptions: error.requestOptions,
          type: error.type, // préserver le type (cancel, timeout…)
          error: message,
        ));
      },
    ));
  }
}

// Instance globale facile à importer
final api = ApiClient().dio;
