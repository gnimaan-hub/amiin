// ─── Démarches Service (local Hive + egouv JSON) ────────────────────────────

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'memory_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'widget_bridge.dart';
import '../models/user_action.dart';

// ── Enums ────────────────────────────────────────────────────────────────────

enum DemarcheStatus { aFaire, enCours, terminee, expiree }

enum DemarcheType { procedure, information }

enum DemarcheCategory {
  identiteFamille,
  santeSocial,
  education,
  habitatLogement,
  transport,
  justice,
  economieFinance,
  etrangers,
  loisirsCultures,
  energieEau,
  securite,
}

extension DemarcheCategoryLabel on DemarcheCategory {
  String get label {
    switch (this) {
      case DemarcheCategory.identiteFamille:   return 'Identité & Famille';
      case DemarcheCategory.santeSocial:        return 'Santé & Social';
      case DemarcheCategory.education:          return 'Éducation';
      case DemarcheCategory.habitatLogement:    return 'Habitat & Logement';
      case DemarcheCategory.transport:          return 'Transport';
      case DemarcheCategory.justice:            return 'Justice';
      case DemarcheCategory.economieFinance:    return 'Économie & Finance';
      case DemarcheCategory.etrangers:          return 'Étrangers';
      case DemarcheCategory.loisirsCultures:    return 'Loisirs & Cultures';
      case DemarcheCategory.energieEau:         return 'Énergie & Eau';
      case DemarcheCategory.securite:           return 'Sécurité';
    }
  }

  String get icon {
    switch (this) {
      case DemarcheCategory.identiteFamille:   return '🪪';
      case DemarcheCategory.santeSocial:        return '🏥';
      case DemarcheCategory.education:          return '🎓';
      case DemarcheCategory.habitatLogement:    return '🏠';
      case DemarcheCategory.transport:          return '🚗';
      case DemarcheCategory.justice:            return '⚖️';
      case DemarcheCategory.economieFinance:    return '💼';
      case DemarcheCategory.etrangers:          return '✈️';
      case DemarcheCategory.loisirsCultures:    return '🎭';
      case DemarcheCategory.energieEau:         return '💡';
      case DemarcheCategory.securite:           return '🔐';
    }
  }
}

// ── Modèles ──────────────────────────────────────────────────────────────────

class DemarcheOrganisme {
  final String nom;
  final String? adresse;
  final String? contact;
  final String? horaires;

  DemarcheOrganisme({
    required this.nom,
    this.adresse,
    this.contact,
    this.horaires,
  });

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'adresse': adresse,
    'contact': contact,
    'horaires': horaires,
  };

  factory DemarcheOrganisme.fromJson(Map json) => DemarcheOrganisme(
    nom: (json['nom'] as String?) ?? '',
    adresse: json['adresse'] as String?,
    contact: json['contact'] as String?,
    horaires: json['horaires'] as String?,
  );
}

class DemarcheDocument {
  final String name;
  final String? description;
  final bool isRequired;
  final String? cas; // contexte "cas particulier" (ex : "Habitations en bois")

  DemarcheDocument({
    required this.name,
    this.description,
    required this.isRequired,
    this.cas,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'isRequired': isRequired,
    'cas': cas,
  };

  factory DemarcheDocument.fromJson(Map json) => DemarcheDocument(
    name: json['name'] as String,
    description: json['description'] as String?,
    isRequired: (json['isRequired'] as bool?) ?? true,
    cas: json['cas'] as String?,
  );
}

class DemarcheStep {
  final int order;
  final String title;
  final String description;
  final String? lieu;
  final String? conseil;
  final String? serviceId;

  DemarcheStep({
    required this.order,
    required this.title,
    required this.description,
    this.lieu,
    this.conseil,
    this.serviceId,
  });

  Map<String, dynamic> toJson() => {
    'order': order,
    'title': title,
    'description': description,
    'lieu': lieu,
    'conseil': conseil,
    'serviceId': serviceId,
  };

  factory DemarcheStep.fromJson(Map json) => DemarcheStep(
    order: (json['order'] as int?) ?? 1,
    title: json['title'] as String,
    description: json['description'] as String,
    lieu: json['lieu'] as String?,
    conseil: json['conseil'] as String?,
    serviceId: json['serviceId'] as String?,
  );
}

class Demarche {
  final String id;
  final int sourceId;
  final String title;
  final DemarcheCategory category;
  final DemarcheType type;
  final String summary;
  final String? beneficiaires;
  final String? conditions;
  final String? duration;
  final String? cost;
  final List<DemarcheDocument> documents;
  final List<DemarcheStep> steps;
  final DemarcheOrganisme? organisme;
  final String? resultat;
  final String? sourceUrl;
  final String updatedAt;

  Demarche({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.category,
    required this.type,
    required this.summary,
    this.beneficiaires,
    this.conditions,
    this.duration,
    this.cost,
    required this.documents,
    required this.steps,
    this.organisme,
    this.resultat,
    this.sourceUrl,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'title': title,
    'category': category.name,
    'type': type.name,
    'summary': summary,
    'beneficiaires': beneficiaires,
    'conditions': conditions,
    'duration': duration,
    'cost': cost,
    'documents': documents.map((d) => d.toJson()).toList(),
    'steps': steps.map((s) => s.toJson()).toList(),
    'organisme': organisme?.toJson(),
    'resultat': resultat,
    'sourceUrl': sourceUrl,
    'updatedAt': updatedAt,
  };

  /// Sépare le nom de l'organisme par " / " pour obtenir les lieux individuels.
  List<DemarcheOrganisme> get lieux {
    if (organisme == null) return [];
    final parts = organisme!.nom
        .split(' / ')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (parts.length <= 1) return [organisme!];
    return parts
        .map((nom) => DemarcheOrganisme(
              nom: nom,
              adresse: organisme!.adresse,
              contact: organisme!.contact,
              horaires: organisme!.horaires,
            ))
        .toList();
  }

  factory Demarche.fromJson(Map json) {
    DemarcheCategory cat;
    try {
      cat = DemarcheCategory.values.firstWhere((e) => e.name == json['category']);
    } catch (_) {
      cat = _mapCategoryFromLabel(json['category'] as String? ?? '');
    }

    DemarcheType type;
    try {
      type = DemarcheType.values.firstWhere((e) => e.name == json['type']);
    } catch (_) {
      type = DemarcheType.procedure;
    }

    return Demarche(
      id: json['id'] as String,
      sourceId: (json['sourceId'] as int?) ?? 0,
      title: json['title'] as String,
      category: cat,
      type: type,
      summary: (json['summary'] as String?) ?? '',
      beneficiaires: json['beneficiaires'] as String?,
      conditions: json['conditions'] as String?,
      duration: json['duration'] as String?,
      cost: json['cost'] as String?,
      documents: ((json['documents'] as List?) ?? [])
          .map((d) => DemarcheDocument.fromJson(d as Map))
          .toList(),
      steps: ((json['steps'] as List?) ?? [])
          .map((s) => DemarcheStep.fromJson(s as Map))
          .toList(),
      organisme: json['organisme'] != null
          ? DemarcheOrganisme.fromJson(json['organisme'] as Map)
          : null,
      resultat: json['resultat'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      updatedAt: (json['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }
}

// ── Suivi par étape ───────────────────────────────────────────────────────────

class UserDemarcheStepStatus {
  final int stepOrder;
  final bool isDone;
  final String? note;
  final String? agendaEventId;
  final String? completedAt;

  UserDemarcheStepStatus({
    required this.stepOrder,
    this.isDone = false,
    this.note,
    this.agendaEventId,
    this.completedAt,
  });

  UserDemarcheStepStatus copyWith({
    bool? isDone,
    String? note,
    String? agendaEventId,
    String? completedAt,
  }) => UserDemarcheStepStatus(
    stepOrder: stepOrder,
    isDone: isDone ?? this.isDone,
    note: note ?? this.note,
    agendaEventId: agendaEventId ?? this.agendaEventId,
    completedAt: completedAt ?? this.completedAt,
  );

  Map<String, dynamic> toJson() => {
    'stepOrder': stepOrder,
    'isDone': isDone,
    'note': note,
    'agendaEventId': agendaEventId,
    'completedAt': completedAt,
  };

  factory UserDemarcheStepStatus.fromJson(Map json) => UserDemarcheStepStatus(
    stepOrder: (json['stepOrder'] as int?) ?? 0,
    isDone: (json['isDone'] as bool?) ?? false,
    note: json['note'] as String?,
    agendaEventId: json['agendaEventId'] as String?,
    completedAt: json['completedAt'] as String?,
  );
}

class UserDemarche {
  final String id;
  final String demarcheId;
  final Demarche demarche;
  final DemarcheStatus status;
  final int currentStep;
  final List<UserDemarcheStepStatus> stepStatuses;
  final String? notes;
  final List<String> checkedDocuments;
  final String startedAt;
  final String updatedAt;

  UserDemarche({
    required this.id,
    required this.demarcheId,
    required this.demarche,
    required this.status,
    required this.currentStep,
    required this.stepStatuses,
    this.notes,
    this.checkedDocuments = const [],
    required this.startedAt,
    required this.updatedAt,
  });

  int get completedSteps => stepStatuses.where((s) => s.isDone).length;
  int get totalSteps => demarche.steps.length;
  double get progress => totalSteps > 0 ? completedSteps / totalSteps : 0.0;

  UserDemarcheStepStatus statusForStep(int order) {
    return stepStatuses.firstWhere(
      (s) => s.stepOrder == order,
      orElse: () => UserDemarcheStepStatus(stepOrder: order),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'demarcheId': demarcheId,
    'demarche': demarche.toJson(),
    'status': status.name,
    'currentStep': currentStep,
    'stepStatuses': stepStatuses.map((s) => s.toJson()).toList(),
    'notes': notes,
    'checkedDocuments': checkedDocuments,
    'startedAt': startedAt,
    'updatedAt': updatedAt,
  };

  factory UserDemarche.fromJson(Map json) {
    DemarcheStatus status;
    try {
      status = DemarcheStatus.values.firstWhere((e) => e.name == json['status']);
    } catch (_) {
      status = DemarcheStatus.enCours;
    }

    return UserDemarche(
      id: json['id'] as String,
      demarcheId: json['demarcheId'] as String,
      demarche: Demarche.fromJson(json['demarche'] as Map),
      status: status,
      currentStep: (json['currentStep'] as int?) ?? 1,
      stepStatuses: ((json['stepStatuses'] as List?) ?? [])
          .map((s) => UserDemarcheStepStatus.fromJson(s as Map))
          .toList(),
      notes: json['notes'] as String?,
      checkedDocuments: ((json['checkedDocuments'] as List?) ?? []).cast<String>(),
      startedAt: (json['startedAt'] as String?) ?? DateTime.now().toIso8601String(),
      updatedAt: (json['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }
}

// ── Adaptateurs Hive ─────────────────────────────────────────────────────────

class DemarcheAdapter extends TypeAdapter<Demarche> {
  @override final int typeId = 12;
  @override Demarche read(BinaryReader reader) => Demarche.fromJson(reader.readMap());
  @override void write(BinaryWriter writer, Demarche obj) => writer.writeMap(obj.toJson());
}

class UserDemarcheAdapter extends TypeAdapter<UserDemarche> {
  @override final int typeId = 13;
  @override UserDemarche read(BinaryReader reader) => UserDemarche.fromJson(reader.readMap());
  @override void write(BinaryWriter writer, UserDemarche obj) => writer.writeMap(obj.toJson());
}

// ── Service ───────────────────────────────────────────────────────────────────

class DemarchesService {
  static const String _catalogBoxName   = 'demarches_catalog';
  static const String _userBoxName      = 'user_demarches';
  static const String _settingsBoxName  = 'demarches_settings';
  static const String _catalogVersion   = '2025-v3';

  late Box<Demarche>     _catalogBox;
  late Box<UserDemarche> _userBox;
  late Box<dynamic>      _settingsBox;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(DemarcheAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(UserDemarcheAdapter());
    _catalogBox   = await Hive.openBox<Demarche>(_catalogBoxName);
    _userBox      = await Hive.openBox<UserDemarche>(_userBoxName);
    _settingsBox  = await Hive.openBox<dynamic>(_settingsBoxName);
    _initialized  = true;
    await _loadInitialCatalog();
  }

  Future<void> _loadInitialCatalog() async {
    final storedVersion = _settingsBox.get('catalog_version') as String?;
    if (storedVersion == _catalogVersion && _catalogBox.isNotEmpty) return;

    await _catalogBox.clear();
    try {
      final jsonStr = await rootBundle.loadString('assets/data/demarches_catalog.json');
      final list = json.decode(jsonStr) as List;
      for (final item in list) {
        final d = _fromEgouvJson(item as Map<String, dynamic>);
        await _catalogBox.put(d.id, d);
      }
      await _settingsBox.put('catalog_version', _catalogVersion);
    } catch (e) {
      // Si le JSON n'est pas chargeable, on garde le catalogue vide plutôt que de crasher
    }
  }

  // ── Parsing JSON egouv → Demarche ─────────────────────────────────────────

  static Demarche _fromEgouvJson(Map<String, dynamic> raw) {
    final category = _mapCategoryFromLabel(raw['category'] as String? ?? '');
    final type = raw['type'] == 'démarche' ? DemarcheType.procedure : DemarcheType.information;

    // Pièces justificatives (strings simples ou objets {cas, documents})
    final docs = <DemarcheDocument>[];
    final rawDocs = raw['pieces_justificatives'];
    if (rawDocs is List) {
      for (final doc in rawDocs) {
        if (doc is String && doc.isNotEmpty) {
          docs.add(DemarcheDocument(name: doc, isRequired: true));
        } else if (doc is Map) {
          final cas = doc['cas'] as String?;
          final subDocs = doc['documents'];
          if (subDocs is List) {
            for (final sub in subDocs) {
              if (sub is String && sub.isNotEmpty) {
                docs.add(DemarcheDocument(name: sub, isRequired: true, cas: cas));
              }
            }
          }
        }
      }
    }

    // Étapes
    final steps = <DemarcheStep>[];
    final rawSteps = raw['etapes'];
    if (rawSteps is List) {
      for (int i = 0; i < rawSteps.length; i++) {
        final desc = rawSteps[i] as String? ?? '';
        if (desc.isEmpty) continue;
        steps.add(DemarcheStep(
          order: i + 1,
          title: _extractStepTitle(desc),
          description: desc,
        ));
      }
    }

    // Organisme
    DemarcheOrganisme? organisme;
    final rawOrg = raw['organisme'];
    if (rawOrg is Map) {
      final nom = rawOrg['nom'] as String? ?? '';
      if (nom.isNotEmpty) organisme = DemarcheOrganisme.fromJson(rawOrg);
    }

    final id = raw['id'] as int? ?? 0;

    return Demarche(
      id: 'egouv_$id',
      sourceId: id,
      title: raw['title'] as String? ?? '',
      category: category,
      type: type,
      summary: raw['description'] as String? ?? '',
      beneficiaires: _nullIfEmpty(raw['beneficiaires'] as String?),
      conditions: _nullIfEmpty(raw['conditions'] as String?),
      duration: _nullIfEmpty(raw['delai'] as String?),
      cost: _nullIfEmpty(raw['cout'] as String?),
      documents: docs,
      steps: steps,
      organisme: organisme,
      resultat: _nullIfEmpty(raw['resultat'] as String?),
      sourceUrl: raw['url'] as String?,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  static String _extractStepTitle(String desc) {
    // Raccourcir : garde la première phrase significative (avant : → point → virgule)
    var title = desc
        .split(RegExp(r'[→:;]'))[0]
        .split('.')[0]
        .trim();
    if (title.length > 60) title = '${title.substring(0, 57)}…';
    return title.isEmpty ? desc.substring(0, desc.length.clamp(0, 60)) : title;
  }

  static String? _nullIfEmpty(String? s) {
    if (s == null || s.trim().isEmpty || s.trim() == 'Non spécifié.' || s.trim() == 'null') return null;
    return s;
  }

  // ── Catalogue ─────────────────────────────────────────────────────────────

  Future<List<Demarche>> getCatalog({DemarcheCategory? category, String? query, DemarcheType? type}) async {
    await _init();
    var list = _catalogBox.values.toList();
    if (category != null) list = list.where((d) => d.category == category).toList();
    if (type != null)     list = list.where((d) => d.type == type).toList();
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((d) =>
        d.title.toLowerCase().contains(q) ||
        d.summary.toLowerCase().contains(q) ||
        (d.beneficiaires?.toLowerCase().contains(q) ?? false) ||
        (d.organisme?.nom.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    list.sort((a, b) => a.category.index.compareTo(b.category.index));
    return list;
  }

  Future<Demarche> getDemarche(String id) async {
    await _init();
    final d = _catalogBox.get(id);
    if (d == null) throw Exception('Démarche introuvable : $id');
    return d;
  }

  // ── Mes Démarches ─────────────────────────────────────────────────────────

  Future<List<UserDemarche>> getUserDemarches() async {
    await _init();
    final list = _userBox.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<UserDemarche> getUserDemarche(String id) async {
    await _init();
    final ud = _userBox.get(id);
    if (ud == null) throw Exception('Démarche utilisateur introuvable');
    return ud;
  }

  Future<UserDemarche> startDemarche(String demarcheId) async {
    await _init();
    // Vérifie si une démarche identique est déjà en cours
    final existing = _userBox.values.where(
      (ud) => ud.demarcheId == demarcheId && ud.status == DemarcheStatus.enCours,
    ).firstOrNull;
    if (existing != null) throw Exception('Cette démarche est déjà en cours.');

    final demarche = await getDemarche(demarcheId);
    final now = DateTime.now().toIso8601String();

    // Initialise les statuts d'étapes
    final stepStatuses = demarche.steps
        .map((s) => UserDemarcheStepStatus(stepOrder: s.order))
        .toList();

    final ud = UserDemarche(
      id: const Uuid().v4(),
      demarcheId: demarcheId,
      demarche: demarche,
      status: DemarcheStatus.enCours,
      currentStep: 1,
      stepStatuses: stepStatuses,
      startedAt: now,
      updatedAt: now,
    );
    await _userBox.put(ud.id, ud);

    MemoryService().recordAction(UserAction(
      type: 'demarche',
      objectId: ud.id,
      summary: 'Démarche "${demarche.title}" démarrée',
      timestamp: DateTime.now(),
      context: 'Action manuelle depuis l\'interface',
    ));
    await _rescheduleFollowUp(ud);
    return ud;
  }

  // ── Validation des étapes ─────────────────────────────────────────────────

  Future<UserDemarche> completeStep(String userDemarcheId, int stepOrder) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');

    final updatedStatuses = ud.stepStatuses.map((s) {
      if (s.stepOrder == stepOrder) {
        return s.copyWith(isDone: true, completedAt: DateTime.now().toIso8601String());
      }
      return s;
    }).toList();

    // Ajoute l'étape si elle n'existe pas encore
    if (!updatedStatuses.any((s) => s.stepOrder == stepOrder)) {
      updatedStatuses.add(UserDemarcheStepStatus(
        stepOrder: stepOrder,
        isDone: true,
        completedAt: DateTime.now().toIso8601String(),
      ));
    }

    final nextIncomplete = ud.demarche.steps
        .where((s) => !updatedStatuses.any((st) => st.stepOrder == s.order && st.isDone))
        .map((s) => s.order)
        .firstOrNull;

    final allDone = ud.demarche.steps.every(
      (s) => updatedStatuses.any((st) => st.stepOrder == s.order && st.isDone),
    );

    final updated = UserDemarche(
      id: ud.id,
      demarcheId: ud.demarcheId,
      demarche: ud.demarche,
      status: allDone ? DemarcheStatus.terminee : DemarcheStatus.enCours,
      currentStep: nextIncomplete ?? (ud.demarche.steps.length + 1),
      stepStatuses: updatedStatuses,
      notes: ud.notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<UserDemarche> uncompleteStep(String userDemarcheId, int stepOrder) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');

    final updatedStatuses = ud.stepStatuses.map((s) {
      if (s.stepOrder == stepOrder) return s.copyWith(isDone: false, completedAt: null);
      return s;
    }).toList();

    final firstIncomplete = ud.demarche.steps
        .where((s) => !updatedStatuses.any((st) => st.stepOrder == s.order && st.isDone))
        .map((s) => s.order)
        .firstOrNull ?? 1;

    final updated = UserDemarche(
      id: ud.id,
      demarcheId: ud.demarcheId,
      demarche: ud.demarche,
      status: DemarcheStatus.enCours,
      currentStep: firstIncomplete,
      stepStatuses: updatedStatuses,
      notes: ud.notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<UserDemarche> addStepNote(String userDemarcheId, int stepOrder, String note) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');

    List<UserDemarcheStepStatus> updatedStatuses = List.from(ud.stepStatuses);
    final idx = updatedStatuses.indexWhere((s) => s.stepOrder == stepOrder);
    if (idx >= 0) {
      updatedStatuses[idx] = updatedStatuses[idx].copyWith(note: note);
    } else {
      updatedStatuses.add(UserDemarcheStepStatus(stepOrder: stepOrder, note: note));
    }

    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: ud.status, currentStep: ud.currentStep,
      stepStatuses: updatedStatuses, notes: ud.notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<UserDemarche> setStepAgendaEvent(String userDemarcheId, int stepOrder, String eventId) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');

    List<UserDemarcheStepStatus> updatedStatuses = List.from(ud.stepStatuses);
    final idx = updatedStatuses.indexWhere((s) => s.stepOrder == stepOrder);
    if (idx >= 0) {
      updatedStatuses[idx] = updatedStatuses[idx].copyWith(agendaEventId: eventId);
    } else {
      updatedStatuses.add(UserDemarcheStepStatus(stepOrder: stepOrder, agendaEventId: eventId));
    }

    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: ud.status, currentStep: ud.currentStep,
      stepStatuses: updatedStatuses, notes: ud.notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<UserDemarche> updateGlobalNotes(String userDemarcheId, String notes) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');
    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: ud.status, currentStep: ud.currentStep,
      stepStatuses: ud.stepStatuses, notes: notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<UserDemarche> toggleDocumentCheck(String userDemarcheId, String docName) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');
    final checked = List<String>.from(ud.checkedDocuments);
    if (checked.contains(docName)) {
      checked.remove(docName);
    } else {
      checked.add(docName);
    }
    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: ud.status, currentStep: ud.currentStep,
      stepStatuses: ud.stepStatuses, notes: ud.notes,
      checkedDocuments: checked,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  // ── Rappel de suivi (intelligent, non intrusif) ───────────────────────────
  //
  // Un seul rappel par démarche, planifié à J+3 à 18 h. Chaque progression le
  // repousse de 3 jours : un utilisateur actif ne le voit donc jamais. Il est
  // annulé dès que la démarche est terminée ou supprimée, et n'est jamais
  // programmé si les notifications de démarches sont désactivées.

  static const _followUpDelay = Duration(days: 3);
  static const _followUpHour = 18;

  String _followUpId(String userDemarcheId) => 'demarche_followup_$userDemarcheId';

  /// Reflète les démarches en cours sur le widget d'écran d'accueil.
  Future<void> _syncWidget() async {
    final enCours = _userBox.values
        .where((ud) => ud.status == DemarcheStatus.enCours)
        .map((ud) => <String, dynamic>{
              'title': ud.demarche.title,
              'step': ud.completedSteps,
              'total': ud.totalSteps,
            })
        .toList();
    await WidgetBridge.pushDemarches(enCours);
  }

  Future<void> _rescheduleFollowUp(UserDemarche ud) async {
    await _syncWidget();
    final id = _followUpId(ud.id);
    await notificationService.cancelReminder(id);
    if (ud.status != DemarcheStatus.enCours) return;
    if (!settingsService.notifMaster || !settingsService.notifDemarches) return;

    final step = ud.demarche.steps
        .where((s) => s.order == ud.currentStep)
        .firstOrNull;
    final stepLabel = step != null
        ? 'étape ${ud.currentStep}/${ud.totalSteps} : ${step.title}'
        : 'étape ${ud.currentStep}/${ud.totalSteps}';

    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, _followUpHour)
        .add(_followUpDelay);

    await notificationService.scheduleReminder(
      id: id,
      title: ud.demarche.title,
      body: 'Votre démarche vous attend — $stepLabel.',
      scheduledAt: at,
    );
  }

  /// Annule tous les rappels de suivi (appelé quand l'utilisateur désactive
  /// les notifications de démarches dans les réglages).
  Future<void> cancelAllFollowUps() async {
    await _init();
    for (final ud in _userBox.values) {
      await notificationService.cancelReminder(_followUpId(ud.id));
    }
  }

  /// Reprogramme les rappels des démarches en cours (réactivation des
  /// notifications dans les réglages).
  Future<void> rescheduleAllFollowUps() async {
    await _init();
    for (final ud in _userBox.values) {
      await _rescheduleFollowUp(ud);
    }
  }

  Future<void> deleteDemarche(String userDemarcheId) async {
    await _init();
    await notificationService.cancelReminder(_followUpId(userDemarcheId));
    await _userBox.delete(userDemarcheId);
    await _syncWidget();
  }

  // Compatibilité ascendante avec l'ancienne API
  Future<UserDemarche> advanceStep(String userDemarcheId) async =>
      completeStep(userDemarcheId, (await getUserDemarche(userDemarcheId)).currentStep);

  Future<UserDemarche> updateStatus(String userDemarcheId, DemarcheStatus status) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('Démarche introuvable');
    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: status, currentStep: ud.currentStep,
      stepStatuses: ud.stepStatuses, notes: ud.notes,
      checkedDocuments: ud.checkedDocuments,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    await _rescheduleFollowUp(updated);
    return updated;
  }

  Future<void> init() async => _init();

  // ── Résumé pour Amiin ─────────────────────────────────────────────────────

  Future<String> getCatalogSummaryForAmiin() async {
    await _init();
    final buf = StringBuffer('Catalogue des démarches administratives de Djibouti :\n\n');
    final byCategory = <DemarcheCategory, List<Demarche>>{};
    for (final d in _catalogBox.values) {
      byCategory.putIfAbsent(d.category, () => []).add(d);
    }
    for (final cat in DemarcheCategory.values) {
      final items = byCategory[cat];
      if (items == null || items.isEmpty) continue;
      buf.writeln('## ${cat.label}');
      for (final d in items) {
        final typeLabel = d.type == DemarcheType.procedure ? '📋' : 'ℹ️';
        buf.write('$typeLabel [${d.id}] ${d.title}');
        if (d.duration != null) buf.write(' — délai : ${d.duration}');
        if (d.cost != null) buf.write(' — coût : ${d.cost}');
        buf.writeln();
      }
      buf.writeln();
    }
    return buf.toString();
  }

  Future<String> getDemarcheDetailForAmiin(String id) async {
    try {
      final d = await getDemarche(id);
      final buf = StringBuffer()
        ..writeln('# ${d.title}')
        ..writeln('Catégorie : ${d.category.label}')
        ..writeln("Type : ${d.type == DemarcheType.procedure ? 'Démarche (procédure)' : "Fiche d'information"}");
      if (d.beneficiaires != null) buf.writeln('Bénéficiaires : ${d.beneficiaires}');
      buf.writeln('\n## Description\n${d.summary}');
      if (d.conditions != null) buf.writeln('\n## Conditions\n${d.conditions}');
      if (d.documents.isNotEmpty) {
        buf.writeln('\n## Pièces justificatives');
        for (final doc in d.documents) {
          if (doc.cas != null) buf.write('  [${doc.cas}] ');
          buf.writeln('- ${doc.name}');
        }
      }
      if (d.steps.isNotEmpty) {
        buf.writeln('\n## Étapes');
        for (final s in d.steps) { buf.writeln('${s.order}. ${s.description}'); }
      }
      if (d.duration != null) buf.writeln('\n## Délai\n${d.duration}');
      if (d.cost != null) buf.writeln('\n## Coût\n${d.cost}');
      if (d.organisme != null) {
        buf.writeln('\n## Organisme compétent\n${d.organisme!.nom}');
        if (d.organisme!.adresse != null) buf.writeln('Adresse : ${d.organisme!.adresse}');
        if (d.organisme!.horaires != null) buf.writeln('Horaires : ${d.organisme!.horaires}');
        if (d.organisme!.contact != null && d.organisme!.contact!.isNotEmpty) {
          buf.writeln('Contact : ${d.organisme!.contact}');
        }
      }
      if (d.resultat != null) buf.writeln('\n## Résultat attendu\n${d.resultat}');
      if (d.sourceUrl != null) buf.writeln('\nSource : ${d.sourceUrl}');
      return buf.toString();
    } catch (_) {
      return 'Démarche introuvable : $id';
    }
  }
}

final demarchesService = DemarchesService();

// ── Helpers internes ──────────────────────────────────────────────────────────

DemarcheCategory _mapCategoryFromLabel(String label) {
  final l = label.toLowerCase().trim();
  if (l.contains('identit') || l.contains('famille')) return DemarcheCategory.identiteFamille;
  if (l.contains('sant') || l.contains('social'))    return DemarcheCategory.santeSocial;
  if (l.contains('duca'))                             return DemarcheCategory.education;
  if (l.contains('habitat') || l.contains('logement')) return DemarcheCategory.habitatLogement;
  if (l.contains('transport'))                        return DemarcheCategory.transport;
  if (l.contains('justice'))                          return DemarcheCategory.justice;
  if (l.contains('conomie') || l.contains('finance')) return DemarcheCategory.economieFinance;
  if (l.contains('tranger'))                          return DemarcheCategory.etrangers;
  if (l.contains('loisir') || l.contains('culture'))  return DemarcheCategory.loisirsCultures;
  if (l.contains('nergie') || l.contains('eau'))      return DemarcheCategory.energieEau;
  if (l.contains('curit'))                            return DemarcheCategory.securite;
  return DemarcheCategory.identiteFamille;
}
