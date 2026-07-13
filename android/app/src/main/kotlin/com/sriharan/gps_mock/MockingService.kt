package com.sriharan.gps_mock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject

class MockingService : Service() {
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopMocking()
            return START_NOT_STICKY
        }

        // A null intent means the system restarted us (START_STICKY). Resume
        // the persisted command instead of mocking lat/lng 0,0.
        val command = commandFromIntent(intent) ?: MockStateStore.getActiveCommand(this)
        if (command == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        MockStateStore.setActiveCommand(this, command)
        startForeground(NOTIFICATION_ID, buildNotification(notificationText(command)))
        startFixedMocking(command)
        return START_STICKY
    }

    private fun commandFromIntent(intent: Intent?): JSONObject? {
        intent ?: return null
        if (!intent.hasExtra(EXTRA_LAT) || !intent.hasExtra(EXTRA_LNG)) return null
        return JSONObject().apply {
            put("mode", MODE_FIXED)
            put("lat", intent.getDoubleExtra(EXTRA_LAT, 0.0))
            put("lng", intent.getDoubleExtra(EXTRA_LNG, 0.0))
            put("label", intent.getStringExtra(EXTRA_LABEL) ?: "")
            put("favoriteId", intent.getStringExtra(EXTRA_FAVORITE_ID) ?: "")
        }
    }

    private fun notificationText(command: JSONObject): String {
        val label = command.optString("label")
        if (label.isNotEmpty()) return label
        return "${command.optDouble("lat")}, ${command.optDouble("lng")}"
    }

    private fun buildNotification(text: String, title: String = "Mock GPS Active"): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Mock GPS Service", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        val openAppIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, MockingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent
            )
            .build()
    }

    private fun updateNotification(text: String, title: String = "Mock GPS Active") {
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, buildNotification(text, title))
    }

    private fun startFixedMocking(command: JSONObject) {
        val lat = command.getDouble("lat")
        val lng = command.getDouble("lng")
        val label = command.optString("label")
        val favoriteId = command.optString("favoriteId")

        job?.cancel()
        job = scope.launch {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            installTestProvider(locationManager)

            while (isActive) {
                pushMockLocation(locationManager, lat, lng, bearing = 0f, speedMps = 0f)
                status = mapOf(
                    "active" to true,
                    "mode" to MODE_FIXED,
                    "lat" to lat,
                    "lng" to lng,
                    "label" to label,
                    "favoriteId" to favoriteId,
                    "progress" to 0.0,
                    "remainingSeconds" to 0,
                    "bearing" to 0.0,
                    "arrived" to false,
                )
                delay(1000)
            }
        }
    }

    private fun installTestProvider(locationManager: LocationManager) {
        try {
            locationManager.addTestProvider(
                PROVIDER,
                false, // requiresNetwork
                false, // requiresSatellite
                false, // requiresCell
                false, // hasMonetaryCost
                true,  // supportsAltitude
                true,  // supportsSpeed
                true,  // supportsBearing
                ProviderProperties.POWER_USAGE_LOW,
                ProviderProperties.ACCURACY_FINE
            )
        } catch (e: Exception) {
            // Provider might already exist or not allowed
        }
        try {
            locationManager.setTestProviderEnabled(PROVIDER, true)
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun pushMockLocation(
        locationManager: LocationManager,
        lat: Double,
        lng: Double,
        bearing: Float,
        speedMps: Float,
    ) {
        val mockLocation = Location(PROVIDER).apply {
            latitude = lat
            longitude = lng
            altitude = 10.0
            time = System.currentTimeMillis()
            speed = speedMps
            this.bearing = bearing
            accuracy = 1.0f
            elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                bearingAccuracyDegrees = 0.1f
                verticalAccuracyMeters = 0.1f
                speedAccuracyMetersPerSecond = 0.1f
            }
        }
        try {
            locationManager.setTestProviderLocation(PROVIDER, mockLocation)
        } catch (e: Exception) {
            // Likely permission missing or not selected as the mock app
        }
    }

    private fun stopMocking() {
        MockStateStore.setActiveCommand(this, null)
        status = null
        job?.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        job?.cancel()
        status = null
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            locationManager.removeTestProvider(PROVIDER)
        } catch (e: Exception) {}
    }

    companion object {
        const val ACTION_STOP = "STOP_MOCKING"
        const val ACTION_START_FIXED = "START_FIXED_MOCKING"
        const val ACTION_START_ROUTE = "START_ROUTE_MOCKING"
        const val EXTRA_LAT = "LATITUDE"
        const val EXTRA_LNG = "LONGITUDE"
        const val EXTRA_LABEL = "LABEL"
        const val EXTRA_FAVORITE_ID = "FAVORITE_ID"
        const val EXTRA_ROUTE_FILE = "ROUTE_FILE"
        const val EXTRA_DURATION_SECONDS = "DURATION_SECONDS"
        const val MODE_FIXED = "fixed"
        const val MODE_ROUTE = "route"
        private const val PROVIDER = LocationManager.GPS_PROVIDER
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "mock_gps_channel"

        @Volatile
        private var status: Map<String, Any?>? = null

        /** Snapshot for the getMockStatus channel call and for tiles/widgets. */
        fun statusMap(): Map<String, Any?> = status ?: mapOf("active" to false)

        fun activeFavoriteId(): String? =
            (status?.get("favoriteId") as? String)?.takeIf { it.isNotEmpty() }
    }
}
