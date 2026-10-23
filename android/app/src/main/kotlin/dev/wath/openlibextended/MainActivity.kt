package dev.wath.openlibextended

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "lightlib/background_translation")
        this.channel = channel
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

    override fun onDestroy() {
        // The Dart code that drives the service ends with the activity.
        if (isFinishing) BackgroundTranslationService.instance?.finish(null, null)
        BackgroundTranslationService.listener = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
