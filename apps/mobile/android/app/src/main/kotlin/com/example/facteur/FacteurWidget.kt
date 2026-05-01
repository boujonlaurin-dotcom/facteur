package com.example.facteur

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Home-screen widget rendering up to 5 digest articles inline.
 *
 * Earlier iterations used a ListView bound to a RemoteViewsService. That
 * pattern is unreliable on Samsung One UI launchers (the RemoteViewsAdapter
 * never receives data and the system shows "Chargement…" forever). We now
 * parse `articles_json` directly in [onUpdate] and append one
 * `widget_article_row` RemoteViews per article into `articles_container`.
 */
class FacteurWidget : AppWidgetProvider() {

    companion object {
        private const val TAG = "FacteurWidget"
        private const val MAX_ROWS = 5
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
                val prefs = HomeWidgetPlugin.getData(context)
                val json = prefs?.getString("articles_json", null)
                Log.d(TAG, "onUpdate id=$appWidgetId json.len=${json?.length ?: -1}")

                renderHeader(views, prefs)
                renderArticles(context, views, json)
                wireClickIntents(context, views, appWidgetId)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId", e)
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

        val updatedAt = prefs?.getString("articles_updated_at", "0")?.toLongOrNull() ?: 0L
        val isStale = updatedAt > 0 &&
            (System.currentTimeMillis() - updatedAt) > STALE_THRESHOLD_MS
        views.setViewVisibility(
            R.id.stale_banner,
            if (isStale) View.VISIBLE else View.GONE,
        )
    }

    private fun renderArticles(context: Context, views: RemoteViews, json: String?) {
        views.removeAllViews(R.id.articles_container)

        val articles = parseArticles(json)
        if (articles.isEmpty()) {
            views.addView(
                R.id.articles_container,
                buildPlaceholderRow(context, "Ouvre Facteur pour charger ton essentiel"),
            )
            return
        }

        for ((index, article) in articles.withIndex()) {
            val row = buildArticleRow(context, article)
            views.addView(R.id.articles_container, row)
            if (index < articles.size - 1) {
                // Separators are baked into widget_article_row.xml.
            }
        }
    }

    private fun parseArticles(json: String?): List<Article> {
        if (json.isNullOrBlank() || json == "[]") return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).take(MAX_ROWS).mapNotNull { i ->
                arr.optJSONObject(i)?.let(::parseArticle)
            }
        } catch (e: Exception) {
            Log.w(TAG, "parseArticles failed", e)
            emptyList()
        }
    }

    private fun parseArticle(obj: JSONObject): Article = Article(
        id = obj.optString("id"),
        rank = obj.optInt("rank", 0),
        topicId = obj.optString("topic_id"),
        topicLabel = obj.optString("topic_label"),
        isMain = obj.optBoolean("is_main", false),
        title = obj.optString("title"),
        sourceName = obj.optString("source_name"),
        sourceLogoPath = obj.optString("source_logo_path"),
        thumbnailPath = obj.optString("thumbnail_path"),
        perspectiveCount = obj.optInt("perspective_count", 0),
        publishedAtIso = obj.optString("published_at_iso"),
    )

    private fun buildArticleRow(context: Context, article: Article): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_article_row)

        rv.setTextViewText(
            R.id.row_topic,
            "${article.rank} — ${article.topicLabel.ifBlank { "Actu" }}",
        )
        rv.setViewVisibility(
            R.id.row_a_la_une,
            if (article.isMain) View.VISIBLE else View.GONE,
        )
        rv.setTextViewText(R.id.row_title, article.title)

        val thumb = loadBitmap(context, article.thumbnailPath, 60)?.let {
            roundCorners(context, it, 8f)
        }
        if (thumb != null) {
            rv.setImageViewBitmap(R.id.row_thumbnail, thumb)
            rv.setViewVisibility(R.id.row_thumbnail, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
        }

        val logo = loadBitmap(context, article.sourceLogoPath, 16)
        if (logo != null) {
            rv.setImageViewBitmap(R.id.row_source_logo, logo)
            rv.setViewVisibility(R.id.row_source_logo, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_source_logo, View.GONE)
        }
        rv.setTextViewText(R.id.row_source_name, article.sourceName)

        if (article.perspectiveCount > 0) {
            rv.setTextViewText(R.id.row_perspective, "+${article.perspectiveCount}")
            rv.setViewVisibility(R.id.row_perspective, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_perspective, View.GONE)
        }

        rv.setTextViewText(R.id.row_time, formatTime(article.publishedAtIso))

        // Tap target — open the article via deep link.
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse("io.supabase.facteur://digest/${article.id}")
                .buildUpon()
                .appendQueryParameter("pos", article.rank.toString())
                .appendQueryParameter("topicId", article.topicId)
                .build()
        }
        val pending = PendingIntent.getActivity(
            context,
            article.id.hashCode(),
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        rv.setOnClickPendingIntent(R.id.row_root, pending)

        return rv
    }

    private fun buildPlaceholderRow(context: Context, text: String): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_article_row)
        rv.setTextViewText(R.id.row_topic, "")
        rv.setViewVisibility(R.id.row_a_la_une, View.GONE)
        rv.setTextViewText(R.id.row_title, text)
        rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
        rv.setViewVisibility(R.id.row_source_logo, View.GONE)
        rv.setTextViewText(R.id.row_source_name, "")
        rv.setViewVisibility(R.id.row_perspective, View.GONE)
        rv.setTextViewText(R.id.row_time, "")
        return rv
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
        views.setOnClickPendingIntent(R.id.widget_header, openPending)
        views.setOnClickPendingIntent(R.id.subtitle, openPending)
        views.setOnClickPendingIntent(R.id.btn_open, openPending)
        views.setOnClickPendingIntent(R.id.stale_banner, openPending)
    }

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    private data class Article(
        val id: String,
        val rank: Int,
        val topicId: String,
        val topicLabel: String,
        val isMain: Boolean,
        val title: String,
        val sourceName: String,
        val sourceLogoPath: String,
        val thumbnailPath: String,
        val perspectiveCount: Int,
        val publishedAtIso: String,
    )

    /**
     * Decode a bitmap downscaled to fit within [targetSizeDp]² to keep the
     * RemoteViews payload small. Inlining 5 unscaled article thumbnails into
     * a single RemoteViews trips Binder's ~1 MB IPC limit, surfacing as
     * "Impossible d'ajouter le widget" on the host launcher.
     */
    private fun loadBitmap(context: Context, path: String?, targetSizeDp: Int): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null

            val targetPx = (targetSizeDp * context.resources.displayMetrics.density).toInt()
                .coerceAtLeast(1)

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            var sample = 1
            while (
                bounds.outWidth / (sample * 2) >= targetPx &&
                bounds.outHeight / (sample * 2) >= targetPx
            ) {
                sample *= 2
            }

            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeFile(file.absolutePath, opts)
        } catch (e: Exception) {
            Log.w(TAG, "Bitmap decode failed: $path", e)
            null
        }
    }

    private fun roundCorners(context: Context, src: Bitmap, radiusDp: Float): Bitmap {
        val r = radiusDp * context.resources.displayMetrics.density
        val output = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = RectF(0f, 0f, src.width.toFloat(), src.height.toFloat())
        canvas.drawRoundRect(rect, r, r, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return output
    }

    private fun formatTime(iso: String): String {
        if (iso.isBlank()) return ""
        return try {
            val parsed = OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            val minutes = Duration.between(parsed, OffsetDateTime.now()).toMinutes()
            when {
                minutes < 1 -> "à l'instant"
                minutes < 60 -> String.format(Locale.FRENCH, "%dmin", minutes)
                minutes < 24 * 60 -> String.format(Locale.FRENCH, "%dh", minutes / 60)
                else -> String.format(Locale.FRENCH, "%dj", minutes / (60 * 24))
            }
        } catch (e: Exception) {
            ""
        }
    }
}
