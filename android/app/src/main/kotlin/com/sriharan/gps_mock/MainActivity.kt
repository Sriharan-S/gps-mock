package com.sriharan.gps_mock

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mockgps/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMocking" -> {
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    if (lat != null && lng != null) {
                        val intent = Intent(this, MockingService::class.java).apply {
                            action = MockingService.ACTION_START_FIXED
                            putExtra(MockingService.EXTRA_LAT, lat)
                            putExtra(MockingService.EXTRA_LNG, lng)
                            putExtra(MockingService.EXTRA_LABEL, call.argument<String>("label"))
                            putExtra(MockingService.EXTRA_FAVORITE_ID, call.argument<String>("favoriteId"))
                        }
                        startMockingService(intent)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "Lat/Lng missing", null)
                    }
                }
                "startRoute" -> {
                    val routeFile = call.argument<String>("routeFile")
                    val durationSeconds = call.argument<Int>("durationSeconds")
                    if (routeFile != null && durationSeconds != null && durationSeconds > 0) {
                        val intent = Intent(this, MockingService::class.java).apply {
                            action = MockingService.ACTION_START_ROUTE
                            putExtra(MockingService.EXTRA_ROUTE_FILE, routeFile)
                            putExtra(MockingService.EXTRA_DURATION_SECONDS, durationSeconds)
                            putExtra(MockingService.EXTRA_LABEL, call.argument<String>("label"))
                        }
                        startMockingService(intent)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "routeFile/durationSeconds missing", null)
                    }
                }
                "stopMocking" -> {
                    val intent = Intent(this, MockingService::class.java)
                    intent.action = MockingService.ACTION_STOP
                    startService(intent)
                    result.success(null)
                }
                "getMockStatus" -> result.success(MockingService.statusMap())
                "isMockLocationApp" -> result.success(isMockLocationApp())
                "syncFavorites" -> {
                    val json = call.argument<String>("json")
                    if (json != null) {
                        MockStateStore.setFavoritesJson(this, json)
                    }
                    result.success(null)
                }
                "openDeveloperSettings" -> {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        // Fallback to generic settings if dev settings intent not found
                        startActivity(Intent(android.provider.Settings.ACTION_SETTINGS))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startMockingService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /** True when this app is selected as the mock location app in
     *  Developer Options. */
    private fun isMockLocationApp(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }
}
