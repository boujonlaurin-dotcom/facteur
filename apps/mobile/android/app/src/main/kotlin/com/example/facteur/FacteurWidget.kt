package com.example.facteur

import android.app.AlarmManager
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
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget mirroring the in-app **Flâner** feed: the newest articles
 * first, capped at [WidgetRendering.MAX_ROWS]. The user picks at install time
 * between two visual variants (Clair / Sombre) via the [FacteurWidgetLight] /
 * [FacteurWidgetDark] subclasses — each is its own AppWidgetProvider with a
 * dedicated layout and color set.
 *
 * Data flow: Flutter writes `widget_articles_json` (deduplicated, sorted
 * newest-first, capped) and `articles_updated_at` via the `home_widget`
 * package; this provider only renders what it finds there.
 *
 * The widget used to render "L'Essentiel du jour, then the Flux". That header
 * block came from a key only `DigestNotifier` ever wrote, and it stopped being
 * written when L'Essentiel merged into the Tournée — so it froze on its last
 * snapshot, permanently occupying the top five rows while the rest refreshed
 * underneath. Cf. docs/bugs/bug-widget-flaner-android.md (D1).
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
        const val UPDATED_AT_KEY = "articles_updated_at"

        /**
         * Horodatage du tap sur 🔄. Le masthead affiche « Mise à jour… » tant
         * que ce marqueur est frais ; Dart le remet à 0 en fin de
         * rafraîchissement (`WidgetService.finishRefresh`).
         *
         * Un booléen ne suffisait pas : si le rafraîchissement n'aboutit
         * jamais (process tué, quota WorkManager, hors ligne prolongé), rien
         * ne le remet à false et le widget reste bloqué sur un état
         * transitoire. Avec un horodatage, l'état **expire tout seul**.
         */
        const val REFRESHING_SINCE_KEY = "widget_refreshing_since"

        /** Au-delà, le marqueur est considéré périmé et ignoré. */
        private const val REFRESHING_TTL_MS = 45_000L

        /**
         * Repaint de sécurité programmé au tap sur 🔄.
         *
         * Sans lui, sortir de « Mise à jour… » supposait qu'un repaint arrive
         * *de quelque part* : de Dart en fin de rafraîchissement, ou de
         * l'alarme système `updatePeriodMillis` — 30 minutes plus tard. Si la
         * chaîne Dart ne rend jamais la main (process tué, worker jamais
         * exécuté, quota), l'état restait affiché une demi-heure. Cette alarme
         * garantit un repaint peu après l'expiration du TTL, quoi qu'il arrive
         * en aval.
         */
        const val ACTION_SETTLE = "com.example.facteur.action.WIDGET_SETTLE"

        /** Broadcast émis par le bouton 🔄 du widget, reçu par [onReceive]. */
        const val ACTION_REFRESH = "com.example.facteur.action.WIDGET_REFRESH"

        /**
         * URI passée à l'isolate Dart. Le host doit rester aligné avec
         * `_widgetRefreshHost` dans `lib/main.dart` — gardé par
         * `test/android/widget_resources_test.dart`.
         */
        const val REFRESH_URI = "facteur://widget-refresh"
    }

    /**
     * Le bouton 🔄 rafraîchit **en place**, sans ouvrir l'app.
     *
     * Il ouvrait auparavant `MainActivity` via `feed?refresh=1` : le flux était
     * bien refetché, mais l'utilisateur était éjecté de son écran d'accueil et
     * rien ne bougeait dans le widget lui-même — d'où « le bouton refresh ne
     * fonctionne pas ». Cf. docs/bugs/bug-widget-flaner-android.md (D4).
     *
     * Deux temps, parce qu'un rafraîchissement réseau prend quelques secondes
     * et qu'un bouton sans retour visuel est indistinguable d'un bouton mort :
     *  1. repeindre immédiatement le masthead en « Mise à jour… » ;
     *  2. réveiller l'isolate Dart de fond (`homeWidgetBackgroundCallback`),
     *     qui refetch et repousse le payload — puis repeint dans tous les cas,
     *     y compris en échec, pour sortir de l'état transitoire.
     */
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> {
                onRefreshRequested(context)
                return
            }
            ACTION_SETTLE -> {
                repaintAll(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    /** Repeint tous les widgets épinglés de cette variante depuis les prefs. */
    private fun repaintAll(context: Context) {
        try {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
            if (ids.isNotEmpty()) onUpdate(context, manager, ids)
            Log.d(TAG, "repaintAll theme=$theme ids=${ids.size}")
        } catch (t: Throwable) {
            Log.e(TAG, "repaintAll failed", t)
        }
    }

    /**
     * Programme le repaint de sécurité peu après l'expiration du TTL.
     *
     * `set()` (inexact) ne demande aucune permission — contrairement à
     * `setExact*`, soumis à `SCHEDULE_EXACT_ALARM` depuis Android 12. Une
     * imprécision de quelques secondes est sans importance ici : on veut
     * seulement garantir qu'*un* repaint finit par arriver.
     */
    private fun scheduleSettle(context: Context) {
        try {
            val intent = Intent(context, javaClass).apply { action = ACTION_SETTLE }
            val pending = PendingIntent.getBroadcast(
                context,
                javaClass.name.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarms?.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + REFRESHING_TTL_MS + 3_000L,
                pending,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "scheduleSettle failed", t)
        }
    }

    private fun onRefreshRequested(context: Context) {
        try {
            HomeWidgetPlugin.getData(context)?.edit()
                ?.putLong(REFRESHING_SINCE_KEY, System.currentTimeMillis())
                ?.apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
            for (id in ids) {
                val views = RemoteViews(context.packageName, layoutId())
                renderMasthead(context, views, id)
                bindArticleList(context, views, id)
                manager.updateAppWidget(id, views)
            }
            scheduleSettle(context)
            Log.d(TAG, "refresh requested theme=$theme ids=${ids.size}")
        } catch (t: Throwable) {
            Log.e(TAG, "Refresh placeholder paint failed", t)
        }

        // Réveille l'isolate Dart sans UI. `.send()` peut lever si le process
        // est dans un état où le service de fond ne peut pas démarrer — on ne
        // laisse jamais ça remonter depuis onReceive (ANR / crash du launcher).
        try {
            HomeWidgetBackgroundIntent
                .getBroadcast(context, Uri.parse(REFRESH_URI))
                .send()
        } catch (t: Throwable) {
            Log.e(TAG, "Background refresh dispatch failed", t)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, layoutId())

                renderMasthead(context, views, appWidgetId)
                bindArticleList(context, views, appWidgetId)

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

    private fun layoutId(): Int = if (theme == THEME_DARK) {
        R.layout.facteur_widget_dark
    } else {
        R.layout.facteur_widget_light
    }

    private fun payload(context: Context): String? =
        HomeWidgetPlugin.getData(context)?.getString(PAYLOAD_KEY, null)

    private fun renderMasthead(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
    ) {
        views.setTextViewText(R.id.masthead_meta, mastheadMeta(context))

        // Tap sur le masthead (marque + wordmark) → ouvre Flâner dans l'app.
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
        views.setOnClickPendingIntent(R.id.masthead_brand, openPending)

        // Bouton refresh : broadcast vers CE provider (voir onReceive), pas un
        // PendingIntent vers MainActivity — le widget se rafraîchit sans que
        // l'app passe au premier plan.
        val refreshIntent = Intent(context, javaClass).apply {
            action = ACTION_REFRESH
        }
        val refreshPending = PendingIntent.getBroadcast(
            context,
            appWidgetId * 10 + 3,
            refreshIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.masthead_refresh, refreshPending)
    }

    /**
     * « 42 articles · Maj 7h02 », ou « Mise à jour… » pendant un refresh.
     *
     * L'heure vient de `articles_updated_at`, c'est-à-dire du dernier push de
     * **données** par Flutter — pas de `LocalTime.now()`, qui avançait à chaque
     * repaint de l'alarme système sur une donnée inchangée (D5).
     *
     * L'état « Mise à jour… » est dérivé d'un marqueur **horodaté** et non d'un
     * drapeau : il expire de lui-même au bout de [REFRESHING_TTL_MS], donc il
     * ne peut pas rester collé si le rafraîchissement n'aboutit jamais.
     */
    private fun mastheadMeta(context: Context): String {
        if (isRefreshing(context)) return "Mise à jour…"
        val prefs = HomeWidgetPlugin.getData(context)
        val count = WidgetRendering.countArticles(prefs?.getString(PAYLOAD_KEY, null))
        val updatedAt = WidgetRendering.formatUpdatedAt(readUpdatedAt(context))
        val countLabel = if (count > 0) {
            "$count " + if (count > 1) "articles" else "article"
        } else {
            ""
        }
        return listOf(countLabel, updatedAt)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
    }

    /**
     * `true` tant qu'un rafraîchissement demandé il y a moins de
     * [REFRESHING_TTL_MS] n'a pas rendu la main. Dart remet le marqueur à 0 via
     * `WidgetService.finishRefresh()` — écrit alors comme `Long` par le plugin,
     * d'où la même tolérance de type que [readUpdatedAt].
     */
    private fun isRefreshing(context: Context): Boolean {
        val since = readLongPref(context, REFRESHING_SINCE_KEY)
        if (since <= 0L) return false
        // Une donnée poussée **après** le début du rafraîchissement prouve
        // qu'il a abouti, quel que soit le chemin qui l'a produite. C'est un
        // signal plus fiable que l'effacement explicite du marqueur, qui
        // suppose que Dart rende la main — précisément ce qui manquait quand
        // « Mise à jour… » restait collé.
        if (readLongPref(context, UPDATED_AT_KEY) >= since) return false
        val age = System.currentTimeMillis() - since
        return age in 0 until REFRESHING_TTL_MS
    }

    private fun readUpdatedAt(context: Context): Long =
        readLongPref(context, UPDATED_AT_KEY)

    /**
     * Lit une clé numérique sans présumer de son type de stockage.
     *
     * Le typage de `HomeWidgetPreferences` n'est pas sous notre contrôle : le
     * plugin sérialise un `int` Dart en `putInt` mais un `String` Dart en
     * `putString`, et le Kotlin écrit lui-même des `putLong`. Une même clé peut
     * donc changer de type selon qui l'a écrite en dernier — et un `getLong`
     * sur un `Int` lève `ClassCastException`, ce qui ferait sauter tout le
     * rendu du masthead. Passer par `all` coupe court : on lit la valeur telle
     * qu'elle est et on la convertit.
     */
    private fun readLongPref(context: Context, key: String): Long {
        val prefs = HomeWidgetPlugin.getData(context) ?: return 0L
        return when (val raw = prefs.all[key]) {
            is Number -> raw.toLong()
            is String -> raw.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun bindArticleList(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
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

        val json = payload(context)
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
