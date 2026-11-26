// ─── UsageService — quota d'utilisation du jour ──────────────────────────────
// Reflète GET /v1/me/usage : part de l'enveloppe gratuite consommée (chat et
// voix confondus), remise à zéro à minuit heure de Djibouti. Quand elle est
// épuisée, le chat n'envoie plus rien (le serveur répondrait 402) jusqu'à la
// remise à zéro, où l'état se rafraîchit tout seul.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'user_scope.dart';

class UsageService extends ChangeNotifier {
  UsageService._() {
    userScope.addListener(_onAccountChanged);
  }

  double _percent = 0;
  bool _exhausted = false;
  bool _unlimited = false;
  DateTime? _resetsAt;
  Timer? _resetTimer;

  /// Part de l'enveloppe du jour consommée (0–100).
  double get percent => _percent;
  bool get exhausted => _exhausted;
  /// Compte sans limite (administrateur, ou quota non appliqué côté serveur).
  bool get unlimited => _unlimited;
  /// Prochaine remise à zéro (heure locale du téléphone).
  DateTime? get resetsAt => _resetsAt;

  Future<void> refresh() async {
    try {
      final resp = await api.get<Map<String, dynamic>>('/me/usage');
      final d = resp.data ?? const {};
      _percent = (d['percent'] as num?)?.toDouble() ?? 0;
      _exhausted = d['exhausted'] == true;
      _unlimited = d['unlimited'] == true;
      _resetsAt = DateTime.tryParse(d['resets_at'] as String? ?? '')?.toLocal();
      _scheduleResetRefresh();
      notifyListeners();
    } catch (e) {
      // Hors ligne / serveur endormi : on garde le dernier état connu.
      debugPrint('Usage indisponible : $e');
    }
  }

  /// Le serveur vient de refuser une requête (402) : on bloque sans attendre.
  void markExhausted() {
    if (_exhausted) return;
    _exhausted = true;
    _percent = 100;
    notifyListeners();
    unawaited(refresh());
  }

  void _scheduleResetRefresh() {
    _resetTimer?.cancel();
    final at = _resetsAt;
    if (at == null) return;
    final delay = at.difference(DateTime.now()) + const Duration(seconds: 5);
    if (delay.isNegative || delay > const Duration(days: 1, hours: 1)) return;
    _resetTimer = Timer(delay, () => unawaited(refresh()));
  }

  void _onAccountChanged() {
    _percent = 0;
    _exhausted = false;
    _unlimited = false;
    _resetsAt = null;
    _resetTimer?.cancel();
    notifyListeners();
    if (!userScope.isGuest) unawaited(refresh());
  }
}

final usageService = UsageService._();
