package com.sriharan.gps_mock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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

class MockingService : Service() {
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)
    private var targetLat: Double = 0.0
    private var targetLng: Double = 0.0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        targetLat = intent?.getDoubleExtra(EXTRA_LAT, 0.0) ?: 0.0
        targetLng = intent?.getDoubleExtra(EXTRA_LNG, 0.0) ?: 0.0

        val channelId = "mock_gps_channel"
        val channelName = "Mock GPS Service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Mock GPS Active")
            .setContentText("Mocking Location: $targetLat, $targetLng")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()

        startForeground(1, notification)

        startMocking()

        return START_STICKY
    }

    private fun startMocking() {
        job?.cancel()
        job = scope.launch {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providerName = LocationManager.GPS_PROVIDER

            try {
                // Using API matching the old app's params where possible or standard defaults
                 locationManager.addTestProvider(
                    providerName,
                    false, // requiresNetwork
                    false, // requiresSatellite
                    false, // requiresCell
                    false, // hasMonetaryCost
                    true,  // supportsAltitude
                    true,  // supportsSpeed
                    true,  // supportsBearing
                    ProviderProperties.POWER_USAGE_LOW, // powerRequirement
                    ProviderProperties.ACCURACY_FINE // accuracy
                )
            } catch (e: Exception) {
                // Provider might already exist or not allowed
            }

            try {
                locationManager.setTestProviderEnabled(providerName, true)
            } catch (e: Exception) {
               // Ignore
            }

            while (isActive) {
                val mockLocation = Location(providerName).apply {
                    latitude = targetLat
                    longitude = targetLng
                    altitude = 10.0
                    time = System.currentTimeMillis()
                    speed = 0.0f
                    bearing = 0.0f
                    accuracy = 1.0f
                    elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                         bearingAccuracyDegrees = 0.1f
                         verticalAccuracyMeters = 0.1f
                         speedAccuracyMetersPerSecond = 0.1f
                    }
                }
                try {
                    locationManager.setTestProviderLocation(providerName, mockLocation)
                } catch (e: Exception) {
                    // Likely permission missing or not set as mock app
                }
                delay(1000)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        job?.cancel()
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
           locationManager.removeTestProvider(LocationManager.GPS_PROVIDER)
        } catch (e: Exception) {}
    }

    companion object {
        const val ACTION_STOP = "STOP_MOCKING"
        const val EXTRA_LAT = "LATITUDE"
        const val EXTRA_LNG = "LONGITUDE"
    }
}
