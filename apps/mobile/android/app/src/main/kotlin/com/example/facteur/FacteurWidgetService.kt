package com.example.facteur

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * RemoteViewsService backing the unified Facteur widget feed.
 *
 * Reads `widget_articles_json` (the Essentiel-then-Flux merged payload, capped
 * at [WidgetRendering.MAX_ROWS]) from the SharedPreferences shared with Flutter
 * via `home_widget`. The `EXTRA_THEME` extra picks between the Clair / Sombre
 * row layouts; deeplink target per row is decided from the `source_kind` field
 * on the article (Essentiel → digest reader, Flux → feed reader).
 */
class FacteurWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val theme = intent.getStringExtra(FacteurWidget.EXTRA_THEME)
            ?: FacteurWidget.THEME_LIGHT
        return FacteurRemoteViewsFactory(applicationContext, theme)
    }
}

private class FacteurRemoteViewsFactory(
    private val context: Context,
    private val theme: String,
) : RemoteViewsService.RemoteViewsFactory {

    private companion object {
        const val TAG = "FacteurWidgetSvc"
        const val PREF_MAX_POSITION = "widget_flux_max_scroll_position"
        const val PREF_TOTAL_COUNT = "widget_flux_total_count"
        const val PREF_AT = "widget_flux_max_scroll_at"
    }

    private val rowLayoutId: Int = if (theme == FacteurWidget.THEME_DARK) {
        R.layout.widget_article_row_dark
    } else {
        R.layout.widget_article_row_light
    }

    private var articles: List<WidgetRendering.Article> = emptyList()

    // Highest row index seen by getViewAt during the current view session.
    // Reset to -1 after each flush. Flushed in onDataSetChanged (start of a
    // new session) and onDestroy (factory torn down).
    private var maxPositionSeen: Int = -1

    override fun onCreate() {
        // Initial population happens in onDataSetChanged when the host calls it.
    }

    override fun onDataSetChanged() {
        // End of the previous view session: persist the max scroll observed.
        flushScrollMetricIfNeeded()

        val prefs = HomeWidgetPlugin.getData(context)
        val json = prefs?.getString(FacteurWidget.PAYLOAD_KEY, null)
        articles = WidgetRendering.parseArticles(json)
        Log.d(TAG, "onDataSetChanged theme=$theme count=${articles.size}")
    }

    override fun onDestroy() {
        flushScrollMetricIfNeeded()
        articles = emptyList()
    }

    override fun getCount(): Int = articles.size

    override fun getViewAt(position: Int): RemoteViews {
        val article = articles.getOrNull(position) ?: return loadingRow()
        if (position > maxPositionSeen) {
            maxPositionSeen = position
        }
        val rv = RemoteViews(context.packageName, rowLayoutId)

        // Topic line: Essentiel keeps the rank prefix ("1 — Climat") as a
        // positional cue inside the daily 5; Flux drops it to feel like a
        // continuous scroll.
        val topicSegment = article.topicLabel.ifBlank { "Actu" }
        val topicLine = if (article.sourceKind == WidgetRendering.SOURCE_KIND_ESSENTIEL) {
            "${article.rank} — $topicSegment"
        } else {
            topicSegment
        }
        rv.setTextViewText(R.id.row_topic, topicLine)
        rv.setViewVisibility(
            R.id.row_a_la_une,
            if (article.isMain) View.VISIBLE else View.GONE,
        )
        rv.setTextViewText(R.id.row_title, article.title)

        // Thumbnails: only Essentiel articles carry one (Flux is image-less
        // to keep the merged payload under the Binder ceiling at MAX_ROWS=80).
        if (article.sourceKind == WidgetRendering.SOURCE_KIND_ESSENTIEL) {
            val thumb = WidgetRendering.loadBitmap(context, article.thumbnailPath, 72)?.let {
                WidgetRendering.roundCorners(context, it, 8f)
            }
            if (thumb != null) {
                rv.setImageViewBitmap(R.id.row_thumbnail, thumb)
                rv.setViewVisibility(R.id.row_thumbnail, View.VISIBLE)
            } else {
                rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
            }
        } else {
            rv.setViewVisibility(R.id.row_thumbnail, View.GONE)
        }

        val logo = WidgetRendering.loadBitmap(context, article.sourceLogoPath, 18)
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

        rv.setTextViewText(R.id.row_time, WidgetRendering.formatTime(article.publishedAtIso))

        // Per-row tap → fillInIntent merged into the template PendingIntent
        // declared by FacteurWidget.onUpdate (setPendingIntentTemplate).
        // Deep link host depends on the source_kind:
        //  - Essentiel → digest reader (digest/<id>)
        //  - Flux      → feed reader   (feed/content/<id>)
        val baseUri = if (article.sourceKind == WidgetRendering.SOURCE_KIND_ESSENTIEL) {
            Uri.parse("io.supabase.facteur://digest/${article.id}")
        } else {
            Uri.parse("io.supabase.facteur://feed/content/${article.id}")
        }
        val fillIn = Intent().apply {
            data = baseUri.buildUpon()
                .appendQueryParameter("pos", article.rank.toString())
                .appendQueryParameter("topicId", article.topicId)
                .build()
        }
        rv.setOnClickFillInIntent(R.id.row_root, fillIn)

        return rv
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        articles.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun loadingRow(): RemoteViews =
        RemoteViews(context.packageName, rowLayoutId)

    /**
     * Persist the max scroll position observed during the current view session
     * so the Flutter side can flush it as a `widget_flux_scroll` PostHog event
     * on the next foreground. Idempotent — only writes when [maxPositionSeen]
     * exceeds the previously stored value, so a scrolled-but-not-flushed
     * session isn't overwritten by a later session that scrolled less.
     *
     * Single batched write per session (start + end of factory life) — never
     * per-row — to keep getViewAt jank-free. The PREF_* keys keep their
     * historic `widget_flux_*` prefix for funnel continuity in PostHog.
     */
    private fun flushScrollMetricIfNeeded() {
        if (maxPositionSeen < 0) return
        val total = articles.size
        if (total <= 0) {
            maxPositionSeen = -1
            return
        }
        val prefs = HomeWidgetPlugin.getData(context) ?: return
        val existing = prefs.getInt(PREF_MAX_POSITION, -1)
        if (maxPositionSeen <= existing) {
            maxPositionSeen = -1
            return
        }
        prefs.edit()
            .putInt(PREF_MAX_POSITION, maxPositionSeen)
            .putInt(PREF_TOTAL_COUNT, total)
            .putLong(PREF_AT, System.currentTimeMillis())
            .apply()
        Log.d(TAG, "flushScrollMetric max=$maxPositionSeen total=$total")
        maxPositionSeen = -1
    }
}
