package app.fractus.fractus_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Un bouton du widget → `backgroundCallback` côté Dart, sans ouvrir l'appli. */
private fun action(context: Context, uri: String): PendingIntent =
    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri))

private fun bindButtons(context: Context, views: RemoteViews) {
    views.setOnClickPendingIntent(R.id.btn_lock, action(context, "fractus://action?name=lock"))
    views.setOnClickPendingIntent(R.id.btn_sleep, action(context, "fractus://action?name=sleep"))
    views.setOnClickPendingIntent(R.id.btn_mute, action(context, "fractus://action?name=mute"))
    views.setOnClickPendingIntent(R.id.btn_play, action(context, "fractus://action?name=play_pause"))
    views.setOnClickPendingIntent(R.id.btn_refresh, action(context, "fractus://refresh"))
}

private fun bindStatus(views: RemoteViews, data: SharedPreferences) {
    val online = data.getString("online", "0") == "1"
    views.setTextViewText(R.id.txt_state, data.getString("state_label", "Fractus") ?: "Fractus")
    views.setTextColor(R.id.txt_state, if (online) 0xFFF5F6F8.toInt() else 0xFF9398A1.toInt())
    views.setImageViewResource(R.id.dot, if (online) R.drawable.dot_on else R.drawable.dot_off)
    views.setTextViewText(R.id.txt_updated, data.getString("updated", "") ?: "")
}

/** Petit : une ligne d'état + les boutons. */
class FractusWidgetSmall : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_small).apply {
                setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
                bindStatus(this, widgetData)
                bindButtons(context, this)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** Grand : état, demande en attente (Autoriser / Refuser), dernière réponse, boutons. */
class FractusWidgetLarge : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_large).apply {
                setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
                bindStatus(this, widgetData)
                bindButtons(context, this)

                val pending = widgetData.getString("pending", "") ?: ""
                if (pending.isNotEmpty()) {
                    setViewVisibility(R.id.pending_box, View.VISIBLE)
                    setTextViewText(R.id.txt_pending, pending)
                    setOnClickPendingIntent(R.id.btn_allow, action(context, "fractus://decide?d=allow"))
                    setOnClickPendingIntent(R.id.btn_deny, action(context, "fractus://decide?d=deny"))
                } else {
                    setViewVisibility(R.id.pending_box, View.GONE)
                }

                val last = widgetData.getString("last_message", "") ?: ""
                setTextViewText(R.id.txt_last, if (last.isEmpty()) "Touche pour parler à Fractus." else last)
                setOnClickPendingIntent(
                    R.id.txt_last,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("fractus://chat")),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
