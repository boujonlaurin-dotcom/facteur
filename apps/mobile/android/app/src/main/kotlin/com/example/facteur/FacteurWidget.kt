package com.example.facteur

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget rendering up to 5 digest articles in a scrollable
 * `ListView` bound to [FacteurWidgetService].
 *
 * Only header text + adapter wiring live here; row construction happens in
 * the service so the list survives system kills and is re-fed via
 * [AppWidgetManager.notifyAppWidgetViewDataChanged].
 */
class FacteurWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "FacteurWidget"
        const val ACTION_REFRESH = "com.example.facteur.action.REFRESH_WIDGET"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, FacteurWidget::class.java),
            )
            if (ids.isNotEmpty()) {
                Log.d(TAG, "ACTION_REFRESH ids=${ids.size}")
                onUpdate(context, mgr, ids)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.facteur_widget)
                val prefs = HomeWidgetPlugin.getData(context)
                val json = prefs?.getString("articles_json", null)
                Log.d(TAG, "onUpdate id=$appWidgetId json.len=${json?.length ?: -1}")

                renderHeader(views, prefs)
                bindArticleList(context, views, appWidgetId, json)
                wireClickIntents(context, views, appWidgetId)

                appWidgetManager.updateAppWidget(appWidgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(
                    appWidgetId,
                    R.id.articles_list,
                )
            } catch (t: Throwable) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId", t)
            }
        }
    }

    private fun renderHeader(views: RemoteViews, prefs: android.content.SharedPreferences?) {
        val streak = prefs?.getString("streak", "0")?.toIntOrNull() ?: 0
        views.setTextViewText(
            R.id.streak_text,
            if (streak > 0) "🔥 ${streak}j" else "",
        )

        val subtitle = when (prefs?.getString("digest_status", "none")) {
            "completed" -> "Essentiel du jour complété ✓"
            "in_progress" -> "Continue ton essentiel"
            else -> "L'Essentiel du jour"
        }
        views.setTextViewText(R.id.subtitle, subtitle)
    }

    private fun bindArticleList(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        json: String?,
    ) {
        // Adapter intent — unique URI per appWidgetId so the system keeps
        // a separate factory instance per widget on the home screen.
        val adapterIntent = Intent(context, FacteurWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.articles_list, adapterIntent)
        views.setEmptyView(R.id.articles_list, R.id.empty_view)

        val isEmpty = json.isNullOrBlank() || json == "[]"
        views.setViewVisibility(
            R.id.empty_view,
            if (isEmpty) View.VISIBLE else View.GONE,
        )

        // Per-row tap delivers a fillInIntent merged with this template.
        // FLAG_MUTABLE is required (Android 12+) so the system can write the
        // fillInIntent's data URI into the template at click time.
        val template = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val templatePending = PendingIntent.getActivity(
            context,
            appWidgetId,
            template,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        views.setPendingIntentTemplate(R.id.articles_list, templatePending)
    }

    private fun wireClickIntents(context: Context, views: RemoteViews, appWidgetId: Int) {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse("io.supabase.facteur://digest")
        }
        val openPending = PendingIntent.getActivity(
            context,
            appWidgetId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.app_name, openPending)
        views.setOnClickPendingIntent(R.id.subtitle, openPending)
        views.setOnClickPendingIntent(R.id.btn_open, openPending)

        val refreshIntent = Intent(context, FacteurWidget::class.java).apply {
            action = ACTION_REFRESH
        }
        val refreshPending = PendingIntent.getBroadcast(
            context,
            appWidgetId,
            refreshIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.btn_refresh, refreshPending)
    }
}
