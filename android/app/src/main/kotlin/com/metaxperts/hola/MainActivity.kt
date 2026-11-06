package com.metaxperts.hola

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity: Android's fingerprint prompt (local_auth) needs it.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // HOLA's server sends every push on "hola_default" with high priority.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("hola_default", "HOLA notifications", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Orders, bookings, training and support updates"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Gives Dart the app-private files directory for the on-device database.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hola/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                // Saves a file (e.g. a certificate PDF) to the public Downloads folder.
                "saveToDownloads" -> try {
                    val bytes = call.argument<ByteArray>("bytes")!!
                    val name = call.argument<String>("name")!!
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    result.success(saveToDownloads(bytes, name, mime))
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Android 10+: MediaStore (no permission). Older: the Downloads directory.
    private fun saveToDownloads(bytes: ByteArray, name: String, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/HOLA")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IllegalStateException("No Downloads folder")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return "Download/HOLA/$name"
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "HOLA").apply { mkdirs() }
        File(dir, name).writeBytes(bytes)
        return "Download/HOLA/$name"
    }
}
