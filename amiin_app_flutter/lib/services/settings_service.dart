// ─── SettingsService ─────────────────────────────────────────────────────────
// Persistance de toutes les préférences utilisateur via une Hive box.
// Est un ChangeNotifier : les widgets qui en dépendent se reconstruisent
// automatiquement à chaque changement de préférence.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'hive_utils.dart';

class SettingsService extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _accountBoxBase = 'settings_account';

  /// Préférences propres au COMPTE (profil, comportement d'Amiin, langue des
  /// réponses, devise…) : stockées dans une box par compte (voir
  /// user_scope.dart). Toutes les autres clés sont des préférences de
  /// l'appareil (thème, texte, voix, notifications…), communes aux comptes.
  static const accountKeys = {
    'tone', 'response_length', 'expertise_level', 'memory_enabled',
    'proactive_suggestions', 'daily_digest', 'favorite_topics',
    'default_voice_mode', 'ai_language', 'currency', 'show_sources',
    'profile_firstname', 'profile_lastname', 'profile_birth_year',
    'profile_profession', 'profile_phone', 'profile_employment',
    'profile_native_language',
  };

  // Nullable : l'app démarre (et affiche le splash) AVANT l'ouverture des
  // boxes. Tant qu'elles ne sont pas ouvertes, les getters renvoient les
  // valeurs par défaut ; init()/openAccount() notifient ensuite.
  Box<dynamic>? _box;
  Box<dynamic>? _accountBox;

  Future<void> init() async {
    _box = await openBoxSafe<dynamic>(_boxName);
    notifyListeners();
  }

  /// Ouvre les préférences du compte [scopeKey] (appelé par UserScope).
  Future<void> openAccount(String scopeKey) async {
    final name = '${_accountBoxBase}_$scopeKey';
    if (_accountBox != null && _accountBox!.isOpen && _accountBox!.name == name) return;
    final old = _accountBox;
    _accountBox = null;
    if (old != null && old.isOpen) await old.close();
    _accountBox = await openBoxSafe<dynamic>(name);
    notifyListeners();
  }

  /// Migration : déplace les préférences de compte de l'ancienne box commune
  /// vers celle du compte [scopeKey] (ou les efface si null).
  Future<void> moveLegacyAccountSettings(String? scopeKey) async {
    final device = _box ?? await openBoxSafe<dynamic>(_boxName);
    final legacy = {
      for (final k in accountKeys)
        if (device.containsKey(k)) k: device.get(k),
    };
    if (legacy.isEmpty) return;
    if (scopeKey != null) {
      final target = await openBoxSafe<dynamic>('${_accountBoxBase}_$scopeKey');
      await target.putAll(legacy);
      if (!identical(target, _accountBox)) await target.close();
    }
    await device.deleteAll(legacy.keys);
  }

  /// Efface les préférences de l'appareil et celles du compte actif.
  Future<void> clearAll() async {
    await _box?.clear();
    await _accountBox?.clear();
    notifyListeners();
  }

  // ── Helpers internes ──────────────────────────────────────────────────────

  Box<dynamic>? _boxFor(String key) => accountKeys.contains(key) ? _accountBox : _box;

  T _get<T>(String key, T defaultValue) =>
      (_boxFor(key)?.get(key, defaultValue: defaultValue) as T?) ?? defaultValue;

  void _set<T>(String key, T value) {
    _boxFor(key)?.put(key, value);
    notifyListeners();
  }

  // ── Comportement Amiin ────────────────────────────────────────────────────

  /// 'formal' | 'neutral' | 'casual'
  String get tone => _get('tone', 'neutral');
  set tone(String v) => _set('tone', v);

  /// 'concise' | 'balanced' | 'detailed'
  String get responseLength => _get('response_length', 'balanced');
  set responseLength(String v) => _set('response_length', v);

  /// 'simplified' | 'standard' | 'expert'
  String get expertiseLevel => _get('expertise_level', 'standard');
  set expertiseLevel(String v) => _set('expertise_level', v);

  bool get memoryEnabled => _get('memory_enabled', true);
  set memoryEnabled(bool v) => _set('memory_enabled', v);

  double get ttsSpeed => ((_boxFor('tts_speed')?.get('tts_speed', defaultValue: 1.0) ?? 1.0) as num).toDouble();
  set ttsSpeed(double v) => _set('tts_speed', v);

  /// Active la synthèse vocale cloud (Edge TTS via backend) au lieu des voix système.
  bool get useCloudTts => _get('use_cloud_tts', false);
  set useCloudTts(bool v) => _set('use_cloud_tts', v);

  /// ID de la voix Edge TTS sélectionnée (ex: 'fr-FR-DeniseNeural').
  String get ttsVoice => _get('tts_voice', 'fr-FR-DeniseNeural');
  set ttsVoice(String v) => _set('tts_voice', v);

  /// Voix effectivement utilisée pour la synthèse : force une voix somali
  /// quand la langue de réponse est le somali (les voix fr/en ne prononcent
  /// pas correctement le somali), sauf si l'utilisateur a déjà choisi une
  /// voix so-*. Par défaut : Muuse (voix masculine). Même logique pour
  /// l'anglais (voix en-*, Jenny par défaut) et l'arabe (voix ar-*, Hamed
  /// par défaut) : bascule automatiquement dès que la langue de réponse
  /// correspond, sauf choix explicite d'une autre voix de la même langue.
  String get effectiveTtsVoice {
    final v = ttsVoice;
    if (aiLanguage == 'so' && !v.startsWith('so-')) return 'so-SO-MuuseNeural';
    if (aiLanguage == 'en' && !v.startsWith('en-')) return 'en-US-JennyNeural';
    if (aiLanguage == 'ar' && !v.startsWith('ar-')) return 'ar-SA-HamedNeural';
    return v;
  }

  bool get proactiveSuggestions => _get('proactive_suggestions', true);
  set proactiveSuggestions(bool v) => _set('proactive_suggestions', v);

  bool get dailyDigest => _get('daily_digest', false);
  set dailyDigest(bool v) => _set('daily_digest', v);

  /// Thématiques prioritaires pour Amiin (liste libre)
  List<String> get favoriteTopics {
    final raw = _boxFor('favorite_topics')?.get('favorite_topics');
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }
  set favoriteTopics(List<String> v) {
    _boxFor('favorite_topics')?.put('favorite_topics', v);
    notifyListeners();
  }

  /// 'none' | 'tts' | 'voice'
  String get defaultVoiceMode => _get('default_voice_mode', 'none');
  set defaultVoiceMode(String v) => _set('default_voice_mode', v);

  // ── Apparence ─────────────────────────────────────────────────────────────

  /// 'terre' | 'nuit' | 'lacte' (les anciens 'ocean' et 'foret' sont
  /// ramenés à 'terre' et 'nuit' par AmiinThemeVariantExt.fromId)
  String get themeVariant => _get('theme_variant', 'terre');
  set themeVariant(String v) => _set('theme_variant', v);

  double get textScale => ((_boxFor('text_scale')?.get('text_scale', defaultValue: 1.0) ?? 1.0) as num).toDouble();
  set textScale(double v) => _set('text_scale', v);

  /// 'dmsans' | 'opensans' | 'noto'
  String get font => _get('font', 'dmsans');
  set font(String v) => _set('font', v);

  /// 'full' | 'reduced' | 'off'
  String get animations => _get('animations', 'full');
  set animations(String v) => _set('animations', v);

  // ── Langue & Région ───────────────────────────────────────────────────────

  /// 'fr' | 'en'
  String get language => _get('language', 'fr');
  set language(String v) => _set('language', v);

  /// Langue dans laquelle Amiin répond — 'fr' | 'en' | 'ar' | 'so'
  String get aiLanguage => _get('ai_language', 'fr');
  set aiLanguage(String v) => _set('ai_language', v);

  /// 'DJF' | 'EUR' | 'USD'
  String get currency => _get('currency', 'DJF');
  set currency(String v) => _set('currency', v);

  /// 'dmy' | 'mdy'
  String get dateFormat => _get('date_format', 'dmy');
  set dateFormat(String v) => _set('date_format', v);

  /// '24h' | '12h'
  String get timeFormat => _get('time_format', '24h');
  set timeFormat(String v) => _set('time_format', v);

  // ── Notifications ─────────────────────────────────────────────────────────

  bool get notifMaster => _get('notif_master', true);
  set notifMaster(bool v) => _set('notif_master', v);

  bool get notifAgenda => _get('notif_agenda', true);
  set notifAgenda(bool v) => _set('notif_agenda', v);

  bool get notifDemarches => _get('notif_demarches', true);
  set notifDemarches(bool v) => _set('notif_demarches', v);

  bool get notifConseil => _get('notif_conseil', true);
  set notifConseil(bool v) => _set('notif_conseil', v);

  bool get notifRelance => _get('notif_relance', true);
  set notifRelance(bool v) => _set('notif_relance', v);

  bool get notifDigest => _get('notif_digest', false);
  set notifDigest(bool v) => _set('notif_digest', v);

  int get notifQuietStart => _get('notif_quiet_start', 22);
  set notifQuietStart(int v) => _set('notif_quiet_start', v);

  int get notifQuietEnd => _get('notif_quiet_end', 7);
  set notifQuietEnd(int v) => _set('notif_quiet_end', v);

  // ── Profil utilisateur ────────────────────────────────────────────────────

  String get profileFirstname => _get('profile_firstname', '');
  set profileFirstname(String v) => _set('profile_firstname', v);

  String get profileLastname => _get('profile_lastname', '');
  set profileLastname(String v) => _set('profile_lastname', v);

  int? get profileBirthYear {
    final v = _boxFor('profile_birth_year')?.get('profile_birth_year');
    return v == null ? null : (v as num).toInt();
  }
  set profileBirthYear(int? v) {
    _boxFor('profile_birth_year')?.put('profile_birth_year', v);
    notifyListeners();
  }

  String get profileProfession => _get('profile_profession', '');
  set profileProfession(String v) => _set('profile_profession', v);

  String get profilePhone => _get('profile_phone', '');
  set profilePhone(String v) => _set('profile_phone', v);

  /// 'employee' | 'freelance' | 'unemployed' | 'student'
  String get profileEmployment => _get('profile_employment', '');
  set profileEmployment(String v) => _set('profile_employment', v);

  String get profileNativeLanguage => _get('profile_native_language', '');
  set profileNativeLanguage(String v) => _set('profile_native_language', v);

  // ── Confidentialité ───────────────────────────────────────────────────────

  /// Afficher les sources dans les réponses d'Amiin
  bool get showSources => _get('show_sources', false);
  set showSources(bool v) => _set('show_sources', v);

  // ── Computed : affichage du nom ───────────────────────────────────────────

  String get displayName {
    final parts = [profileFirstname, profileLastname]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.join(' ');
  }

  String get initials {
    final f = profileFirstname.isNotEmpty ? profileFirstname[0].toUpperCase() : '';
    final l = profileLastname.isNotEmpty ? profileLastname[0].toUpperCase() : '';
    if (f.isEmpty && l.isEmpty) return 'A';
    return '$f$l';
  }

  // ── Payload API : injecté dans chaque requête /chat/stream ───────────────

  Map<String, dynamic> get userPreferencesPayload => {
    'tone': tone,
    'response_length': responseLength,
    'expertise_level': expertiseLevel,
    'ai_language': aiLanguage,
    'show_sources': showSources,
    'currency': currency,
  };

  // ── Profil transmis à Amiin (données brutes, formulées par le backend) ────
  // Longueurs bornées comme côté serveur (ClientProfile dans amiin_api.py).
  // La langue, les sources et la devise passent par userPreferencesPayload.

  static String _cap(String s, int max) => s.length <= max ? s : s.substring(0, max);

  Map<String, dynamic> get profileContextPayload {
    final year = profileBirthYear;
    return {
      'display_name': _cap(displayName, 60),
      if (year != null && year >= 1900 && year <= 2100) 'birth_year': year,
      'profession': _cap(profileProfession, 80),
      'employment': _cap(profileEmployment, 20),
      'native_language': _cap(profileNativeLanguage, 40),
      'phone': _cap(profilePhone, 30),
      'favorite_topics': [for (final t in favoriteTopics.take(10)) _cap(t, 40)],
    };
  }

}

/// Singleton global — initialisé dans main() avant runApp().
final settingsService = SettingsService();
