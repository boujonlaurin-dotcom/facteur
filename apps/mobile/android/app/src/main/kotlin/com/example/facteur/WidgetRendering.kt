package com.example.facteur

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Shared parsing + bitmap helpers used by both [FacteurWidget] (header
 * rendering, MAX_ROWS cap) and [FacteurWidgetService]'s RemoteViewsFactory
 * (row rendering inside the ListView).
 */
internal object WidgetRendering {

    private const val TAG = "FacteurWidget"
    const val MAX_ROWS = 5

    data class Article(
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

    fun parseArticles(json: String?): List<Article> {
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

    /**
     * Decode a bitmap downscaled to fit within [targetSizeDp]² to keep the
     * RemoteViews payload small. Inlining unscaled thumbnails into a single
     * RemoteViews trips Binder's ~1 MB IPC limit, surfacing as
     * "Impossible d'ajouter le widget" on the host launcher.
     */
    fun loadBitmap(context: Context, path: String?, targetSizeDp: Int): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val targetPx = (targetSizeDp * context.resources.displayMetrics.density).toInt()
                .coerceAtLeast(1)

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            var sample = 1
            while (
                bounds.outWidth / (sample * 2) >= targetPx &&
                bounds.outHeight / (sample * 2) >= targetPx
            ) {
                sample *= 2
            }

            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeFile(path, opts)
        } catch (e: Exception) {
            Log.w(TAG, "Bitmap decode failed: $path", e)
            null
        }
    }

    fun roundCorners(context: Context, src: Bitmap, radiusDp: Float): Bitmap {
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

    fun formatTime(iso: String): String {
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
