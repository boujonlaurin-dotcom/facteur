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
 * RemoteViewsService backing the home-screen widget's scrollable article list.
 *
 * Reads the same `articles_json` SharedPreferences key that
 * [FacteurWidget] uses, so refresh paths stay consistent: any caller that
 * already invokes `appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.articles_list)`
 * triggers a re-read here.
 */
class FacteurWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return FacteurRemoteViewsFactory(applicationContext)
    }
}

private class FacteurRemoteViewsFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    private companion object {
        const val TAG = "FacteurWidgetSvc"
    }

    private var articles: List<WidgetRendering.Article> = emptyList()

    override fun onCreate() {
        // Initial population happens in onDataSetChanged when the host calls it.
    }

    override fun onDataSetChanged() {
        val prefs = HomeWidgetPlugin.getData(context)
        val json = prefs?.getString("articles_json", null)
        articles = WidgetRendering.parseArticles(json)
        Log.d(TAG, "onDataSetChanged count=${articles.size}")
    }

    override fun onDestroy() {
        articles = emptyList()
    }

    override fun getCount(): Int = articles.size

    override fun getViewAt(position: Int): RemoteViews {
        val article = articles.getOrNull(position) ?: return loadingRow()
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

        val thumb = WidgetRendering.loadBitmap(context, article.thumbnailPath, 72)?.let {
            WidgetRendering.roundCorners(context, it, 8f)
        }
        if (thumb != null) {
            rv.setImageViewBitmap(R.id.row_thumbnail, thumb)
            rv.setViewVisibility(R.id.row_thumbnail, View.VISIBLE)
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
        val fillIn = Intent().apply {
            data = Uri.parse("io.supabase.facteur://digest/${article.id}")
                .buildUpon()
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
        RemoteViews(context.packageName, R.layout.widget_article_row)
}
