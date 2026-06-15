// ─── Annuaire Service ────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'api_client.dart';

// ── Modèles ──────────────────────────────────────────────────────────────────

class ServiceAddress {
  final String street;
  final String district;
  final String city;
  final Map<String, double>? coordinates;

  const ServiceAddress({
    required this.street,
    required this.district,
    required this.city,
    this.coordinates,
  });

  factory ServiceAddress.fromJson(Map<String, dynamic> json) => ServiceAddress(
        street: json['street'] as String? ?? '',
        district: json['district'] as String? ?? '',
        city: json['city'] as String? ?? 'Djibouti-ville',
        coordinates: json['coordinates'] != null
            ? {
                'lat': (json['coordinates']['lat'] as num).toDouble(),
                'lng': (json['coordinates']['lng'] as num).toDouble(),
              }
            : null,
      );
}

class AmiinService {
  final String id;
  final String name;
  final String? ministry;
  final String category;
  final String sousCategorie;
  final String quartier;
  final String? description;
  final String? phone;
  final String? email;
  final String? website;
  final String? hours;
  final ServiceAddress address;
  final bool? isFavorite;
  final double? distanceKm;

  const AmiinService({
    required this.id,
    required this.name,
    this.ministry,
    required this.category,
    this.sousCategorie = '',
    this.quartier = '',
    this.description,
    this.phone,
    this.email,
    this.website,
    this.hours,
    required this.address,
    this.isFavorite,
    this.distanceKm,
  });

  factory AmiinService.fromJson(Map<String, dynamic> json) => AmiinService(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ministry: json['ministry'] as String?,
        category: json['category'] as String? ?? 'autre',
        sousCategorie: json['sous_categorie'] as String? ?? '',
        quartier: json['quartier'] as String? ?? '',
        description: json['description'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        website: json['website'] as String?,
        hours: json['hours'] as String?,
        address: ServiceAddress.fromJson(
            json['address'] as Map<String, dynamic>? ?? {}),
        isFavorite: json['isFavorite'] as bool?,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      );

  // Construit depuis une entrée locale (annuaire_enrichi.json)
  factory AmiinService.fromLocal(Map<String, dynamic> e) => AmiinService(
        id: e['id'] as String? ?? '',
        name: e['nom'] as String? ?? '',
        category: e['categorie'] as String? ?? '',
        sousCategorie: e['sous_categorie'] as String? ?? '',
        quartier: e['quartier'] as String? ?? '',
        phone: e['telephone'] as String?,
        address: ServiceAddress(
          street: e['adresse'] as String? ?? '',
          district: e['quartier'] as String? ?? '',
          city: e['ville_region'] as String? ?? 'Djibouti-ville',
          coordinates: (e['latitude'] != null && e['longitude'] != null)
              ? {
                  'lat': (e['latitude'] as num).toDouble(),
                  'lng': (e['longitude'] as num).toDouble(),
                }
              : null,
        ),
      );
}

// ── Données locales (asset) ───────────────────────────────────────────────────

class AnnuaireLocalData {
  final List<AmiinService> entries;
  final List<String> categories;
  final List<String> sousCategories;
  final List<String> quartiers;
  final List<String> villes;
  final List<Map<String, dynamic>> arborescence; // {categorie, sous_categories[]}

  const AnnuaireLocalData({
    required this.entries,
    required this.categories,
    required this.sousCategories,
    required this.quartiers,
    required this.villes,
    required this.arborescence,
  });
}

// ── Service principal ─────────────────────────────────────────────────────────

class AnnuaireService {
  final Dio _dio = api;
  AnnuaireLocalData? _localData;

  // ── Données locales ──────────────────────────────────────────────────────

  Future<AnnuaireLocalData> loadLocal() async {
    if (_localData != null) return _localData!;
    final raw = await rootBundle.loadString('assets/data/annuaire_enrichi.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (json['entries'] as List)
        .map((e) => AmiinService.fromLocal(e as Map<String, dynamic>))
        .toList();
    _localData = AnnuaireLocalData(
      entries: entries,
      categories: (json['categories'] as List).cast<String>(),
      sousCategories: (json['sous_categories'] as List).cast<String>(),
      quartiers: (json['quartiers'] as List).cast<String>(),
      villes: (json['villes'] as List).cast<String>(),
      arborescence: (json['arborescence'] as List).cast<Map<String, dynamic>>(),
    );
    return _localData!;
  }

  /// Navigation locale : toutes les entrées d'une catégorie / sous-catégorie / quartier.
  Future<List<AmiinService>> browse({
    String? categorie,
    String? sousCategorie,
    String? quartier,
    String? ville,
  }) async {
    final data = await loadLocal();
    return data.entries.where((e) {
      if (categorie != null && e.category != categorie) return false;
      if (sousCategorie != null && e.sousCategorie != sousCategorie) return false;
      if (quartier != null && e.quartier != quartier) return false;
      if (ville != null && e.address.city != ville) return false;
      return true;
    }).toList();
  }

  /// Recherche locale fuzzy (insensible à la casse, cherche dans nom + catégorie + adresse).
  Future<List<AmiinService>> searchLocal(String query,
      {String? categorie, String? quartier}) async {
    if (query.isEmpty) return browse(categorie: categorie, quartier: quartier);
    final data = await loadLocal();
    final q = query.toLowerCase();
    return data.entries.where((e) {
      if (categorie != null && e.category != categorie) return false;
      if (quartier != null && e.quartier != quartier) return false;
      return e.name.toLowerCase().contains(q) ||
          e.sousCategorie.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.address.street.toLowerCase().contains(q) ||
          e.quartier.toLowerCase().contains(q);
    }).toList();
  }

  // ── API backend (recherche sémantique) ───────────────────────────────────

  /// Recherche sémantique via Qdrant (gère les fautes, troncatures, synonymes).
  Future<List<AmiinService>> search(
    String query, {
    String? categorie,
    String? sousCategorie,
    String? quartier,
    String? ville,
  }) async {
    try {
      final params = <String, dynamic>{'q': query};
      if (categorie != null) params['categorie'] = categorie;
      if (sousCategorie != null) params['sous_categorie'] = sousCategorie;
      if (quartier != null) params['quartier'] = quartier;
      if (ville != null) params['ville'] = ville;
      final response =
          await _dio.get('/annuaire/services', queryParameters: params);
      final List services = response.data['services'] as List? ?? [];
      return services.map((j) => AmiinService.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      // Fallback local si le backend est indisponible
      return searchLocal(query, categorie: categorie, quartier: quartier);
    }
  }

  /// Services proches (GPS).
  Future<List<AmiinService>> getNearby(double lat, double lng,
      {int radiusKm = 5, String? categorie}) async {
    try {
      final params = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius': radiusKm,
        if (categorie != null) 'categorie': categorie,
      };
      final response =
          await _dio.get('/annuaire/services/nearby', queryParameters: params);
      final List services = response.data['services'] as List? ?? [];
      return services.map((j) => AmiinService.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Catégories disponibles (depuis backend avec comptages).
  Future<Map<String, dynamic>> getCategories() async {
    final response = await _dio.get('/annuaire/categories');
    return response.data as Map<String, dynamic>;
  }

  /// Cherche une entrée par ID dans le JSON local.
  Future<AmiinService?> getServiceLocal(String id) async {
    final data = await loadLocal();
    try {
      return data.entries.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Détail d'un service — local d'abord, backend en fallback.
  Future<AmiinService> getService(String id) async {
    final local = await getServiceLocal(id);
    if (local != null) return local;
    // Fallback backend (pour les IDs venant d'une recherche sémantique)
    final response = await _dio.get('/annuaire/services/$id');
    return AmiinService.fromJson(response.data['service'] as Map<String, dynamic>);
  }

  /// Favoris.
  Future<List<AmiinService>> getFavorites() async {
    final response = await _dio.get('/annuaire/favorites');
    final List services = response.data['services'] as List? ?? [];
    return services.map((j) => AmiinService.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    if (isFavorite) {
      await _dio.post('/annuaire/favorites/$id');
    } else {
      await _dio.delete('/annuaire/favorites/$id');
    }
  }
}

final annuaireService = AnnuaireService();
