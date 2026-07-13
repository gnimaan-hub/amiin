// ─── Pont vers le widget d'écran d'accueil Android ──────────────────────────
//
// Centralise tout ce qui alimente le widget natif « Aujourd'hui » :
//   • pushBrief    — météo, horaires de prière (les 5, le natif calcule la
//                    prochaine), taux de change
//   • pushEvents   — rendez-vous des 7 prochains jours (le natif filtre par
//                    l'heure courante : RDV du jour, sinon prochain)
//   • pushDemarches— démarches en cours (titre + progression)
//
// Deux canaux de mise à jour :
//   1. L'app ouverte : chaque changement (brief rafraîchi, agenda modifié,
//      étape de démarche cochée) pousse immédiatement.
//   2. L'app fermée : une tâche WorkManager horaire re-télécharge le brief
//      (le token est rafraîchi par l'intercepteur habituel) et met le widget
//      à jour. Les RDV/démarches n'ont pas besoin de ce canal : ils ne
//      changent que par une action dans l'app.
//
// Gère aussi les taps du widget : la barre « Poser une question » et le
// micro ouvrent l'app directement sur le chat (écoute vocale déjà lancée
// pour le micro).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../navigation/app_router.dart';
import 'agenda_service.dart';
import 'api_client.dart';
import 'chat_controller.dart';
import 'home_brief_service.dart';

/// Doit correspondre au nom de classe Kotlin et au <receiver> du manifest.
const kWidgetAndroidName = 'AmiinBriefWidgetProvider';

const _kBackgroundTask = 'amiin_widget_refresh';

// ── Tâche de fond WorkManager ─────────────────────────────────────────────────
// Tourne dans un isolate séparé, app fermée. On ne touche PAS à Hive ici
// (accès multi-isolate dangereux) : on télécharge le brief et on écrit
// directement dans le stockage du widget, rien d'autre.

@pragma('vm:entry-point')
void widgetBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      ApiClient.init(); // intercepteur auth : token + refresh automatique
      final resp = await api.get('/home/brief');
      final brief = HomeBrief.fromJson(resp.data as Map?);
      if (brief != null && !brief.isEmpty) {
        await WidgetBridge.writeBriefData(brief);
        await HomeWidget.updateWidget(androidName: kWidgetAndroidName);
      }
      return true;
    } catch (e) {
      debugPrint('Rafraîchissement widget en fond échoué : $e');
      return true; // pas de retry agressif — la prochaine heure réessaiera
    }
  });
}

class WidgetBridge {
  WidgetBridge._();

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// À appeler une fois dans main() : enregistre la tâche de fond,
  /// branche l'agenda, pousse l'état initial et écoute les taps du widget.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await Workmanager().initialize(widgetBackgroundDispatcher);
      await Workmanager().registerPeriodicTask(
        _kBackgroundTask,
        _kBackgroundTask,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );

      // Agenda : re-pousse les RDV à chaque modification (création par l'IA
      // ou manuelle, suppression…), puis une fois au démarrage.
      agendaService.listenable.addListener(() => unawaited(pushEvents()));
      unawaited(pushEvents());

      _wireWidgetTaps();
    } catch (e) {
      debugPrint('Init widget bridge échouée : $e');
    }
  }

  // ── Taps sur le widget ──────────────────────────────────────────────────────

  static void _wireWidgetTaps() {
    // App déjà ouverte en arrière-plan → flux
    HomeWidget.widgetClicked.listen(_handleWidgetUri);
    // App lancée à froid par le tap → URI initiale
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
  }

  static Uri? _lastUri;
  static DateTime _lastUriAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    // Au lancement à froid, la même URI arrive deux fois (valeur initiale +
    // flux). Sans dédup : double navigation et double toggle du micro
    // (qui démarrerait puis s'arrêterait aussitôt).
    final now = DateTime.now();
    if (uri.toString() == _lastUri.toString() &&
        now.difference(_lastUriAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastUri = uri;
    _lastUriAt = now;

    final target = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    if (target != 'chat') return; // amiin://home → comportement par défaut

    // Lancement à froid : attendre que le premier frame soit rendu avant de
    // naviguer, sinon GoRouter n'est pas encore attaché.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appRouter.go('/chat');
      if (uri.queryParameters['voice'] == '1') {
        // Laisse le temps au ChatScreen de monter et d'attacher son listener.
        Future.delayed(const Duration(milliseconds: 400), () {
          chatListenRequest.value++;
        });
      }
    });
  }

  // ── Brief (météo / prières / taux) ──────────────────────────────────────────

  /// Écrit les données du brief dans le stockage du widget. Utilisé par
  /// l'app (via pushBrief) et par la tâche de fond.
  static Future<void> writeBriefData(HomeBrief b) async {
    final weather = b.weather;
    await HomeWidget.saveWidgetData<String>(
        'widget_weather_value', weather != null ? '${weather.temp}°' : '—');
    await HomeWidget.saveWidgetData<String>(
        'widget_weather_label', weather?.desc ?? 'Météo');

    // Les 5 horaires : le provider Kotlin calcule la prochaine à chaque
    // rafraîchissement d'affichage (elle reste donc juste toute la journée).
    await HomeWidget.saveWidgetData<String>(
        'widget_prayers_json',
        b.prayers != null ? jsonEncode(b.prayers!.toJson()) : '');

    final fx = b.fx;
    if (fx != null) {
      final eur = fx.eurFdj;
      await HomeWidget.saveWidgetData<String>('widget_fx_value',
          eur != null ? '${eur.round()} FDJ' : '${fx.usdFdj.round()} FDJ');
      await HomeWidget.saveWidgetData<String>(
          'widget_fx_label', eur != null ? '1 euro' : '1 dollar');
    } else {
      await HomeWidget.saveWidgetData<String>('widget_fx_value', '—');
      await HomeWidget.saveWidgetData<String>('widget_fx_label', 'Taux');
    }

    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    await HomeWidget.saveWidgetData<String>('widget_updated_at', '$hh:$mm');
  }

  /// Pousse le brief et rafraîchit le widget. Best-effort, jamais bloquant.
  static Future<void> pushBrief(HomeBrief b) async {
    if (!_supported) return;
    try {
      await writeBriefData(b);
      await HomeWidget.updateWidget(androidName: kWidgetAndroidName);
    } catch (e) {
      debugPrint('Widget non mis à jour (brief) : $e');
    }
  }

  // ── Rendez-vous ─────────────────────────────────────────────────────────────

  /// Pousse les RDV des 7 prochains jours. Le natif choisit quoi afficher
  /// (RDV du jour à venir, sinon prochain de la semaine) selon l'heure.
  static Future<void> pushEvents() async {
    if (!_supported) return;
    try {
      final now = DateTime.now();
      final events = await agendaService.getEvents(
        now.subtract(const Duration(hours: 1)).toIso8601String(),
        now.add(const Duration(days: 7)).toIso8601String(),
      );
      final payload = events
          .map((e) => {'title': e.title, 'start': e.startDate})
          .toList();
      await HomeWidget.saveWidgetData<String>(
          'widget_events_json', jsonEncode(payload));
      await HomeWidget.updateWidget(androidName: kWidgetAndroidName);
    } catch (e) {
      debugPrint('Widget non mis à jour (agenda) : $e');
    }
  }

  // ── Démarches ───────────────────────────────────────────────────────────────

  /// Pousse les démarches en cours (appelé par demarches_service après
  /// chaque mutation). Reçoit des maps simples pour éviter tout couplage.
  static Future<void> pushDemarches(
      List<Map<String, dynamic>> enCours) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(
          'widget_demarches_json', jsonEncode(enCours));
      await HomeWidget.updateWidget(androidName: kWidgetAndroidName);
    } catch (e) {
      debugPrint('Widget non mis à jour (démarches) : $e');
    }
  }
}
