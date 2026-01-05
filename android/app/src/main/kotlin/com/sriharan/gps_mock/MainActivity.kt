package com.sriharan.gps_mock

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.mockgps/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startMocking") {
                val lat = call.argument<Double>("lat")
                val lng = call.argument<Double>("lng")
                if (lat != null && lng != null) {
                    val intent = Intent(this, MockingService::class.java)
                    intent.putExtra(MockingService.EXTRA_LAT, lat)
                    intent.putExtra(MockingService.EXTRA_LNG, lng)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Lat/Lng missing", null)
                }
            } else if (call.method == "stopMocking") {
                val intent = Intent(this, MockingService::class.java)
                intent.action = MockingService.ACTION_STOP
                startService(intent)
                result.success(null)
            } else if (call.method == "openDeveloperSettings") {
                try {
                    startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
                    result.success(null)
                } catch (e: Exception) {
                    // Fallback to generic settings if dev settings intent not found
                    startActivity(Intent(android.provider.Settings.ACTION_SETTINGS))
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
