package com.example.facteur

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class FacteurWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.facteur_widget)

            // Article data
            val title = widgetData.getString("article_title", null)
            val source = widgetData.getString("article_source", null)
            val topic = widgetData.getString("article_topic", null)
            val imagePath = widgetData.getString("article_image_path", null)

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
                "completed" -> "Essentiel du jour compl\u00e9t\u00e9 \u2713"
                "in_progress" -> "Continue ton essentiel \u00b7 $progress"
                "available" -> "Ton essentiel du jour t\u2019attend !"
                else -> "Ouvre Facteur pour commencer"
            }
            views.setTextViewText(R.id.status_message, statusMessage)

            // Article card
            if (!title.isNullOrEmpty()) {
                views.setTextViewText(R.id.article_title, title)
                val meta = listOfNotNull(source, topic).joinToString(" \u00b7 ")
                views.setTextViewText(R.id.article_meta, meta)
            } else {
                views.setTextViewText(R.id.article_title, "Ouvre l\u2019app pour charger ton essentiel")
                views.setTextViewText(R.id.article_meta, "")
            }

            // Thumbnail image
            if (!imagePath.isNullOrEmpty()) {
                val file = File(imagePath)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.article_image, bitmap)
                    }
                }
            }

            // Button text: "Voir N autres news"
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
            views.setOnClickPendingIntent(R.id.article_card, digestPending)
            views.setOnClickPendingIntent(R.id.btn_more, digestPending)
            views.setOnClickPendingIntent(R.id.btn_explore, feedPending)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
