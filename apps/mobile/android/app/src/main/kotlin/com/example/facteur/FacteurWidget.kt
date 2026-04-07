package com.example.facteur

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class FacteurWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "FacteurWidget"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val widgetData = HomeWidgetPlugin.getData(context)
                if (widgetData == null) {
                    Log.w(TAG, "Widget data unavailable, skipping update")
                    continue
                }
                val views = RemoteViews(context.packageName, R.layout.facteur_widget)

                // Status data
                val status = widgetData.getString("digest_status", "none")
                val progress = widgetData.getString("digest_progress", "0/0")
                val remaining = widgetData.getString("remaining_count", "0")
                val streak = widgetData.getString("streak", "0")

                // Streak display
                val streakInt = streak?.toIntOrNull() ?: 0
                if (streakInt > 0) {
                    views.setTextViewText(R.id.streak_text, "\uD83D\uDD25 ${streakInt}j")
                } else {
                    views.setTextViewText(R.id.streak_text, "")
                }

                // Status message
                val statusMessage = when (status) {
                    "completed" -> "Essentiel du jour complété ✓"
                    "in_progress" -> "Continue ton essentiel · $progress"
                    "available" -> "Ton essentiel du jour t\u2019attend !"
                    else -> "Ouvre Facteur pour commencer"
                }
                views.setTextViewText(R.id.status_message, statusMessage)

                // Article 1
                bindArticleCard(
                    views,
                    titleId = R.id.article_title_1,
                    metaId = R.id.article_meta_1,
                    imageId = R.id.article_image_1,
                    logoId = R.id.article_logo_1,
                    title = widgetData.getString("article_title", null),
                    source = widgetData.getString("article_source", null),
                    imagePath = widgetData.getString("article_image_path", null),
                    logoPath = widgetData.getString("article_logo_path", null),
                    fallbackText = "Ouvre l\u2019app pour charger ton essentiel"
                )

                // Article 2
                val title2 = widgetData.getString("article_2_title", null)
                if (!title2.isNullOrEmpty()) {
                    views.setViewVisibility(R.id.article_card_2, View.VISIBLE)
                    bindArticleCard(
                        views,
                        titleId = R.id.article_title_2,
                        metaId = R.id.article_meta_2,
                        imageId = R.id.article_image_2,
                        logoId = R.id.article_logo_2,
                        title = title2,
                        source = widgetData.getString("article_2_source", null),
                        imagePath = widgetData.getString("article_2_image_path", null),
                        logoPath = widgetData.getString("article_2_logo_path", null),
                        fallbackText = null
                    )
                } else {
                    views.setViewVisibility(R.id.article_card_2, View.GONE)
                }

                // Button text
                val remainingInt = remaining?.toIntOrNull() ?: 0
                if (remainingInt > 0) {
                    views.setTextViewText(R.id.btn_more, "Voir $remainingInt autres news")
                } else {
                    views.setTextViewText(R.id.btn_more, "Voir le digest")
                }

                // PendingIntents — open app
                val digestIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("io.supabase.facteur://digest")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val digestPending = PendingIntent.getActivity(
                    context, 0, digestIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val feedIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("io.supabase.facteur://feed")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val feedPending = PendingIntent.getActivity(
                    context, 1, feedIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                // Bind click handlers
                views.setOnClickPendingIntent(R.id.article_card_1, digestPending)
                views.setOnClickPendingIntent(R.id.article_card_2, digestPending)
                views.setOnClickPendingIntent(R.id.btn_more, digestPending)
                views.setOnClickPendingIntent(R.id.btn_explore, feedPending)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId", e)
            }
        }
    }

    private fun bindArticleCard(
        views: RemoteViews,
        titleId: Int,
        metaId: Int,
        imageId: Int,
        logoId: Int,
        title: String?,
        source: String?,
        imagePath: String?,
        logoPath: String?,
        fallbackText: String?
    ) {
        if (!title.isNullOrEmpty()) {
            views.setTextViewText(titleId, title)
            views.setTextViewText(metaId, source ?: "")
        } else if (fallbackText != null) {
            views.setTextViewText(titleId, fallbackText)
            views.setTextViewText(metaId, "")
        } else {
            views.setTextViewText(titleId, "")
            views.setTextViewText(metaId, "")
        }

        val bitmap = loadBitmapOrNull(imagePath)
        if (bitmap != null) {
            views.setImageViewBitmap(imageId, bitmap)
            views.setViewVisibility(imageId, View.VISIBLE)
        } else {
            views.setViewVisibility(imageId, View.GONE)
        }

        val logo = loadBitmapOrNull(logoPath)
        if (logo != null) {
            views.setImageViewBitmap(logoId, logo)
            views.setViewVisibility(logoId, View.VISIBLE)
        } else {
            views.setViewVisibility(logoId, View.GONE)
        }
    }

    private fun loadBitmapOrNull(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            val file = File(path)
            if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to decode bitmap: $path", e)
            null
        }
    }
}
