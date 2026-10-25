package dev.arne5.lightlib

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The library's bento cards as home-screen widgets. The app writes a
 * snapshot of what they show (already in the app's language, see
 * lib/services/home_widgets.dart); the widgets draw it and open the app
 * on a tap.
 */
object HomeWidgets {
    private const val PREFS = "lightlib_widgets"
    private const val KEY = "snapshot"
    const val ACTION_OPEN = "dev.arne5.lightlib.WIDGET_OPEN"
    const val EXTRA_BOOK = "bookId"
    const val EXTRA_LIBRARY = "library"

    fun save(context: Context, snapshot: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, snapshot).apply()
        updateAll(context)
    }

    fun load(context: Context): JSONObject? = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)?.let { JSONObject(it) }
    } catch (e: Exception) {
        null
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in listOf(ContinueReadingWidget::class.java, ReadingRecapWidget::class.java)) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            val intent = Intent(context, provider)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }

    /** What a widget tap asks for, from the intent that opened the app. */
    fun actionOf(intent: Intent?): Map<String, Any>? {
        if (intent?.action != ACTION_OPEN) return null
        val book = intent.getStringExtra(EXTRA_BOOK)
        return when {
            !book.isNullOrEmpty() -> mapOf("bookId" to book)
            intent.getBooleanExtra(EXTRA_LIBRARY, false) -> mapOf("library" to true)
            else -> null
        }
    }

    fun openIntent(context: Context, requestCode: Int, bookId: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (bookId != null) intent.putExtra(EXTRA_BOOK, bookId)
        else intent.putExtra(EXTRA_LIBRARY, true)
        return PendingIntent.getActivity(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun dp(context: Context, value: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics)

    /** The widget's current size in dp (the smaller, portrait width). */
    fun sizeOf(manager: AppWidgetManager, id: Int): Pair<Int, Int> {
        val options: Bundle = manager.getAppWidgetOptions(id)
        val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110))
        return Pair(if (w > 0) w else 250, if (h > 0) h else 110)
    }

    /** A cover file decoded near [heightPx] tall, cropped to 2:3, rounded. */
    fun cover(context: Context, path: String?, heightPx: Int, radiusPx: Float): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outHeight / (sample * 2) >= heightPx) sample *= 2
            val source = BitmapFactory.decodeFile(path,
                BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            val h = min(heightPx, source.height * 2)
            val w = (h * 2f / 3f).roundToInt()
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            // Centre-crop the picture into 2:3.
            val scale = max(w.toFloat() / source.width, h.toFloat() / source.height)
            val matrix = Matrix().apply {
                setScale(scale, scale)
                postTranslate((w - source.width * scale) / 2f, (h - source.height * scale) / 2f)
            }
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            shader.setLocalMatrix(matrix)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                this.shader = shader
            }
            canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radiusPx, radiusPx, paint)
            if (source != out) source.recycle()
            out
        } catch (e: Throwable) {
            null
        }
    }

    /** The checkpoint ring: [progress] of a circle with the percentage. */
    fun ring(context: Context, progress: Double, sizePx: Int): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val stroke = sizePx * 0.1f
        val box = RectF(stroke / 2, stroke / 2, sizePx - stroke / 2, sizePx - stroke / 2)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = color(context, R.color.widget_track)
        }
        canvas.drawArc(box, 0f, 360f, false, track)
        val arc = Paint(track).apply {
            color = color(context, R.color.widget_primary)
            strokeCap = Paint.Cap.ROUND
        }
        val p = progress.coerceIn(0.0, 1.0)
        if (p > 0) canvas.drawArc(box, -90f, (360 * p).toFloat(), false, arc)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = color(context, R.color.widget_on_primary_container)
            textSize = sizePx * 0.24f
            textAlign = Paint.Align.CENTER
            isFakeBoldText = true
        }
        val y = sizePx / 2f - (text.descent() + text.ascent()) / 2
        canvas.drawText("${(p * 100).roundToInt()}%", sizePx / 2f, y, text)
        return out
    }

    /** Four weeks as two rows of fourteen days, oldest first; today ringed. */
    fun heatmap(context: Context, days: List<Int>, widthPx: Int): Bitmap {
        val columns = 14
        val gap = dp(context, 4f)
        val cell = min((widthPx - gap * (columns - 1)) / columns, dp(context, 16f))
        val width = (cell * columns + gap * (columns - 1)).roundToInt()
        val height = (cell * 2 + gap).roundToInt()
        val out = Bitmap.createBitmap(max(width, 1), max(height, 1), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val primary = color(context, R.color.widget_primary)
        val empty = color(context, R.color.widget_track)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = cell * 0.22f
        for (i in 0 until min(days.size, columns * 2)) {
            val hits = days[i]
            paint.color = when {
                hits <= 0 -> empty
                hits < 3 -> withAlpha(primary, 90)
                hits < 10 -> withAlpha(primary, 165)
                else -> primary
            }
            val row = i / columns
            val col = i % columns
            val left = col * (cell + gap)
            val top = row * (cell + gap)
            canvas.drawRoundRect(RectF(left, top, left + cell, top + cell), radius, radius, paint)
            if (i == columns * 2 - 1) {
                val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp(context, 1f)
                    color = color(context, R.color.widget_on)
                }
                canvas.drawRoundRect(RectF(left, top, left + cell, top + cell), radius, radius, ringPaint)
            }
        }
        return out
    }

    private fun color(context: Context, id: Int): Int = context.getColor(id)

    private fun withAlpha(color: Int, alpha: Int) = (color and 0x00FFFFFF) or (alpha shl 24)
}

/**
 * The widget's views for every size the launcher may give it. On Android
 * 12+ the launcher picks the variant that fits (also after the phone is
 * folded or unfolded); before, the widget's current size decides.
 */
internal fun responsive(
    context: Context, manager: AppWidgetManager, id: Int,
    sizes: List<SizeF>, build: (Float, Float) -> RemoteViews
): RemoteViews {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        return RemoteViews(sizes.associateWith { build(it.width, it.height) })
    }
    val (w, h) = HomeWidgets.sizeOf(manager, id)
    return build(w.toFloat(), h.toFloat())
}

/** "Continue reading": the book being read (or the newest), and the next. */
class ContinueReadingWidget : AppWidgetProvider() {
    companion object {
        /** 1x1 to wide and tall: cover; cover and title; the full card. */
        val sizes = listOf(
            SizeF(50f, 50f), SizeF(100f, 50f), SizeF(160f, 50f),
            SizeF(100f, 100f), SizeF(100f, 160f), SizeF(160f, 100f), SizeF(250f, 100f),
            SizeF(160f, 150f), SizeF(250f, 150f), SizeF(250f, 250f),
        )
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context, manager, id))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle
    ) {
        manager.updateAppWidget(id, render(context, manager, id))
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val data = HomeWidgets.load(context)
        // One picture of each cover for every size (the launcher's bitmap
        // memory is limited; the same bitmap is sent once).
        val hero = data?.optJSONObject("hero")
        val cover = HomeWidgets.cover(context, hero?.optString("cover"),
            HomeWidgets.dp(context, 280f).roundToInt(), HomeWidgets.dp(context, 18f))
        val nextCover = HomeWidgets.cover(context,
            data?.optJSONObject("next")?.optString("cover"),
            HomeWidgets.dp(context, 33f).roundToInt(), HomeWidgets.dp(context, 4f))
        return responsive(context, manager, id, sizes) { w, h ->
            build(context, data, id, w, h, cover, nextCover)
        }
    }

    /** The card for a widget [width] x [height] dp. */
    private fun build(
        context: Context, data: JSONObject?, id: Int, width: Float, height: Float,
        cover: Bitmap?, nextCover: Bitmap?
    ): RemoteViews {
        // Narrow and tall: the cover on top. Small: the cover alone.
        val tall = width < 160 && height >= 100
        val coverOnly = !tall && (width < 100 || height < 50)
        val views = RemoteViews(context.packageName,
            if (tall) R.layout.widget_continue_reading_tall else R.layout.widget_continue_reading)
        val hero = data?.optJSONObject("hero")
        val labels = data?.optJSONObject("labels")
        views.setOnClickPendingIntent(R.id.widget_root,
            HomeWidgets.openIntent(context, id * 10, hero?.optString("id")?.ifEmpty { null }))
        if (hero == null) {
            views.setViewVisibility(R.id.book, View.GONE)
            views.setViewVisibility(R.id.empty, View.VISIBLE)
            views.setTextViewText(R.id.empty, labels?.optString("empty")
                ?: context.getString(R.string.widget_continue_description))
            return views
        }
        views.setViewVisibility(R.id.book, View.VISIBLE)
        views.setViewVisibility(R.id.empty, View.GONE)
        views.setTextViewText(R.id.title, hero.optString("title"))
        val author = hero.optString("author")
        views.setTextViewText(R.id.author, author)

        if (cover != null) views.setImageViewBitmap(R.id.cover, cover)
        else views.setImageViewResource(R.id.cover, R.drawable.widget_cover_placeholder)
        if (tall) {
            views.setInt(R.id.title, "setMaxLines", if (height >= 160) 2 else 1)
            views.setViewVisibility(R.id.author,
                if (author.isEmpty() || height < 200) View.GONE else View.VISIBLE)
            return views
        }

        views.setViewVisibility(R.id.text_column, if (coverOnly) View.GONE else View.VISIBLE)
        views.setInt(R.id.book, "setGravity", if (coverOnly) Gravity.CENTER else Gravity.START)
        if (coverOnly) return views
        // Short: no label, a one-line title; the author once there is room.
        views.setViewVisibility(R.id.label_pill, if (height >= 100) View.VISIBLE else View.GONE)
        views.setInt(R.id.title, "setMaxLines", if (height >= 100) 2 else 1)
        views.setViewVisibility(R.id.author,
            if (author.isEmpty() || height < 80) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.label, labels?.optString("hero") ?: "")

        val next = data.optJSONObject("next")
        if (next != null && height >= 150) {
            views.setViewVisibility(R.id.next_row, View.VISIBLE)
            views.setTextViewText(R.id.next_label, labels?.optString("nextUp") ?: "")
            views.setTextViewText(R.id.next_title, next.optString("title"))
            if (nextCover != null) views.setImageViewBitmap(R.id.next_cover, nextCover)
            else views.setImageViewResource(R.id.next_cover, R.drawable.widget_cover_placeholder)
            views.setOnClickPendingIntent(R.id.next_row,
                HomeWidgets.openIntent(context, id * 10 + 1, next.optString("id")))
        } else {
            views.setViewVisibility(R.id.next_row, View.GONE)
        }
        return views
    }
}

/** "Reading record": checkpoints, the streak and four weeks of reading. */
class ReadingRecapWidget : AppWidgetProvider() {
    companion object {
        /** 2x1 to tall: checkpoints; with the streak; with the four weeks. */
        val sizes = listOf(
            SizeF(110f, 50f), SizeF(180f, 50f), SizeF(110f, 110f),
            SizeF(180f, 110f), SizeF(250f, 110f), SizeF(180f, 180f),
            SizeF(250f, 180f), SizeF(320f, 180f),
        )
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context, manager, id))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle
    ) {
        manager.updateAppWidget(id, render(context, manager, id))
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val data = HomeWidgets.load(context)
        val progress = data?.optJSONObject("recap")?.optDouble("progress", 0.0) ?: 0.0
        val rings = mutableMapOf<Int, Bitmap>()
        return responsive(context, manager, id, sizes) { w, h ->
            build(context, data, id, w, h) { px ->
                rings.getOrPut(px) { HomeWidgets.ring(context, progress, px) }
            }
        }
    }

    private fun build(
        context: Context, data: JSONObject?, id: Int, width: Float, height: Float,
        ring: (Int) -> Bitmap
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_reading_recap)
        views.setOnClickPendingIntent(R.id.widget_root, HomeWidgets.openIntent(context, id * 10 + 5, null))
        // Narrow: the checkpoints alone; short: no line under the count.
        views.setViewVisibility(R.id.streak_tile, if (width >= 180) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.ring, if (width >= 140 || height >= 110) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.to_next, if (height >= 80) View.VISIBLE else View.GONE)
        val ringPx = HomeWidgets.dp(context, if (height >= 80) 50f else 36f).roundToInt()
        val recap = data?.optJSONObject("recap")
        if (recap == null) {
            views.setViewVisibility(R.id.activity, View.GONE)
            views.setTextViewText(R.id.checkpoints, context.getString(R.string.widget_recap_name))
            views.setTextViewText(R.id.completed, "0")
            views.setTextViewText(R.id.to_next, data?.optJSONObject("labels")?.optString("empty") ?: "")
            views.setTextViewText(R.id.streak, "0")
            views.setTextViewText(R.id.streak_label, "")
            views.setImageViewBitmap(R.id.ring, ring(ringPx))
            views.setImageViewResource(R.id.fire, R.drawable.ic_widget_fire_off)
            return views
        }
        views.setTextViewText(R.id.checkpoints, recap.optString("checkpoints"))
        views.setTextViewText(R.id.completed, recap.optString("completed"))
        views.setTextViewText(R.id.to_next, recap.optString("toNext"))
        views.setImageViewBitmap(R.id.ring, ring(ringPx))
        views.setTextViewText(R.id.streak, recap.optString("streak"))
        views.setTextViewText(R.id.streak_label, recap.optString("streakLabel"))
        views.setImageViewResource(R.id.fire,
            if (recap.optBoolean("streakOn")) R.drawable.ic_widget_fire else R.drawable.ic_widget_fire_off)

        // The activity strip needs about 80dp under the tiles.
        if (height >= 180) {
            views.setViewVisibility(R.id.activity, View.VISIBLE)
            views.setTextViewText(R.id.weeks, recap.optString("weeks"))
            views.setTextViewText(R.id.reading_days, recap.optString("readingDays"))
            val days = recap.optJSONArray("days")
            val list = (0 until (days?.length() ?: 0)).map { days!!.optInt(it) }
            val strip = HomeWidgets.dp(context, (width - 40).coerceAtLeast(120f)).roundToInt()
            views.setImageViewBitmap(R.id.heatmap, HomeWidgets.heatmap(context, list, strip))
        } else {
            views.setViewVisibility(R.id.activity, View.GONE)
        }
        return views
    }
}
