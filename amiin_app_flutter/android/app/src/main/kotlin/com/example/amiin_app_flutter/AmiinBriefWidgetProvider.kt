package com.example.amiin_app_flutter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Widget « Aujourd'hui » v2 : météo, prochaine prière, taux de change,
 * rendez-vous du jour (ou prochain de la semaine), démarches en cours,
 * et raccourcis chat (texte / vocal).
 *
 * Aucun appel réseau ici : les données sont écrites par l'app (widget_bridge)
 * ou par la tâche WorkManager horaire. Le provider recalcule à chaque
 * rafraîchissement d'affichage (~30 min) ce qui dépend de l'heure courante :
 * la prochaine prière et le rendez-vous à montrer — ainsi un RDV passé
 * disparaît tout seul, même sans nouvelle donnée.
 */
class AmiinBriefWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.amiin_brief_widget)

            // ── Rangée 1 : météo / prière / taux ──
            views.setTextViewText(
                R.id.widget_weather_value, data.getString("widget_weather_value", "—"))
            views.setTextViewText(
                R.id.widget_weather_label, data.getString("widget_weather_label", "Météo"))

            val (prayerTime, prayerName) = nextPrayer(data)
            views.setTextViewText(R.id.widget_prayer_value, prayerTime)
            views.setTextViewText(R.id.widget_prayer_label, prayerName)

            views.setTextViewText(
                R.id.widget_fx_value, data.getString("widget_fx_value", "—"))
            views.setTextViewText(
                R.id.widget_fx_label, data.getString("widget_fx_label", "Taux"))

            views.setTextViewText(
                R.id.widget_updated_at, data.getString("widget_updated_at", ""))

            // ── Rangée 2 : rendez-vous ──
            views.setTextViewText(R.id.widget_event_line, eventLine(data))

            // ── Rangée 3 : démarches ──
            views.setTextViewText(R.id.widget_demarche_line, demarcheLine(data))

            // ── Taps ──
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("amiin://home")))
            views.setOnClickPendingIntent(
                R.id.widget_ask_pill,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("amiin://chat")))
            views.setOnClickPendingIntent(
                R.id.widget_mic_button,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("amiin://chat?voice=1")))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    // ── Prochaine prière (calculée à l'affichage) ─────────────────────────────

    private fun nextPrayer(data: SharedPreferences): Pair<String, String> {
        val raw = data.getString("widget_prayers_json", "") ?: ""
        if (raw.isEmpty()) return Pair("—", "Prière")
        return try {
            val json = JSONObject(raw)
            val order = listOf(
                "fajr" to "Fajr", "dhuhr" to "Dhuhr", "asr" to "Asr",
                "maghrib" to "Maghrib", "isha" to "Isha",
            )
            val cal = Calendar.getInstance()
            val nowMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
            for ((key, label) in order) {
                val time = json.optString(key, "")
                val parts = time.split(":")
                if (parts.size != 2) continue
                val minutes = (parts[0].toIntOrNull() ?: 0) * 60 + (parts[1].toIntOrNull() ?: 0)
                if (minutes > nowMinutes) return Pair(time, label)
            }
            // Après l'Isha → Fajr (du lendemain)
            Pair(json.optString("fajr", "—"), "Fajr")
        } catch (e: Exception) {
            Pair("—", "Prière")
        }
    }

    // ── Rendez-vous : celui du jour à venir, sinon le prochain de la semaine ──

    private fun eventLine(data: SharedPreferences): String {
        val raw = data.getString("widget_events_json", "") ?: ""
        if (raw.isEmpty()) return "📅  Aucun rendez-vous à venir"
        return try {
            val events = JSONArray(raw)
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.FRANCE)
            val now = Calendar.getInstance()

            var best: Calendar? = null
            var bestTitle = ""
            for (i in 0 until events.length()) {
                val ev = events.getJSONObject(i)
                val startRaw = ev.optString("start", "")
                if (startRaw.length < 16) continue
                val date = fmt.parse(startRaw.substring(0, 16)) ?: continue
                val cal = Calendar.getInstance().apply { time = date }
                if (cal.before(now)) continue
                if (best == null || cal.before(best)) {
                    best = cal
                    bestTitle = ev.optString("title", "")
                }
            }
            val chosen = best ?: return "📅  Aucun rendez-vous à venir"

            val hm = String.format(
                Locale.FRANCE, "%02d:%02d",
                chosen.get(Calendar.HOUR_OF_DAY), chosen.get(Calendar.MINUTE))
            val sameDay =
                chosen.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
                chosen.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
            val prefix = if (sameDay) {
                "Aujourd'hui $hm"
            } else {
                val days = arrayOf("dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam.")
                "${days[chosen.get(Calendar.DAY_OF_WEEK) - 1]} $hm"
            }
            "📅  $prefix · $bestTitle"
        } catch (e: Exception) {
            "📅  Aucun rendez-vous à venir"
        }
    }

    // ── Démarches en cours ────────────────────────────────────────────────────

    private fun demarcheLine(data: SharedPreferences): String {
        val raw = data.getString("widget_demarches_json", "") ?: ""
        if (raw.isEmpty()) return "📋  Aucune démarche en cours"
        return try {
            val list = JSONArray(raw)
            if (list.length() == 0) return "📋  Aucune démarche en cours"
            val first = list.getJSONObject(0)
            val title = first.optString("title", "")
            val step = first.optInt("step", 0)
            val total = first.optInt("total", 0)
            val progress = if (total > 0) " ($step/$total)" else ""
            if (list.length() == 1) {
                "📋  $title$progress"
            } else {
                "📋  ${list.length()} en cours · $title$progress"
            }
        } catch (e: Exception) {
            "📋  Aucune démarche en cours"
        }
    }
}
