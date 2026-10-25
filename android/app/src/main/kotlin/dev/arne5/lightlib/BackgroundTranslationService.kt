package dev.arne5.lightlib

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app process alive while library books are translated in the
 * background, with an ongoing notification that shows the progress.
 *
 * The translation itself runs in the app's Dart code; this service only
 * holds the process in the foreground state, a partial wake lock that
 * expires on its own if updates stop, and the notification. Dart drives it
 * through [MainActivity]'s method channel.
 */
class BackgroundTranslationService : Service() {
    companion object {
        const val CHANNEL_ID = "background_translation"
        const val NOTIFICATION_ID = 7301
        const val DONE_NOTIFICATION_ID = 7302
        const val ACTION_UPDATE = "dev.arne5.lightlib.translation.UPDATE"
        const val ACTION_PAUSE = "dev.arne5.lightlib.translation.PAUSE"

        // Re-acquired on every update; lapses if the Dart side goes quiet.
        private const val WAKE_LOCK_MS = 10 * 60 * 1000L

        @Volatile
        var instance: BackgroundTranslationService? = null
            private set

        /** Events for Dart: "pauseRequested", "timedOut". */
        @Volatile
        var listener: ((String) -> Unit)? = null

        fun ensureChannel(context: Context, name: String) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var started = false
    private var extras: Bundle = Bundle()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> {
                listener?.invoke("pauseRequested")
                return START_NOT_STICKY
            }
            else -> update(intent?.extras ?: extras)
        }
        // Not restarted by the system: without the app's Dart code there
        // is nothing to run.
        return START_NOT_STICKY
    }

    /** Shows [values] (title, text, subText, progress, max, indeterminate). */
    fun update(values: Bundle) {
        extras = values
        val notification = build(values)
        if (!started) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            started = true
        } else {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification)
        }
        holdWakeLock()
    }

    private fun build(values: Bundle): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val immutable = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        if (open != null) {
            builder.setContentIntent(PendingIntent.getActivity(this, 0, open, immutable))
        }
        val pause = Intent(this, BackgroundTranslationService::class.java).setAction(ACTION_PAUSE)
        val pauseLabel = values.getString("pauseLabel")
        if (!pauseLabel.isNullOrEmpty()) {
            @Suppress("DEPRECATION")
            builder.addAction(Notification.Action.Builder(
                R.drawable.ic_stat_translate, pauseLabel,
                PendingIntent.getService(this, 1, pause, immutable)).build())
        }
        val max = values.getInt("max", 0)
        builder
            .setSmallIcon(R.drawable.ic_stat_translate)
            .setContentTitle(values.getString("title") ?: "")
            .setContentText(values.getString("text") ?: "")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setProgress(max, values.getInt("progress", 0),
                values.getBoolean("indeterminate", max == 0))
        values.getString("subText")?.let { builder.setSubText(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun holdWakeLock() {
        val lock = wakeLock ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LightLib:BackgroundTranslation")
            .also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
        lock.acquire(WAKE_LOCK_MS)
    }

    /** Ends the service; [doneTitle] posts a dismissible "finished" notice. */
    fun finish(doneTitle: String?, doneText: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        if (!doneTitle.isNullOrEmpty()) postDone(doneTitle, doneText)
        stopSelf()
    }

    private fun postDone(title: String, text: String?) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) {
            builder.setContentIntent(PendingIntent.getActivity(this, 2, open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        }
        builder.setSmallIcon(R.drawable.ic_stat_translate)
            .setContentTitle(title)
            .setAutoCancel(true)
        text?.let { builder.setContentText(it) }
        getSystemService(NotificationManager::class.java)
            .notify(DONE_NOTIFICATION_ID, builder.build())
    }

    // Android 15 limits data-sync services to 6 hours a day: stop cleanly
    // and let Dart pause until the app is opened again.
    override fun onTimeout(startId: Int, fgsType: Int) {
        listener?.invoke("timedOut")
        finish(null, null)
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        instance = null
        started = false
        super.onDestroy()
    }
}
