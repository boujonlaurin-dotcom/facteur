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
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget rendering up to 5 Essentiel articles or up to 30 Flux
 * (feed) articles, switchable from the in-widget tab bar.
 *
 * Data flow: Flutter writes `articles_json` (Essentiel) and `feed_articles_json`
 * (Flux) via the `home_widget` package. The active mode is persisted natively
 * in `widget_mode` SharedPreferences (`essentiel` | `flux`, default `essentiel`)
 * and toggled via PendingIntent broadcasts on the two header tabs.
 */
class FacteurWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "FacteurWidget"
        const val ACTION_SET_MODE_ESSENTIEL = "com.example.facteur.action.SET_MODE_ESSENTIEL"
        const val ACTION_SET_MODE_FLUX = "com.example.facteur.action.SET_MODE_FLUX"

        const val MODE_ESSENTIEL = "essentiel"
        const val MODE_FLUX = "flux"
        const val PREF_KEY_MODE = "widget_mode"
        const val EXTRA_MODE = "widget_mode"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val newMode = when (intent.action) {
            ACTION_SET_MODE_ESSENTIEL -> MODE_ESSENTIEL
            ACTION_SET_MODE_FLUX -> MODE_FLUX
            else -> null
        } ?: return

        // Persist mode then re-render every instance of the widget so the tabs
        // and list reflect the new selection immediately.
        val prefs = HomeWidgetPlugin.getData(context)
        prefs?.edit()?.putString(PREF_KEY_MODE, newMode)?.apply()

        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(
            ComponentName(context, FacteurWidget::class.java),
        )
        if (ids.isNotEmpty()) {
            Log.d(TAG, "mode=$newMode ids=${ids.size}")
            onUpdate(context, mgr, ids)
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
                val mode = prefs?.getString(PREF_KEY_MODE, MODE_ESSENTIEL) ?: MODE_ESSENTIEL
                val jsonKey = if (mode == MODE_FLUX) "feed_articles_json" else "articles_json"
                val json = prefs?.getString(jsonKey, null)
                Log.d(TAG, "onUpdate id=$appWidgetId mode=$mode json.len=${json?.length ?: -1}")

                renderTabs(context, views, appWidgetId, mode)
                bindArticleList(context, views, appWidgetId, mode, json)

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

    private fun renderTabs(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        mode: String,
    ) {
        val isEssentiel = mode != MODE_FLUX
        styleTab(context, views, R.id.tab_essentiel, isEssentiel)
        styleTab(context, views, R.id.tab_flux, !isEssentiel)

        // Each tab toggles the mode via a broadcast; onReceive persists the
        // choice and re-renders. Distinct request codes keep the two
        // PendingIntents from being collapsed into one.
        val essentielIntent = Intent(context, FacteurWidget::class.java).apply {
            action = ACTION_SET_MODE_ESSENTIEL
        }
        val essentielPending = PendingIntent.getBroadcast(
            context,
            appWidgetId * 10,
            essentielIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.tab_essentiel, essentielPending)

        val fluxIntent = Intent(context, FacteurWidget::class.java).apply {
            action = ACTION_SET_MODE_FLUX
        }
        val fluxPending = PendingIntent.getBroadcast(
            context,
            appWidgetId * 10 + 1,
            fluxIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.tab_flux, fluxPending)
    }

    private fun styleTab(
        context: Context,
        views: RemoteViews,
        tabId: Int,
        active: Boolean,
    ) {
        val bg = if (active) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive
        views.setInt(tabId, "setBackgroundResource", bg)

        val color = ContextCompat.getColor(
            context,
            if (active) R.color.facteur_text_primary else R.color.facteur_text_secondary,
        )
        views.setTextColor(tabId, color)
    }

    private fun bindArticleList(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        mode: String,
        json: String?,
    ) {
        // Adapter intent — unique URI per (appWidgetId, mode) so the system
        // keeps a separate factory instance and reloads when the mode flips.
        val adapterIntent = Intent(context, FacteurWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            putExtra(EXTRA_MODE, mode)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.articles_list, adapterIntent)
        views.setEmptyView(R.id.articles_list, R.id.empty_view)

        val isEmpty = json.isNullOrBlank() || json == "[]"
        views.setViewVisibility(
            R.id.empty_view,
            if (isEmpty) View.VISIBLE else View.GONE,
        )
        val emptyCopy = if (mode == MODE_FLUX) {
            "Ouvre Facteur pour charger ton flux"
        } else {
            "Ouvre Facteur pour charger ton essentiel"
        }
        views.setTextViewText(R.id.empty_view, emptyCopy)
        // Tapping the empty view opens the right tab in the app.
        views.setOnClickPendingIntent(
            R.id.empty_view,
            buildOpenAppPendingIntent(context, appWidgetId, mode),
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

    private fun buildOpenAppPendingIntent(
        context: Context,
        appWidgetId: Int,
        mode: String,
    ): PendingIntent {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse(
                if (mode == MODE_FLUX) {
                    "io.supabase.facteur://feed"
                } else {
                    "io.supabase.facteur://digest"
                },
            )
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId * 10 + 2,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
