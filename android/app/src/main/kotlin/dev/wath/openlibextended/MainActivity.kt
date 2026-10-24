package dev.wath.openlibextended

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var widgetChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = HomeWidgets.actionOf(intent) ?: return
        setIntent(intent)
        widgetChannel?.invokeMethod("widgetAction", action)
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "lightlib/background_translation")
        this.channel = channel
        val widgets = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lightlib/widgets")
        widgetChannel = widgets
        widgets.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val snapshot = call.argument<String>("snapshot")
                    if (snapshot != null) HomeWidgets.save(applicationContext, snapshot)
                    result.success(null)
                }
                "takeLaunchAction" -> {
                    result.success(HomeWidgets.actionOf(intent))
                    // Acted on once; a configuration change must not reopen it.
                    intent?.action = null
                }
                else -> result.notImplemented()
            }
        }
        val main = Handler(Looper.getMainLooper())
        BackgroundTranslationService.listener = { event ->
            main.post { this.channel?.invokeMethod(event, null) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    val values = Bundle().apply {
                        putString("title", call.argument<String>("title"))
                        putString("text", call.argument<String>("text"))
                        putString("subText", call.argument<String>("subText"))
                        putString("pauseLabel", call.argument<String>("pauseLabel"))
                        putInt("progress", call.argument<Int>("progress") ?: 0)
                        putInt("max", call.argument<Int>("max") ?: 0)
                        putBoolean("indeterminate", call.argument<Boolean>("indeterminate") ?: false)
                    }
                    val running = BackgroundTranslationService.instance
                    if (running != null) {
                        running.update(values)
                        result.success(true)
                    } else if (call.method == "start") {
                        result.success(start(values, call.argument<String>("channelName") ?: "Translation"))
                    } else {
                        result.success(false)
                    }
                }
                "stop" -> {
                    BackgroundTranslationService.instance?.finish(
                        call.argument<String>("doneTitle"), call.argument<String>("doneText"))
                    result.success(null)
                }
                "deviceState" -> result.success(deviceState())
                "isMetered" -> result.success(
                    (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                        .isActiveNetworkMetered)
                "lastExits" -> Thread {
                    val exits = try { lastExits() } catch (e: Exception) { emptyList() }
                    main.post { result.success(exits) }
                }.start()
                else -> result.notImplemented()
            }
        }
    }

    private fun start(values: Bundle, channelName: String): Boolean {
        BackgroundTranslationService.ensureChannel(this, channelName)
        val intent = Intent(this, BackgroundTranslationService::class.java)
            .setAction(BackgroundTranslationService.ACTION_UPDATE)
            .putExtras(values)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (e: Exception) {
            // Not allowed from the background (Android 12+): the books
            // then wait until the app is open again.
            false
        }
    }

    private fun deviceState(): Map<String, Any> {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return mapOf(
            "thermal" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                power.currentThermalStatus else 0),
            "powerSave" to power.isPowerSaveMode,
            "battery" to (if (level >= 0 && scale > 0) level * 100 / scale else 100),
            "charging" to (plugged || status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL),
        )
    }

    /// How the app's last few processes ended (Android 11+): a native crash,
    /// the system killing it for memory, an ANR... with the crash's abort
    /// message and backtrace lines when Android kept them. A crash inside a
    /// native library (the translation engine) leaves nothing in the app's
    /// own log, which lives in memory.
    private fun lastExits(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val updated = try {
            packageManager.getPackageInfo(packageName, 0).lastUpdateTime
        } catch (e: Exception) { 0L }
        return am.getHistoricalProcessExitReasons(packageName, 0, 5).map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                // Ended in an older version of the app.
                "beforeUpdate" to (info.timestamp < updated),
                "reason" to reasonName(info.reason),
                "description" to info.description,
                "status" to info.status,
                "importance" to info.importance,
                "pssKb" to info.pss,
                "rssKb" to info.rss,
                "trace" to traceOf(info),
            )
        }
    }

    private fun traceOf(info: ApplicationExitInfo): String? {
        if (info.reason != ApplicationExitInfo.REASON_CRASH_NATIVE &&
            info.reason != ApplicationExitInfo.REASON_ANR) return null
        val bytes = try {
            info.traceInputStream?.use { it.readBytes() }
        } catch (e: Exception) { null } ?: return null
        // Native crashes come as a tombstone protobuf: its readable strings
        // (signal, abort message, frames' libraries and functions) suffice.
        val lines = Regex("[\\x20-\\x7e]{6,}")
            .findAll(String(bytes, Charsets.ISO_8859_1))
            .map { it.value.trim() }
            .filter { line ->
                info.reason == ApplicationExitInfo.REASON_ANR ||
                    line.contains(".so") || line.contains("SIG") ||
                    line.contains("abort", ignoreCase = true) ||
                    line.contains("fault", ignoreCase = true) ||
                    line.contains("Check failed") || line.contains("error", ignoreCase = true)
            }
            .distinct()
            .take(60)
            .joinToString("\n")
        return if (lines.length > 6000) lines.substring(0, 6000) else lines
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "unknown_$reason"
    }

    override fun onDestroy() {
        // The Dart code that drives the service ends with the activity.
        if (isFinishing) BackgroundTranslationService.instance?.finish(null, null)
        BackgroundTranslationService.listener = null
        channel?.setMethodCallHandler(null)
        channel = null
        widgetChannel?.setMethodCallHandler(null)
        widgetChannel = null
        super.onDestroy()
    }
}
