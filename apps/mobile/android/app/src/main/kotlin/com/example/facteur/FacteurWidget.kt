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

/**
 * Home-screen widget hosting a scrollable list of digest articles. The list
 * is bound via [setRemoteAdapter] to [FacteurWidgetService], which reads
 * SharedPreferences populated from Flutter (`articles_json` etc.).
 *
 * Tap targets:
 *  - Header / footer / empty area → `io.supabase.facteur://digest`
 *  - List rows → `io.supabase.facteur://digest/<articleId>?pos=…&topicId=…`
 *
 * Both URIs are caught by the Flutter [DeepLinkService] (custom scheme is
 * registered in AndroidManifest) and routed via GoRouter.
 */
class FacteurWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "FacteurWidget"
        private const val STALE_THRESHOLD_MS = 36L * 60 * 60 * 1000 // 36h
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.facteur_widget)
                val data = HomeWidgetPlugin.getData(context)

                // Header — streak
                val streak = data?.getString("streak", "0")?.toIntOrNull() ?: 0
                if (streak > 0) {
                    views.setTextViewText(R.id.streak_text, "🔥 ${streak}j")
                } else {
                    views.setTextViewText(R.id.streak_text, "")
                }

                // Subtitle reflects digest progress when known
                val subtitle = when (data?.getString("digest_status", "none")) {
                    "completed" -> "Essentiel du jour complété ✓"
                    "in_progress" -> "Continue ton essentiel"
                    "available" -> "L'Essentiel du jour"
                    else -> "L'Essentiel du jour"
                }
                views.setTextViewText(R.id.subtitle, subtitle)

                // Stale banner
                val updatedAt = data?.getString("articles_updated_at", "0")
                    ?.toLongOrNull() ?: 0L
                val isStale = updatedAt > 0 &&
                    (System.currentTimeMillis() - updatedAt) > STALE_THRESHOLD_MS
                views.setViewVisibility(
                    R.id.stale_banner,
                    if (isStale) View.VISIBLE else View.GONE,
                )

                // Bind ListView to RemoteViewsService
                val serviceIntent = Intent(context, FacteurWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    // Required to make each instance unique so Android does not
                    // recycle factory instances across widgets.
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
                views.setRemoteAdapter(R.id.articles_list, serviceIntent)
                views.setEmptyView(R.id.articles_list, R.id.empty_view)

                // Pending intent template — list rows append the article path
                // via setOnClickFillInIntent in FacteurWidgetRemoteViewsFactory.
                val templateIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    data = Uri.parse("io.supabase.facteur://digest/")
                }
                val templatePending = PendingIntent.getActivity(
                    context,
                    0,
                    templateIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                )
                views.setPendingIntentTemplate(R.id.articles_list, templatePending)

                // Open-app pending intent — used by header, subtitle, footer button,
                // empty view (and the stale banner).
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    data = Uri.parse("io.supabase.facteur://digest")
                }
                val openPending = PendingIntent.getActivity(
                    context,
                    1,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_header, openPending)
                views.setOnClickPendingIntent(R.id.subtitle, openPending)
                views.setOnClickPendingIntent(R.id.btn_open, openPending)
                views.setOnClickPendingIntent(R.id.empty_view, openPending)
                views.setOnClickPendingIntent(R.id.stale_banner, openPending)

                appWidgetManager.updateAppWidget(appWidgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(
                    appWidgetId,
                    R.id.articles_list,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId", e)
            }
        }
    }
}
