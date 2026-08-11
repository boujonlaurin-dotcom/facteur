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
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * Shared parsing + bitmap helpers for the Facteur widget.
 *
 * The payload is a mirror of the in-app **Flâner** feed: deduplicated, sorted
 * newest-first by Flutter, capped at [MAX_ROWS] rows — well under the ~1 MB
 * Binder IPC ceiling because rows carry no thumbnail, only a source logo (cf.
 * widget.5.flux-iter2).
 */
internal object WidgetRendering {

    private const val TAG = "FacteurWidget"

    /** Total cap for the rendered payload. */
    const val MAX_ROWS = 80

    data class Article(
        val id: String,
        val rank: Int,
        val topicId: String,
        val topicLabel: String,
        val title: String,
        val sourceName: String,
        val sourceLogoPath: String,
        val publishedAtIso: String,
    )

    fun parseArticles(json: String?, maxRows: Int = MAX_ROWS): List<Article> {
        if (json.isNullOrBlank() || json == "[]") return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).take(maxRows).mapNotNull { i ->
                arr.optJSONObject(i)?.let(::parseArticle)
            }
        } catch (e: Exception) {
            Log.w(TAG, "parseArticles failed", e)
            emptyList()
        }
    }

    /**
     * Cheap count without full parsing — used to render the masthead meta
     * ("12 articles · 7h02"). Falls back to 0 on any error.
     */
    fun countArticles(json: String?): Int {
        if (json.isNullOrBlank() || json == "[]") return 0
        return try {
            JSONArray(json).length().coerceAtMost(MAX_ROWS)
        } catch (_: Exception) {
            0
        }
    }

    private fun parseArticle(obj: JSONObject): Article = Article(
        id = obj.optString("id"),
        rank = obj.optInt("rank", 0),
        topicId = obj.optString("topic_id"),
        topicLabel = obj.optString("topic_label"),
        title = obj.optString("title"),
        sourceName = obj.optString("source_name"),
        sourceLogoPath = obj.optString("source_logo_path"),
        publishedAtIso = obj.optString("published_at_iso"),
    )

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

    /**
     * Âge relatif d'un article, **au format exact de Flâner**.
     *
     * Le widget est un miroir de Flâner : un même article doit y afficher la
     * même chaîne. Flâner passe par `timeago` en locale `fr_short`, dont les
     * libellés vivent dans `lib/core/utils/fr_compact_messages.dart` — on en
     * reproduit ici les seuils **et** les chaînes (« < 1 min », « 3 min »,
     * « 2h », « 4j »…). L'ancienne échelle maison (« à l'instant », « 45min »)
     * ne correspondait à rien dans l'app.
     *
     * Un [iso] **vide** est le signal délibéré envoyé par Flutter quand le
     * serveur n'a pas donné de `published_at` : ne rien afficher vaut mieux
     * qu'une date inventée. Flutter y substituait `DateTime.now()`, qui se
     * figeait dans le payload et laissait des articles vieux de plusieurs
     * jours affichés « à l'instant » (cf. bug D2).
     *
     * Un delta **négatif** (léger décalage d'horloge entre le serveur et le
     * téléphone) est ramené à zéro, donc « < 1 min » : c'est ce que fait
     * `timeago`, dont les préfixes sont vides ici. Le garde-fou précédent
     * renvoyait "" et faisait disparaître la date des articles les plus
     * frais — exactement ceux qu'on veut mettre en avant.
     */
    fun formatTime(iso: String, now: OffsetDateTime = OffsetDateTime.now()): String {
        if (iso.isBlank()) return ""
        return try {
            val parsed = OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            val seconds = Duration.between(parsed, now).seconds.coerceAtLeast(0L)
            val minutes = seconds / 60.0
            val hours = minutes / 60.0
            val days = hours / 24.0
            when {
                seconds < 45 -> "< 1 min"
                seconds < 90 -> "1 min"
                minutes < 45 -> String.format(Locale.FRENCH, "%d min", Math.round(minutes))
                minutes < 90 -> "1h"
                hours < 24 -> String.format(Locale.FRENCH, "%dh", Math.round(hours))
                hours < 48 -> "1j"
                days < 30 -> String.format(Locale.FRENCH, "%dj", Math.round(days))
                days < 60 -> "1 mo."
                days < 365 -> String.format(Locale.FRENCH, "%d mo.", Math.round(days / 30.0))
                days < 730 -> "1 an"
                else -> String.format(Locale.FRENCH, "%d ans", Math.round(days / 365.0))
            }
        } catch (e: Exception) {
            ""
        }
    }

    /**
     * Masthead freshness label, built from `articles_updated_at` (epoch millis
     * of the last **data** push from Flutter).
     *
     * This replaces a `LocalTime.now()` formatted at paint time. The system
     * alarm (`updatePeriodMillis`, 30 min) re-runs `onUpdate` **without any
     * network call**, so that clock advanced every half hour on top of data
     * that could be two weeks old: the widget actively lied about its own
     * freshness (cf. docs/bugs/bug-widget-flaner-android.md, D5).
     *
     * Returns "" when nothing has ever been pushed, so the masthead can fall
     * back to the row count alone rather than print a 1970 timestamp.
     */
    fun formatUpdatedAt(
        epochMillis: Long,
        now: LocalDateTime = LocalDateTime.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): String {
        if (epochMillis <= 0L) return ""
        return try {
            val at = Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDateTime()
            val hhmm = at.format(DateTimeFormatter.ofPattern("H'h'mm", Locale.FRENCH))
            val days = ChronoUnit.DAYS.between(at.toLocalDate(), now.toLocalDate())
            when {
                // `<= 0` et non `== 0` : une horloge qui repart en arrière
                // (fuseau, réglage manuel) ne doit pas produire « Maj dans 3
                // jours » — on retombe simplement sur l'heure.
                days <= 0L -> "Maj $hhmm"
                days == 1L -> "Maj hier $hhmm"
                else -> "Maj le " + at.format(
                    DateTimeFormatter.ofPattern("dd/MM", Locale.FRENCH),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "formatUpdatedAt failed for $epochMillis", e)
            ""
        }
    }
}
