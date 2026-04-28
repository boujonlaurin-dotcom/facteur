package com.example.facteur

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
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Backs the widget's ListView. Reads `articles_json` from the home_widget
 * SharedPreferences bridge, deserialises into widget rows, and inflates one
 * `widget_article_row` per article. When the JSON is absent or empty, falls
 * back to a single placeholder row driving the user back into the app.
 */
class FacteurWidgetRemoteViewsFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    companion object {
        private const val TAG = "FacteurWidgetFactory"
        private const val EXTRA_ARTICLE_ID = "article_id"
        private const val EXTRA_POSITION = "position"
        private const val EXTRA_TOPIC_ID = "topic_id"
    }

    private data class Row(
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
        val isPlaceholder: Boolean = false,
    )

    private val rows: MutableList<Row> = mutableListOf()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        rows.clear()
        try {
            val data = HomeWidgetPlugin.getData(context)
            val json = data?.getString("articles_json", null)
            Log.d(
                TAG,
                "onDataSetChanged: data=${data != null} json.len=${json?.length ?: -1}",
            )
            if (data == null || json.isNullOrBlank() || json == "[]") {
                rows.add(placeholderRow("Ouvre Facteur pour charger ton essentiel"))
                return
            }
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                rows.add(parseRow(obj))
            }
            if (rows.isEmpty()) {
                rows.add(placeholderRow("Ouvre Facteur pour charger ton essentiel"))
            }
            Log.d(TAG, "onDataSetChanged: rows=${rows.size}")
        } catch (e: Exception) {
            Log.w(TAG, "onDataSetChanged failed", e)
            rows.clear()
            rows.add(placeholderRow("Ouvre Facteur pour charger ton essentiel"))
        }
    }

    override fun onDestroy() {
        rows.clear()
    }

    override fun getCount(): Int = if (rows.isEmpty()) 1 else rows.size

    override fun getViewAt(position: Int): RemoteViews = try {
        buildViewAt(position)
    } catch (e: Exception) {
        Log.w(TAG, "getViewAt($position) failed", e)
        placeholderViews("Ouvre Facteur pour charger ton essentiel")
    }

    private fun buildViewAt(position: Int): RemoteViews {
        val row = rows.getOrNull(position) ?: return placeholderViews(
            "Ouvre Facteur pour charger ton essentiel"
        )
        if (row.isPlaceholder) {
            return placeholderViews(row.title)
        }

        val rv = RemoteViews(context.packageName, R.layout.widget_article_row)
        rv.setTextViewText(
            R.id.row_topic,
            "${row.rank} — ${row.topicLabel.ifBlank { "Actu" }}"
        )
        rv.setViewVisibility(
            R.id.row_a_la_une,
            if (row.isMain) View.VISIBLE else View.GONE
        )
        rv.setTextViewText(R.id.row_title, row.title)

        // Thumbnail (rounded 8dp corners)
        val thumb = loadBitmap(row.thumbnailPath)?.let { roundCorners(it, 8f) }
        if (thumb != null) {
            rv.setImageViewBitmap(R.id.row_thumbnail, thumb)
            rv.setViewVisibility(R.id.row_thumbnail, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
        }

        // Source line
        val logo = loadBitmap(row.sourceLogoPath)
        if (logo != null) {
            rv.setImageViewBitmap(R.id.row_source_logo, logo)
            rv.setViewVisibility(R.id.row_source_logo, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_source_logo, View.GONE)
        }
        rv.setTextViewText(R.id.row_source_name, row.sourceName)

        if (row.perspectiveCount > 0) {
            rv.setTextViewText(R.id.row_perspective, "+${row.perspectiveCount}")
            rv.setViewVisibility(R.id.row_perspective, View.VISIBLE)
        } else {
            rv.setViewVisibility(R.id.row_perspective, View.GONE)
        }

        rv.setTextViewText(R.id.row_time, formatTime(row.publishedAtIso))

        // Tap target — encoded into the fillInIntent for setPendingIntentTemplate.
        // The base template URI is io.supabase.facteur://digest/. We append the
        // article id by setting the data URI on the fillInIntent.
        val fillIn = Intent().apply {
            data = Uri.parse("io.supabase.facteur://digest/${row.id}")
                .buildUpon()
                .appendQueryParameter("pos", row.rank.toString())
                .appendQueryParameter("topicId", row.topicId)
                .build()
            putExtra(EXTRA_ARTICLE_ID, row.id)
            putExtra(EXTRA_POSITION, row.rank)
            putExtra(EXTRA_TOPIC_ID, row.topicId)
        }
        rv.setOnClickFillInIntent(R.id.row_root, fillIn)

        return rv
    }

    override fun getLoadingView(): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_loading_view)

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long {
        val row = rows.getOrNull(position) ?: return position.toLong()
        return row.id.hashCode().toLong()
    }

    override fun hasStableIds(): Boolean = true

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    private fun parseRow(obj: JSONObject): Row {
        return Row(
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
    }

    private fun placeholderRow(text: String): Row = Row(
        id = "__placeholder__",
        rank = 0,
        topicId = "",
        topicLabel = "",
        isMain = false,
        title = text,
        sourceName = "",
        sourceLogoPath = "",
        thumbnailPath = "",
        perspectiveCount = 0,
        publishedAtIso = "",
        isPlaceholder = true,
    )

    private fun placeholderViews(text: String): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_article_row)
        rv.setTextViewText(R.id.row_topic, "")
        rv.setViewVisibility(R.id.row_a_la_une, View.GONE)
        rv.setTextViewText(R.id.row_title, text)
        rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
        rv.setViewVisibility(R.id.row_source_logo, View.GONE)
        rv.setTextViewText(R.id.row_source_name, "")
        rv.setViewVisibility(R.id.row_perspective, View.GONE)
        rv.setTextViewText(R.id.row_time, "")
        // Placeholder taps just fall through to the template (digest).
        rv.setOnClickFillInIntent(R.id.row_root, Intent())
        return rv
    }

    private fun roundCorners(src: Bitmap, radiusDp: Float): Bitmap {
        val density = context.resources.displayMetrics.density
        val r = radiusDp * density
        val output = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = RectF(0f, 0f, src.width.toFloat(), src.height.toFloat())
        canvas.drawRoundRect(rect, r, r, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return output
    }

    private fun loadBitmap(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path)
            if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
        } catch (e: Exception) {
            Log.w(TAG, "Bitmap decode failed: $path (${e.message})")
            null
        }
    }

    private fun formatTime(iso: String): String {
        if (iso.isBlank()) return ""
        return try {
            val parsed = OffsetDateTime.parse(
                iso,
                DateTimeFormatter.ISO_OFFSET_DATE_TIME
            )
            val diff = Duration.between(parsed, OffsetDateTime.now())
            val minutes = diff.toMinutes()
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
