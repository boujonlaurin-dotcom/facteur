package com.example.facteur

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Home-screen widget rendering a unified Facteur feed: up to 5 articles from
 * the daily Essentiel followed by deduplicated Flux items, capped at
 * [WidgetRendering.MAX_ROWS] total. The user picks at install time between
 * two visual variants (Clair / Sombre) via the [FacteurWidgetLight] /
 * [FacteurWidgetDark] subclasses — each is its own AppWidgetProvider with
 * a dedicated layout and color set.
 *
 * Data flow: Flutter writes `widget_articles_json` (the merged Essentiel +
 * Flux payload) via the `home_widget` package. There is no more in-widget
 * mode switch; deeplink targets are decided per-row from the `source_kind`
 * field (`essentiel` → `digest/<id>`, `flux` → `feed/content/<id>`).
 */
abstract class FacteurWidget : AppWidgetProvider() {

    /**
     * "light" or "dark" — picks the layout, row layout and resource colors.
     * Overridden by [FacteurWidgetLight] / [FacteurWidgetDark].
     */
    protected abstract val theme: String

    companion object {
        private const val TAG = "FacteurWidget"
        const val EXTRA_THEME = "widget_theme"
        const val THEME_LIGHT = "light"
        const val THEME_DARK = "dark"
        const val PAYLOAD_KEY = "widget_articles_json"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val layoutId = if (theme == THEME_DARK) {
                    R.layout.facteur_widget_dark
                } else {
                    R.layout.facteur_widget_light
                }
                val views = RemoteViews(context.packageName, layoutId)

                val prefs = HomeWidgetPlugin.getData(context)
                val json = prefs?.getString(PAYLOAD_KEY, null)
                Log.d(TAG, "onUpdate id=$appWidgetId theme=$theme json.len=${json?.length ?: -1}")

                renderMasthead(context, views, appWidgetId, json)
                bindArticleList(context, views, appWidgetId, json)

                appWidgetManager.updateAppWidget(appWidgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(
                    appWidgetId,
                    R.id.articles_list,
                )
            } catch (t: Throwable) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId theme=$theme", t)
            }
        }
    }

    private fun renderMasthead(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        json: String?,
    ) {
        val count = WidgetRendering.countArticles(json)
        val article = if (count > 1) "articles" else "article"
        val hour = LocalTime.now().format(
            DateTimeFormatter.ofPattern("H'h'mm", Locale.FRENCH),
        )
        // "12 articles · 7h02"
        val meta = if (count > 0) "$count $article · $hour" else hour
        views.setTextViewText(R.id.masthead_meta, meta)

        // Tap on the masthead opens the feed in-app — primary surface for the
        // unified widget now that the segmented control is gone.
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse("io.supabase.facteur://feed")
        }
        val openPending = PendingIntent.getActivity(
            context,
            appWidgetId * 10,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_masthead, openPending)
    }

    private fun bindArticleList(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        json: String?,
    ) {
        // Adapter intent — unique URI per (appWidgetId, theme) so the system
        // keeps a separate factory instance per pinned widget.
        val adapterIntent = Intent(context, FacteurWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            putExtra(EXTRA_THEME, theme)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.articles_list, adapterIntent)
        views.setEmptyView(R.id.articles_list, R.id.empty_view)

        val isEmpty = json.isNullOrBlank() || json == "[]"
        views.setViewVisibility(
            R.id.empty_view,
            if (isEmpty) View.VISIBLE else View.GONE,
        )
        views.setOnClickPendingIntent(
            R.id.empty_view,
            buildOpenAppPendingIntent(context, appWidgetId),
        )

        // Per-row tap → fillInIntent merged into the template PendingIntent.
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
    ): PendingIntent {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse("io.supabase.facteur://feed")
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId * 10 + 2,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
