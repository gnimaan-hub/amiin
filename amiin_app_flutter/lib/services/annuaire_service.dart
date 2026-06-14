// ─── Annuaire Service ────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'api_client.dart';

enum ServiceCategory {
  ministere,
  mairie,
  sante,
  education,
  justice,
  securite,
  transport,
  economie,
  autre,
}

class ServiceAddress {
  final String street;
  final String district;
  final String city;
  final Map<String, double>? coordinates; // {lat, lng}

  ServiceAddress({
    required this.street,
    required this.district,
    required this.city,
    this.coordinates,
  });

  factory ServiceAddress.fromJson(Map<String, dynamic> json) {
    return ServiceAddress(
      street: json['street'],
      district: json['district'],
      city: json['city'],
      coordinates: json['coordinates'] != null
          ? {'lat': json['coordinates']['lat'], 'lng': json['coordinates']['lng']}
          : null,
    );
  }
}

class ServiceHours {
  final String days;
  final String hours;

  ServiceHours({required this.days, required this.hours});

  factory ServiceHours.fromJson(Map<String, dynamic> json) {
    return ServiceHours(days: json['days'], hours: json['hours']);
  }
}

class AmiinService {
  final String id;
  final String name;
  final String? ministry;
  final ServiceCategory category;
  final String? description;
  final String? phone;
  final String? email;
  final String? website;
  final ServiceAddress address;
  final List<ServiceHours>? hours;
  final bool? isFavorite;
  final double? distanceKm;

  AmiinService({
    required this.id,
    required this.name,
    this.ministry,
    required this.category,
    this.description,
    this.phone,
    this.email,
    this.website,
    required this.address,
    this.hours,
    this.isFavorite,
    this.distanceKm,
  });

  factory AmiinService.fromJson(Map<String, dynamic> json) {
    return AmiinService(
      id: json['id'],
      name: json['name'],
      ministry: json['ministry'],
      category: _categoryFromString(json['category']),
      description: json['description'],
      phone: json['phone'],
      email: json['email'],
      website: json['website'],
      address: ServiceAddress.fromJson(json['address']),
      hours: json['hours'] != null
          ? (json['hours'] as List).map((h) => ServiceHours.fromJson(h)).toList()
          : null,
      isFavorite: json['isFavorite'],
      distanceKm: json['distanceKm']?.toDouble(),
    );
  }

  static ServiceCategory _categoryFromString(String value) {
    switch (value) {
      case 'ministere':
        return ServiceCategory.ministere;
      case 'mairie':
        return ServiceCategory.mairie;
      case 'sante':
        return ServiceCategory.sante;
      case 'education':
        return ServiceCategory.education;
      case 'justice':
        return ServiceCategory.justice;
      case 'securite':
        return ServiceCategory.securite;
      case 'transport':
        return ServiceCategory.transport;
      case 'economie':
        return ServiceCategory.economie;
      default:
        return ServiceCategory.autre;
    }
  }
}

class AnnuaireService {
  final Dio _dio = api;

  /// Recherche dans l'annuaire
  Future<List<AmiinService>> search(String query, {ServiceCategory? category}) async {
    final response = await _dio.get('/annuaire/services', queryParameters: {
      'q': query,
      if (category != null) 'category': _categoryToString(category),
    });
    final List<dynamic> servicesJson = response.data['services'];
    return servicesJson.map((json) => AmiinService.fromJson(json)).toList();
  }

  /// Services proches de l'utilisateur
  Future<List<AmiinService>> getNearby(double lat, double lng, {int radiusKm = 5}) async {
    final response = await _dio.get('/annuaire/services/nearby', queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius': radiusKm,
    });
    final List<dynamic> servicesJson = response.data['services'];
    return servicesJson.map((json) => AmiinService.fromJson(json)).toList();
  }

  /// Détail d'un service
  Future<AmiinService> getService(String id) async {
    final response = await _dio.get('/annuaire/services/$id');
    return AmiinService.fromJson(response.data['service']);
  }

  /// Favoris de l'utilisateur
  Future<List<AmiinService>> getFavorites() async {
    final response = await _dio.get('/annuaire/favorites');
    final List<dynamic> servicesJson = response.data['services'];
    return servicesJson.map((json) => AmiinService.fromJson(json)).toList();
  }

  /// Ajouter / retirer un favori
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    if (isFavorite) {
      await _dio.post('/annuaire/favorites/$id');
    } else {
      await _dio.delete('/annuaire/favorites/$id');
    }
  }

  String _categoryToString(ServiceCategory category) {
    switch (category) {
      case ServiceCategory.ministere:
        return 'ministere';
      case ServiceCategory.mairie:
        return 'mairie';
      case ServiceCategory.sante:
        return 'sante';
      case ServiceCategory.education:
        return 'education';
      case ServiceCategory.justice:
        return 'justice';
      case ServiceCategory.securite:
        return 'securite';
      case ServiceCategory.transport:
        return 'transport';
      case ServiceCategory.economie:
        return 'economie';
      default:
        return 'autre';
    }
  }
}

final annuaireService = AnnuaireService();