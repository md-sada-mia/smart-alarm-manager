package com.smart_alarm_manager.smart_alarm_manager

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.smart_alarm_manager/settings"
    private val REQUEST_CODE_PICK_RINGTONE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var currentRingtone: android.media.Ringtone? = null
    private var alarmRingtone: android.media.Ringtone? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Only set flags if launched with show_on_lock extra (from alarm trigger)
        val showOnLock = intent.getBooleanExtra("show_on_lock", false)
        if (showOnLock) {
            setLockScreenFlags(true)
        }
    }

    private fun setLockScreenFlags(enable: Boolean) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enable)
            setTurnScreenOn(enable)
        }
        
        if (enable) {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        } else {
            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickSystemRingtone") {
                if (pendingResult != null) {
                    result.error("PENDING_RESULT", "A ringtone picker is already active", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                intent.putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                intent.putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select Alarm Tone")
                intent.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, null as Uri?)
                startActivityForResult(intent, REQUEST_CODE_PICK_RINGTONE)
            } else if (call.method == "bringToForeground") {
                val intent = Intent(context, MainActivity::class.java)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(intent)
                result.success(true)
            } else if (call.method == "toggleLockScreenVisible") {
                val enable = call.argument<Boolean>("enable") ?: false
                setLockScreenFlags(enable)
                result.success(true)
            } else if (call.method == "playSystemRingtone") {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    try {
                        val uri = Uri.parse(uriString)
                        val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                        currentRingtone?.stop() // Stop existing
                        currentRingtone = ringtone
                        ringtone.play()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.message, null)
                    }
                } else {
                     result.error("INVALID_URI", "URI is null", null)
                }
            } else if (call.method == "stopSystemRingtone") {
                currentRingtone?.stop()
                currentRingtone = null
                result.success(true)
            } else if (call.method == "playAlarmSound") {
                val uriString = call.argument<String>("uri")
                try {
                    val uri = if (uriString != null) {
                        Uri.parse(uriString)
                    } else {
                        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    }
                    val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                    alarmRingtone?.stop() // Stop existing alarm
                    alarmRingtone = ringtone
                    ringtone.isLooping = true // Enable looping for alarm
                    ringtone.play()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY_ALARM_ERROR", e.message, null)
                }
            } else if (call.method == "stopAlarmSound") {
                alarmRingtone?.stop()
                alarmRingtone = null
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_RINGTONE && pendingResult != null) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                if (uri != null) {
                    pendingResult?.success(uri.toString())
                } else {
                    // User chose "Silent" or nothing
                    pendingResult?.success(null)
                }
            } else {
                // Cancelled
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
