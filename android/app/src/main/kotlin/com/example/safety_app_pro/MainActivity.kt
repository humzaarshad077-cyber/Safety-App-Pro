package com.example.safety_app_pro


import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.telephony.SmsManager
import android.util.Base64
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.safetyapp/native_sms"
    private val CAMERA_REQUEST_CODE = 9901
    private var pendingCameraResult: MethodChannel.Result? = null

    // 🔦 Flashlight Strobe Variables
    private var isStrobeRunning = false
    private var isTorchOn = false
    private val strobeHandler = Handler(Looper.getMainLooper())
    private var strobeRunnable: Runnable? = null

    // 🎤 Voice Note Recorder & Player Variables
    private var mediaRecorder: MediaRecorder? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioFilePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createHighPriorityNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // 1. 📩 NATIVE MULTIPART BACKGROUND SMS (With Dual-SIM & OEM Fallback)
                "sendBackgroundSms" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    if (!phone.isNullOrBlank() && !message.isNullOrBlank()) {
                        try {
                            @Suppress("DEPRECATION")
                            val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                applicationContext.getSystemService(SmsManager::class.java) ?: SmsManager.getDefault()
                            } else {
                                SmsManager.getDefault()
                            }

                            val parts = smsManager.divideMessage(message)
                            if (parts != null && parts.size > 1) {
                                smsManager.sendMultipartTextMessage(phone.trim(), null, parts, null, null)
                            } else {
                                smsManager.sendTextMessage(phone.trim(), null, message, null, null)
                            }
                            result.success("SMS Sent")
                        } catch (e: Exception) {
                            result.error("SMS_ERR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone or message is empty", null)
                    }
                }

                // 2. 🔋 NATIVE BATTERY LEVEL
                "getBatteryLevel" -> {
                    try {
                        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        result.success(if (level in 1..100) level else 100)
                    } catch (e: Exception) {
                        result.success(100)
                    }
                }

                // 3. 🔦 HARDWARE FLASHLIGHT SOS STROBE
                "toggleStrobe" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    toggleFlashlightStrobe(enable)
                    result.success(isStrobeRunning)
                }

                // 4. 🎤 START VOICE NOTE RECORDING
                "startVoiceRecording" -> {
                    try {
                        stopRecordingInternal()
                        stopPlaybackInternal()
                        val outFile = File(cacheDir, "voice_note_temp.m4a")
                        if (outFile.exists()) outFile.delete()
                        audioFilePath = outFile.absolutePath

                        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            MediaRecorder(applicationContext)
                        } else {
                            @Suppress("DEPRECATION")
                            MediaRecorder()
                        }

                        mediaRecorder?.apply {
                            setAudioSource(MediaRecorder.AudioSource.MIC)
                            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            setAudioSamplingRate(16000)
                            setAudioEncodingBitRate(24000)
                            setOutputFile(audioFilePath)
                            prepare()
                            start()
                        }
                        result.success("RECORDING_STARTED")
                    } catch (e: Exception) {
                        result.error("REC_ERR", e.message, null)
                    }
                }

                // 5. 🎤 STOP VOICE RECORDING & RETURN BASE64 AUDIO
                "stopVoiceRecording" -> {
                    try {
                        stopRecordingInternal()
                        val path = audioFilePath
                        if (path != null) {
                            val file = File(path)
                            if (file.exists() && file.length() > 0) {
                                val bytes = file.readBytes()
                                val base64Audio = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                result.success(base64Audio)
                            } else {
                                result.error("EMPTY_FILE", "Recorded file is empty", null)
                            }
                        } else {
                            result.error("NO_FILE", "No recording path found", null)
                        }
                    } catch (e: Exception) {
                        result.error("STOP_REC_ERR", e.message, null)
                    }
                }

                // 6. 🔊 PLAY BASE64 VOICE NOTE (Returns Duration in ms)
                "playVoiceNote" -> {
                    val base64Audio = call.argument<String>("base64Audio")
                    if (!base64Audio.isNullOrEmpty()) {
                        try {
                            stopPlaybackInternal()

                            val audioBytes = Base64.decode(base64Audio, Base64.DEFAULT)
                            val playFile = File(cacheDir, "voice_note_play.m4a")
                            FileOutputStream(playFile).use { it.write(audioBytes) }

                            mediaPlayer = MediaPlayer().apply {
                                setDataSource(playFile.absolutePath)
                                prepare()
                                start()
                            }
                            val durationMs = mediaPlayer?.duration ?: 5000
                            result.success(durationMs)
                        } catch (e: Exception) {
                            result.error("PLAY_ERR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_AUDIO", "Audio data is empty", null)
                    }
                }

                // 7. ⏹️ STOP VOICE NOTE PLAYBACK MID-WAY
                "stopVoicePlayback" -> {
                    stopPlaybackInternal()
                    result.success("STOPPED")
                }

                // 8. 📷 CAPTURE CAMERA PHOTO/SNAPSHOT FOR CHAT
                "captureCameraPhoto" -> {
                    try {
                        pendingCameraResult = result
                        val cameraIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                        startActivityForResult(cameraIntent, CAMERA_REQUEST_CODE)
                    } catch (e: Exception) {
                        pendingCameraResult = null
                        result.error("CAM_ERR", e.message, null)
                    }
                }

                // 9. 📲 SHOW DIRECT HEADS-UP / LOCK-SCREEN POPUP NOTIFICATION
                "showHeadsUpNotification" -> {
                    val title = call.argument<String>("title") ?: "Safety App Pro Alert"
                    val body = call.argument<String>("body") ?: "Tap to view details"
                    showDirectScreenNotification(title, body)
                    result.success("SHOWN")
                }

                else -> result.notImplemented()
            }
        }
    }

    // 📷 Handle Camera Photo Result & Compress to Fast Base64 for Chat
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAMERA_REQUEST_CODE) {
            val res = pendingCameraResult
            pendingCameraResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    @Suppress("DEPRECATION")
                    val bitmap = data.extras?.get("data") as? Bitmap
                    if (bitmap != null) {
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                        val byteArray = stream.toByteArray()
                        val base64Image = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                        res?.success(base64Image)
                    } else {
                        res?.success(null)
                    }
                } catch (e: Exception) {
                    res?.error("IMG_ERR", e.message, null)
                }
            } else {
                res?.success(null)
            }
        }
    }

    // 📲 Create High-Priority Heads-Up Notification Channel (With Sound & Vibration)
    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val channel = NotificationChannel(
                "safety_high_priority_channel",
                "Emergency & Direct Chat Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows instant pop-up alerts on screen even when app is closed"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
                setSound(soundUri, audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun showDirectScreenNotification(title: String, body: String) {
        try {
            createHighPriorityNotificationChannel()
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                (System.currentTimeMillis() % 10000).toInt(),
                intent,
                pendingIntentFlags
            )

            val builder = NotificationCompat.Builder(this, "safety_high_priority_channel")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, true)

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify((System.currentTimeMillis() % 10000).toInt(), builder.build())
        } catch (_: Exception) {}
    }

    private fun stopPlaybackInternal() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    private fun stopRecordingInternal() {
        try {
            mediaRecorder?.stop()
        } catch (_: Exception) {}
        try {
            mediaRecorder?.release()
        } catch (_: Exception) {}
        mediaRecorder = null
    }

    private fun toggleFlashlightStrobe(enable: Boolean) {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        strobeRunnable?.let { strobeHandler.removeCallbacks(it) }

        if (!enable) {
            isStrobeRunning = false
            isTorchOn = false
            try {
                val cameraId = cameraManager.cameraIdList.firstOrNull()
                if (cameraId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    cameraManager.setTorchMode(cameraId, false)
                }
            } catch (_: Exception) {}
            return
        }

        isStrobeRunning = true
        strobeRunnable = object : Runnable {
            override fun run() {
                if (!isStrobeRunning) return
                try {
                    val cameraId = cameraManager.cameraIdList.firstOrNull()
                    if (cameraId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        isTorchOn = !isTorchOn
                        cameraManager.setTorchMode(cameraId, isTorchOn)
                    }
                } catch (_: Exception) {}
                strobeHandler.postDelayed(this, 250)
            }
        }
        strobeHandler.post(strobeRunnable!!)
    }
}