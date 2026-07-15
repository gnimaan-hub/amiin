package com.example.amiin_app_flutter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Typeface
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Widget « Aujourd'hui » v3 — compact 4×2 :
 *   fixe    : température héros + chip prochaine prière
 *   rotatif : ViewFlipper 5 s — RDV ⇄ démarches ⇄ taux €/$ (chaque page
 *             est tappable vers l'écran correspondant de l'app)
 *   fixe    : barre « Poser une question » + micro → chat (vocal pour le micro)
 *
 * Aucun appel réseau ici : les données sont écrites par l'app (widget_bridge)
 * ou par la tâche WorkManager horaire. Le provider recalcule à chaque
 * rafraîchissement (~30 min) ce qui dépend de l'heure : prochaine prière et
 * RDV pertinent — un RDV passé disparaît donc tout seul.
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

            // ── Zone fixe : météo héros + prière ──
            views.setTextViewText(
                R.id.widget_weather_value, data.getString("widget_weather_value", "—"))
            views.setTextViewText(
                R.id.widget_weather_label, data.getString("widget_weather_label", "Météo"))

            val (prayerName, prayerTime) = nextPrayer(data)
            views.setTextViewText(R.id.widget_prayer_chip, "🕌 $prayerName · $prayerTime")

            // ── Zone rotative ──
            views.setTextViewText(R.id.widget_event_line, eventLine(context, data))
            views.setTextViewText(R.id.widget_demarche_line, demarcheLine(context, data))
            views.setTextViewText(
                R.id.widget_fx_line,
                data.getString("widget_fx_line", "💱  Taux du jour indisponible"))

            // ── Taps ──
            fun launch(uri: String) = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse(uri))

            views.setOnClickPendingIntent(R.id.widget_root, launch("amiin://home"))
            views.setOnClickPendingIntent(R.id.widget_event_line, launch("amiin://agenda"))
            views.setOnClickPendingIntent(R.id.widget_demarche_line, launch("amiin://demarches"))
            views.setOnClickPendingIntent(R.id.widget_fx_line, launch("amiin://home"))
            views.setOnClickPendingIntent(R.id.widget_ask_pill, launch("amiin://chat"))
            views.setOnClickPendingIntent(R.id.widget_mic_button, launch("amiin://chat?voice=1"))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** "prefix" normal + "strong" coloré et gras + "rest" normal. */
    private fun accentLine(
        prefix: String, strong: String, rest: String, color: Int,
    ): CharSequence {
        val sb = SpannableStringBuilder(prefix)
        val start = sb.length
        sb.append(strong)
        sb.setSpan(ForegroundColorSpan(color), start, sb.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.append(rest)
        return sb
    }

    // ── Prochaine prière (calculée à l'affichage) ─────────────────────────────

    private fun nextPrayer(data: SharedPreferences): Pair<String, String> {
        val raw = data.getString("widget_prayers_json", "") ?: ""
        if (raw.isEmpty()) return Pair("Prière", "—")
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
                if (minutes > nowMinutes) return Pair(label, time)
            }
            // Après l'Isha → Fajr (du lendemain)
            Pair("Fajr", json.optString("fajr", "—"))
        } catch (e: Exception) {
            Pair("Prière", "—")
        }
    }

    // ── Rendez-vous : celui du jour à venir, sinon le prochain de la semaine ──

    private fun eventLine(context: Context, data: SharedPreferences): CharSequence {
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
            accentLine("📅  ", prefix,
                " · $bestTitle", ContextCompat.getColor(context, R.color.widget_secretariat))
        } catch (e: Exception) {
            "📅  Aucun rendez-vous à venir"
        }
    }

    // ── Démarches en cours ────────────────────────────────────────────────────

    private fun demarcheLine(context: Context, data: SharedPreferences): CharSequence {
        val raw = data.getString("widget_demarches_json", "") ?: ""
        if (raw.isEmpty()) return "📋  Aucune démarche en cours"
        return try {
            val list = JSONArray(raw)
            if (list.length() == 0) return "📋  Aucune démarche en cours"
            val first = list.getJSONObject(0)
            val title = first.optString("title", "")
            val step = first.optInt("step", 0)
            val total = first.optInt("total", 0)
            val ocre = ContextCompat.getColor(context, R.color.widget_accent)
            val strong = if (total > 0) "$step/$total" else "en cours"
            val prefix = if (list.length() > 1) "📋  ${list.length()} en cours · " else "📋  "
            accentLine(prefix, strong, "  $title", ocre)
        } catch (e: Exception) {
            "📋  Aucune démarche en cours"
        }
    }
}
