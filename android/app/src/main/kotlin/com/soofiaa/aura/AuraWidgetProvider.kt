package com.soofiaa.aura

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Widget de la pantalla de inicio. No calcula nada: la app le deja el
// texto de cada dia (home_widget_sync.dart) y aca se elige el de hoy.
class AuraWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = buildViews(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        private const val PREFS = "aura_widget"
        private const val KEY = "payload"

        // Lo llama MainActivity con lo que manda la app.
        fun save(context: Context, payload: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, payload).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, AuraWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val views = buildViews(context)
                for (id in ids) manager.updateAppWidget(id, views)
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            var title = "Aura"
            var text = ""
            try {
                val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(KEY, null)
                if (raw != null) {
                    val json = JSONObject(raw)
                    val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                    val pair = json.getJSONObject("days").optJSONArray(today)
                        ?: json.getJSONArray("fallback")
                    title = pair.getString(0)
                    text = pair.getString(1)
                }
            } catch (e: Exception) {
                // Datos ilegibles: solo "Aura".
            }
            val views = RemoteViews(context.packageName, R.layout.aura_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_text, text)
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            return views
        }
    }
}
