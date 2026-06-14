// ─── Démarches Service (local Hive) ─────────────────────────────────────────

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'memory_service.dart';
import '../models/user_action.dart';

enum DemarcheStatus { aFaire, enCours, terminee, expiree }
enum DemarcheCategory { identite, famille, logement, emploi, sante, education, transport, fiscal, autre }

class DemarcheDocument {
  final String name;
  final String? description;
  final bool isRequired;
  DemarcheDocument({required this.name, this.description, required this.isRequired});
  Map<String, dynamic> toJson() => {'name': name, 'description': description, 'isRequired': isRequired};
  factory DemarcheDocument.fromJson(Map<dynamic, dynamic> json) => DemarcheDocument(
    name: json['name'] as String,
    description: json['description'] as String?,
    isRequired: json['isRequired'] as bool,
  );
}

class DemarcheStep {
  final int order;
  final String title;
  final String description;
  final String? serviceId;
  DemarcheStep({required this.order, required this.title, required this.description, this.serviceId});
  Map<String, dynamic> toJson() => {'order': order, 'title': title, 'description': description, 'serviceId': serviceId};
  factory DemarcheStep.fromJson(Map<dynamic, dynamic> json) => DemarcheStep(
    order: json['order'] as int,
    title: json['title'] as String,
    description: json['description'] as String,
    serviceId: json['serviceId'] as String?,
  );
}

class Demarche {
  final String id;
  final String title;
  final DemarcheCategory category;
  final String summary;
  final String? duration;
  final String? cost;
  final List<DemarcheDocument> documents;
  final List<DemarcheStep> steps;
  final String? serviceId;
  final String updatedAt;

  Demarche({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    this.duration,
    this.cost,
    required this.documents,
    required this.steps,
    this.serviceId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'category': category.name, 'summary': summary,
    'duration': duration, 'cost': cost, 'documents': documents.map((d) => d.toJson()).toList(),
    'steps': steps.map((s) => s.toJson()).toList(), 'serviceId': serviceId, 'updatedAt': updatedAt,
  };

  factory Demarche.fromJson(Map<dynamic, dynamic> json) => Demarche(
    id: json['id'] as String,
    title: json['title'] as String,
    category: DemarcheCategory.values.firstWhere((e) => e.name == json['category']),
    summary: json['summary'] as String,
    duration: json['duration'] as String?,
    cost: json['cost'] as String?,
    documents: (json['documents'] as List).map((d) => DemarcheDocument.fromJson(d as Map<dynamic, dynamic>)).toList(),
    steps: (json['steps'] as List).map((s) => DemarcheStep.fromJson(s as Map<dynamic, dynamic>)).toList(),
    serviceId: json['serviceId'] as String?,
    updatedAt: json['updatedAt'] as String,
  );
}

class UserDemarche {
  final String id;
  final String demarcheId;
  final Demarche demarche;
  final DemarcheStatus status;
  final int currentStep;
  final String? notes;
  final String startedAt;
  final String updatedAt;

  UserDemarche({
    required this.id,
    required this.demarcheId,
    required this.demarche,
    required this.status,
    required this.currentStep,
    this.notes,
    required this.startedAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'demarcheId': demarcheId, 'demarche': demarche.toJson(),
    'status': status.name, 'currentStep': currentStep, 'notes': notes,
    'startedAt': startedAt, 'updatedAt': updatedAt,
  };

  factory UserDemarche.fromJson(Map<dynamic, dynamic> json) => UserDemarche(
    id: json['id'] as String,
    demarcheId: json['demarcheId'] as String,
    demarche: Demarche.fromJson(json['demarche'] as Map<dynamic, dynamic>),
    status: DemarcheStatus.values.firstWhere((e) => e.name == json['status']),
    currentStep: json['currentStep'] as int,
    notes: json['notes'] as String?,
    startedAt: json['startedAt'] as String,
    updatedAt: json['updatedAt'] as String,
  );
}

// Adaptateurs Hive
class DemarcheAdapter extends TypeAdapter<Demarche> {
  @override final int typeId = 12;
  @override Demarche read(BinaryReader reader) {
    final map = reader.readMap();
    return Demarche.fromJson(map);
  }
  @override void write(BinaryWriter writer, Demarche obj) => writer.writeMap(obj.toJson());
}

class UserDemarcheAdapter extends TypeAdapter<UserDemarche> {
  @override final int typeId = 13;
  @override UserDemarche read(BinaryReader reader) {
    final map = reader.readMap();
    return UserDemarche.fromJson(map);
  }
  @override void write(BinaryWriter writer, UserDemarche obj) => writer.writeMap(obj.toJson());
}
class DemarchesService {
  static const String _catalogBoxName = 'demarches_catalog';
  static const String _userBoxName = 'user_demarches';
  late Box<Demarche> _catalogBox;
  late Box<UserDemarche> _userBox;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(DemarcheAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(UserDemarcheAdapter());
    _catalogBox = await Hive.openBox<Demarche>(_catalogBoxName);
    _userBox = await Hive.openBox<UserDemarche>(_userBoxName);
    _initialized = true;
    await _loadInitialCatalog();
  }

  // Charge un catalogue par défaut (à remplacer par des vraies données)
  Future<void> _loadInitialCatalog() async {
    if (_catalogBox.isNotEmpty) return;
    // Ajouter quelques démarches exemple (tu pourras importer un JSON plus tard)
    final sample = Demarche(
      id: 'cni',
      title: 'Carte nationale d’identité',
      category: DemarcheCategory.identite,
      summary: 'Obtenir ou renouveler sa carte d’identité.',
      duration: '2 semaines',
      cost: '5 000 FDJ',
      documents: [
        DemarcheDocument(name: 'Extrait d’acte de naissance', isRequired: true),
        DemarcheDocument(name: 'Photo d’identité', isRequired: true),
      ],
      steps: [
        DemarcheStep(order: 1, title: 'Remplir le formulaire', description: 'Disponible en ligne ou au guichet.'),
        DemarcheStep(order: 2, title: 'Déposer le dossier', description: 'Au centre d’état civil.'),
      ],
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _catalogBox.put(sample.id, sample);
  }

  Future<List<Demarche>> getCatalog({DemarcheCategory? category, String? query}) async {
    await _init();
    var list = _catalogBox.values.toList();
    if (category != null) list = list.where((d) => d.category == category).toList();
    if (query != null && query.isNotEmpty) {
      list = list.where((d) => d.title.toLowerCase().contains(query.toLowerCase())).toList();
    }
    return list;
  }

  Future<Demarche> getDemarche(String id) async {
    await _init();
    final d = _catalogBox.get(id);
    if (d == null) throw Exception('Démarche not found');
    return d;
  }

  Future<List<UserDemarche>> getUserDemarches() async {
    await _init();
    return _userBox.values.toList();
  }

  Future<UserDemarche> startDemarche(String demarcheId) async {
    await _init();
    final demarche = await getDemarche(demarcheId);
    final now = DateTime.now().toIso8601String();
    final userDemarche = UserDemarche(
      id: const Uuid().v4(),
      demarcheId: demarcheId,
      demarche: demarche,
      status: DemarcheStatus.enCours,
      currentStep: 1,
      notes: null,
      startedAt: now,
      updatedAt: now,
    );
    await _userBox.put(userDemarche.id, userDemarche);

    MemoryService().recordAction(UserAction(
      type: 'demarche',
      objectId: userDemarche.id,
      summary: 'Démarche "${demarche.title}" démarrée',
      timestamp: DateTime.now(),
      context: 'Action manuelle depuis l\'interface',
    ));
    return userDemarche;
  }

  Future<UserDemarche> advanceStep(String userDemarcheId) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('UserDemarche not found');
    final newStep = ud.currentStep + 1;
    final status = newStep > ud.demarche.steps.length ? DemarcheStatus.terminee : DemarcheStatus.enCours;
    final updated = UserDemarche(
      id: ud.id,
      demarcheId: ud.demarcheId,
      demarche: ud.demarche,
      status: status,
      currentStep: newStep,
      notes: ud.notes,
      startedAt: ud.startedAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    return updated;
  }

  Future<UserDemarche> updateStatus(String userDemarcheId, DemarcheStatus status) async {
    await _init();
    final ud = _userBox.get(userDemarcheId);
    if (ud == null) throw Exception('UserDemarche not found');
    final updated = UserDemarche(
      id: ud.id, demarcheId: ud.demarcheId, demarche: ud.demarche,
      status: status, currentStep: ud.currentStep, notes: ud.notes,
      startedAt: ud.startedAt, updatedAt: DateTime.now().toIso8601String(),
    );
    await _userBox.put(ud.id, updated);
    return updated;
  }

  // Méthode publique d'initialisation
  Future<void> init() async => _init();
}

final demarchesService = DemarchesService();