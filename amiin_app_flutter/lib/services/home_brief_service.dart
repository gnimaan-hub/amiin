// ─── Brief du jour (météo, prières, taux FDJ) ────────────────────────────────
//
// Alimente la bande « Aujourd'hui » de l'écran d'accueil via GET /home/brief.
// Philosophie : jamais bloquant, jamais d'erreur visible. Le dernier brief
// reçu est conservé en cache Hive pour affichage immédiat (et hors-ligne) ;
// le rafraîchissement réseau se fait en arrière-plan, au plus une fois
// toutes les 30 minutes.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'api_client.dart';
import 'hive_utils.dart';

/// Nom du provider Android (doit correspondre à AmiinBriefWidgetProvider.kt
/// et à l'entrée `receiver` de AndroidManifest.xml).
const _kWidgetAndroidName = 'AmiinBriefWidgetProvider';

class HomeBriefWeather {
  final int temp;
  final int feelsLike;
  final String desc;
  final String icon;

  HomeBriefWeather({
    required this.temp,
    required this.feelsLike,
    required this.desc,
    required this.icon,
  });

  Map<String, dynamic> toJson() =>
      {'temp': temp, 'feels_like': feelsLike, 'desc': desc, 'icon': icon};

  static HomeBriefWeather? fromJson(Map? json) {
    if (json == null) return null;
    return HomeBriefWeather(
      temp: (json['temp'] as num?)?.round() ?? 0,
      feelsLike: (json['feels_like'] as num?)?.round() ?? 0,
      desc: (json['desc'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '',
    );
  }
}

class HomeBriefPrayers {
  final String fajr, dhuhr, asr, maghrib, isha;

  HomeBriefPrayers({
    required this.fajr,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  Map<String, dynamic> toJson() => {
        'fajr': fajr, 'dhuhr': dhuhr, 'asr': asr,
        'maghrib': maghrib, 'isha': isha,
      };

  static HomeBriefPrayers? fromJson(Map? json) {
    if (json == null) return null;
    return HomeBriefPrayers(
      fajr: (json['fajr'] as String?) ?? '',
      dhuhr: (json['dhuhr'] as String?) ?? '',
      asr: (json['asr'] as String?) ?? '',
      maghrib: (json['maghrib'] as String?) ?? '',
      isha: (json['isha'] as String?) ?? '',
    );
  }

  /// Prochaine prière par rapport à [now] : (nom, heure "HH:mm"),
  /// ou la Fajr du lendemain après l'Isha.
  (String, String) next(DateTime now) {
    final entries = [
      ('Fajr', fajr), ('Dhuhr', dhuhr), ('Asr', asr),
      ('Maghrib', maghrib), ('Isha', isha),
    ];
    final nowMinutes = now.hour * 60 + now.minute;
    for (final (name, time) in entries) {
      final parts = time.split(':');
      if (parts.length != 2) continue;
      final m = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      if (m > nowMinutes) return (name, time);
    }
    return ('Fajr', fajr);
  }
}

class HomeBriefFx {
  final double usdFdj;
  final double? eurFdj;

  HomeBriefFx({required this.usdFdj, this.eurFdj});

  Map<String, dynamic> toJson() => {'usd_fdj': usdFdj, 'eur_fdj': eurFdj};

  static HomeBriefFx? fromJson(Map? json) {
    if (json == null) return null;
    final usd = (json['usd_fdj'] as num?)?.toDouble();
    if (usd == null) return null;
    return HomeBriefFx(usdFdj: usd, eurFdj: (json['eur_fdj'] as num?)?.toDouble());
  }
}

class HomeBrief {
  final String date;
  final HomeBriefWeather? weather;
  final HomeBriefPrayers? prayers;
  final HomeBriefFx? fx;

  HomeBrief({required this.date, this.weather, this.prayers, this.fx});

  bool get isEmpty => weather == null && prayers == null && fx == null;

  Map<String, dynamic> toJson() => {
        'date': date,
        'weather': weather?.toJson(),
        'prayers': prayers?.toJson(),
        'fx': fx?.toJson(),
      };

  static HomeBrief? fromJson(Map? json) {
    if (json == null) return null;
    return HomeBrief(
      date: (json['date'] as String?) ?? '',
      weather: HomeBriefWeather.fromJson(json['weather'] as Map?),
      prayers: HomeBriefPrayers.fromJson(json['prayers'] as Map?),
      fx: HomeBriefFx.fromJson(json['fx'] as Map?),
    );
  }
}

class HomeBriefService {
  static final HomeBriefService _instance = HomeBriefService._internal();
  factory HomeBriefService() => _instance;
  HomeBriefService._internal();

  static const _boxName = 'home_brief';
  static const _refreshInterval = Duration(minutes: 30);

  Box? _box;
  DateTime? _lastFetch;
  bool _fetching = false;

  /// Dernier brief connu (cache ou réseau). Null tant que rien n'est arrivé —
  /// l'accueil masque alors simplement la bande.
  final ValueNotifier<HomeBrief?> brief = ValueNotifier(null);

  Future<void> _init() async {
    if (_box != null) return;
    _box = await openBoxSafe(_boxName);
    final cached = _box!.get('latest');
    if (cached is Map) {
      brief.value = HomeBrief.fromJson(cached);
      final ts = _box!.get('fetched_at');
      if (ts is String) _lastFetch = DateTime.tryParse(ts);
    }
  }

  /// Charge le cache puis rafraîchit depuis l'API si le dernier fetch date
  /// de plus de 30 minutes. Silencieux : toute erreur laisse le brief en l'état.
  Future<void> refresh({bool force = false}) async {
    await _init();
    if (_fetching) return;
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _refreshInterval) {
      return;
    }
    _fetching = true;
    try {
      final resp = await api.get('/home/brief');
      final fresh = HomeBrief.fromJson(resp.data as Map?);
      if (fresh != null && !fresh.isEmpty) {
        brief.value = fresh;
        _lastFetch = DateTime.now();
        await _box!.put('latest', fresh.toJson());
        await _box!.put('fetched_at', _lastFetch!.toIso8601String());
        unawaited(_pushToHomeScreenWidget(fresh));
      }
    } catch (e) {
      debugPrint('Brief du jour indisponible : $e');
    } finally {
      _fetching = false;
    }
  }

  /// Reflète le brief sur le widget d'écran d'accueil Android. Best-effort :
  /// une erreur ici (widget non ajouté, plateforme non supportée) ne doit
  /// jamais remonter à l'appelant ni affecter l'app elle-même.
  Future<void> _pushToHomeScreenWidget(HomeBrief b) async {
    try {
      final weather = b.weather;
      await HomeWidget.saveWidgetData<String>(
        'widget_weather_value', weather != null ? '${weather.temp}°' : '—');
      await HomeWidget.saveWidgetData<String>(
        'widget_weather_label', weather?.desc ?? 'Météo indisponible');

      final prayers = b.prayers;
      if (prayers != null) {
        final (name, time) = prayers.next(DateTime.now());
        await HomeWidget.saveWidgetData<String>('widget_prayer_value', time);
        await HomeWidget.saveWidgetData<String>('widget_prayer_label', name);
      } else {
        await HomeWidget.saveWidgetData<String>('widget_prayer_value', '—');
        await HomeWidget.saveWidgetData<String>('widget_prayer_label', 'Prière');
      }

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

      await HomeWidget.updateWidget(androidName: _kWidgetAndroidName);
    } catch (e) {
      debugPrint('Widget d\'écran d\'accueil non mis à jour : $e');
    }
  }
}

final homeBriefService = HomeBriefService();
