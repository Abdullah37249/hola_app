package com.holaprofessional.hola_professional

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Gives Dart the app-private files directory for the on-device database.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hola/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
