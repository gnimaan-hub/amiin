package com.example.amiin_app_flutter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Widget d'écran d'accueil « Aujourd'hui » : météo, prochaine prière, taux de
 * change. Ne fait aucun appel réseau — il affiche simplement les valeurs que
 * home_brief_service.dart écrit via home_widget après chaque rafraîchissement
 * du brief dans l'app. Si aucune donnée n'a encore été écrite (première
 * installation, jamais ouvert l'app), il montre un état neutre "—".
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

            views.setTextViewText(
                R.id.widget_weather_value,
                data.getString("widget_weather_value", "—"),
            )
            views.setTextViewText(
                R.id.widget_weather_label,
                data.getString("widget_weather_label", "Météo"),
            )
            views.setTextViewText(
                R.id.widget_prayer_value,
                data.getString("widget_prayer_value", "—"),
            )
            views.setTextViewText(
                R.id.widget_prayer_label,
                data.getString("widget_prayer_label", "Prière"),
            )
            views.setTextViewText(
                R.id.widget_fx_value,
                data.getString("widget_fx_value", "—"),
            )
            views.setTextViewText(
                R.id.widget_fx_label,
                data.getString("widget_fx_label", "Taux"),
            )
            views.setTextViewText(
                R.id.widget_updated_at,
                data.getString("widget_updated_at", ""),
            )

            // Tap sur le widget → ouvre l'app (écran d'accueil, comme un tap normal)
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("amiin://home"),
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
    }
}
