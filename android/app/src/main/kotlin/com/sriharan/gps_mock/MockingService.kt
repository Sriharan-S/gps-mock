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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.core.app.NotificationCompat
import com.sriharan.gps_mock.tiles.BaseFavoriteTileService
import com.sriharan.gps_mock.widgets.FavoriteWidgetProvider
import com.sriharan.gps_mock.widgets.NavigationWidgetProvider
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.tan

class MockingService : Service() {
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    @Volatile
    private var pushFailureAlerted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // Callers may use startForegroundService for the stop command
            // (e.g. quick-settings tiles); honor the contract by entering
            // the foreground before tearing down.
            startForeground(NOTIFICATION_ID, buildNotification("Stopping mock location"))
            stopMocking()
            return START_NOT_STICKY
        }

        // A null intent means the system restarted us (START_STICKY). Resume
        // the persisted command instead of mocking lat/lng 0,0.
        val freshCommand = commandFromIntent(intent)
        val command = freshCommand ?: MockStateStore.getActiveCommand(this)
        if (command == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        pushFailureAlerted = false
        if (freshCommand != null) MockStateStore.recordStart(this, freshCommand)
        MockStateStore.setActiveCommand(this, command)
        startForeground(NOTIFICATION_ID, buildNotification(notificationText(command)))
        when (command.optString("mode", MODE_FIXED)) {
            MODE_ROUTE -> startRouteMocking(command)
            else -> {
                startFixedMocking(command)
                NavigationWidgetProvider.pushIdle(this)
            }
        }
        BaseFavoriteTileService.refreshAll(this)
        FavoriteWidgetProvider.refreshAll(this)
        return START_STICKY
    }

    private fun commandFromIntent(intent: Intent?): JSONObject? {
        intent ?: return null
        if (intent.action == ACTION_START_ROUTE) {
            val routeFile = intent.getStringExtra(EXTRA_ROUTE_FILE) ?: return null
            val durationSeconds = intent.getIntExtra(EXTRA_DURATION_SECONDS, 0)
            if (durationSeconds <= 0) return null
            return JSONObject().apply {
                put("mode", MODE_ROUTE)
                put("routeFile", routeFile)
                put("durationSeconds", durationSeconds)
                put("label", intent.getStringExtra(EXTRA_LABEL) ?: "")
                put("fromLabel", intent.getStringExtra(EXTRA_FROM_LABEL) ?: "")
                put("toLabel", intent.getStringExtra(EXTRA_TO_LABEL) ?: "")
                put("distanceMeters", intent.getDoubleExtra(EXTRA_DISTANCE_METERS, 0.0))
            }
        }
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
        if (command.optString("mode") == MODE_ROUTE) return "Simulating route"
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

    // ------------------------------------------------------------ fixed mode

    private fun startFixedMocking(command: JSONObject) {
        val lat = command.getDouble("lat")
        val lng = command.getDouble("lng")
        val label = command.optString("label")
        val favoriteId = command.optString("favoriteId")

        // Publish immediately so getMockStatus reflects the new state without
        // waiting for the first tick.
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

        job?.cancel()
        job = scope.launch {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            installTestProvider(locationManager)

            while (isActive) {
                pushMockLocation(locationManager, lat, lng, bearing = 0f, speedMps = 0f)
                delay(1000)
            }
        }
    }

    // ------------------------------------------------------------ route mode

    private fun startRouteMocking(command: JSONObject) {
        val routeFile = command.optString("routeFile")
        val durationSeconds = command.optInt("durationSeconds", 0)
        val label = command.optString("label")

        val points = loadRoutePoints(routeFile)
        if (points.size < 2 || durationSeconds <= 0) {
            postAlert(
                "Mock route stopped",
                "The route data could not be loaded. Open GPS Mock and start the route again."
            )
            stopMocking()
            return
        }

        // Remember when the route began so a sticky restart resumes mid-route
        // instead of starting over.
        if (!command.has("startedAtMillis")) {
            command.put("startedAtMillis", System.currentTimeMillis())
            MockStateStore.setActiveCommand(this, command)
        }
        val startedAtMillis = command.getLong("startedAtMillis")

        // Precompute cumulative distances along the polyline.
        val cumulative = DoubleArray(points.size)
        for (i in 1 until points.size) {
            cumulative[i] = cumulative[i - 1] + distanceMeters(points[i - 1], points[i])
        }
        val totalDistance = cumulative.last()
        if (totalDistance <= 0.0) {
            stopMocking()
            return
        }
        val cruiseSpeed = (totalDistance / durationSeconds).toFloat()

        publishRouteStatus(
            points.first(), label, 0.0, durationSeconds, 0f, cruiseSpeed, false, routeFile
        )

        job?.cancel()
        job = scope.launch {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            installTestProvider(locationManager)

            var tick = 0
            var arrivalRecorded = false
            while (isActive) {
                val elapsed = (System.currentTimeMillis() - startedAtMillis) / 1000.0
                val fraction = (elapsed / durationSeconds).coerceIn(0.0, 1.0)
                val arrived = fraction >= 1.0
                if (arrived && !arrivalRecorded) {
                    arrivalRecorded = true
                    MockStateStore.recordArrived(this@MockingService)
                }
                val (position, bearing) = positionAlongRoute(
                    points, cumulative, totalDistance * fraction
                )
                val speed = if (arrived) 0f else cruiseSpeed
                pushMockLocation(locationManager, position[0], position[1], bearing, speed)

                val remaining = (durationSeconds - elapsed).coerceAtLeast(0.0).toInt()
                publishRouteStatus(
                    position, label, fraction, remaining, bearing, speed, arrived, routeFile
                )

                if (arrived) {
                    if (tick % 60 == 0) {
                        updateNotification("$label · arrived, holding position", "Mock route finished")
                    }
                } else if (tick % 5 == 0) {
                    updateNotification(
                        "$label · ${formatRemaining(remaining)} left", "Mock route active"
                    )
                }

                // Keep the navigation home-screen widget fresh (progress +
                // map snapshot) roughly every 15 seconds while running.
                if (tick % 15 == 0 && NavigationWidgetProvider.hasWidgets(this@MockingService)) {
                    val snapshot = fetchStaticMapBitmap(position[0], position[1])
                    NavigationWidgetProvider.push(this@MockingService, statusMap(), snapshot)
                }

                tick++
                delay(1000)
            }
        }
    }

    /** Composes a small map image centred on the mock position for the
     *  navigation widget by stitching OpenStreetMap tiles — completely free,
     *  no API key. Returns null when the network fails; the widget then
     *  shows text-only progress. */
    private fun fetchStaticMapBitmap(lat: Double, lng: Double): Bitmap? {
        return try {
            val zoom = 15
            val worldTiles = 1 shl zoom
            val xTile = (lng + 180.0) / 360.0 * worldTiles
            val latRad = Math.toRadians(lat)
            val yTile = (1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * worldTiles

            val width = 400
            val height = 220
            val left = xTile * TILE_SIZE - width / 2.0
            val top = yTile * TILE_SIZE - height / 2.0

            val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            canvas.drawColor(Color.parseColor("#FF1E1E2E"))

            var drewAny = false
            for (tx in floor(left / TILE_SIZE).toInt()..floor((left + width - 1) / TILE_SIZE).toInt()) {
                for (ty in floor(top / TILE_SIZE).toInt()..floor((top + height - 1) / TILE_SIZE).toInt()) {
                    if (ty < 0 || ty >= worldTiles) continue
                    val wrappedX = ((tx % worldTiles) + worldTiles) % worldTiles
                    val tile = fetchOsmTile(zoom, wrappedX, ty) ?: continue
                    drewAny = true
                    canvas.drawBitmap(
                        tile,
                        (tx * TILE_SIZE - left).toFloat(),
                        (ty * TILE_SIZE - top).toFloat(),
                        null
                    )
                }
            }
            if (!drewAny) return null

            // Marker dot at the mock position (the exact canvas centre).
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.color = Color.parseColor("#FF6C63FF")
            canvas.drawCircle(width / 2f, height / 2f, 10f, paint)
            paint.color = Color.WHITE
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 3f
            canvas.drawCircle(width / 2f, height / 2f, 10f, paint)
            output
        } catch (e: Exception) {
            null
        }
    }

    /** Fetches one OSM tile, with a small in-memory cache — successive
     *  widget refreshes mostly reuse the same tiles as the position moves. */
    private fun fetchOsmTile(zoom: Int, x: Int, y: Int): Bitmap? {
        val key = "$zoom/$x/$y"
        synchronized(tileCache) { tileCache[key]?.let { return it } }
        return try {
            val url = URL("https://tile.openstreetmap.org/$zoom/$x/$y.png")
            val connection = url.openConnection() as HttpURLConnection
            connection.setRequestProperty("User-Agent", OSM_USER_AGENT)
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            val bitmap = connection.inputStream.use { BitmapFactory.decodeStream(it) }
            if (bitmap != null) {
                synchronized(tileCache) { tileCache[key] = bitmap }
            }
            bitmap
        } catch (e: Exception) {
            null
        }
    }

    private val tileCache = object : LinkedHashMap<String, Bitmap>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Bitmap>?): Boolean =
            size > 12
    }

    private fun publishRouteStatus(
        position: DoubleArray,
        label: String,
        progress: Double,
        remainingSeconds: Int,
        bearing: Float,
        speedMps: Float,
        arrived: Boolean,
        routeFile: String,
    ) {
        status = mapOf(
            "active" to true,
            "mode" to MODE_ROUTE,
            "lat" to position[0],
            "lng" to position[1],
            "label" to label,
            "favoriteId" to "",
            "progress" to progress,
            "remainingSeconds" to remainingSeconds,
            "bearing" to bearing.toDouble(),
            "speedMps" to speedMps.toDouble(),
            "arrived" to arrived,
            "routeFile" to routeFile,
        )
    }

    /** Reads a JSON array of [lat, lng] pairs written by the Flutter side. */
    private fun loadRoutePoints(path: String): List<DoubleArray> {
        return try {
            val array = JSONArray(File(path).readText())
            (0 until array.length()).mapNotNull { index ->
                val pair = array.optJSONArray(index) ?: return@mapNotNull null
                if (pair.length() < 2) return@mapNotNull null
                doubleArrayOf(pair.getDouble(0), pair.getDouble(1))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Interpolates the position [targetMeters] along the polyline and the
     *  bearing of the segment it falls on. */
    private fun positionAlongRoute(
        points: List<DoubleArray>,
        cumulative: DoubleArray,
        targetMeters: Double,
    ): Pair<DoubleArray, Float> {
        if (targetMeters <= 0.0) {
            return points[0] to bearingDegrees(points[0], points[1])
        }
        if (targetMeters >= cumulative.last()) {
            val last = points.size - 1
            return points[last] to bearingDegrees(points[last - 1], points[last])
        }

        var index = cumulative.toList().binarySearch { it.compareTo(targetMeters) }
        if (index < 0) index = -index - 1
        if (index <= 0) index = 1

        val segmentStart = cumulative[index - 1]
        val segmentLength = cumulative[index] - segmentStart
        val t = if (segmentLength <= 0.0) 0.0 else (targetMeters - segmentStart) / segmentLength
        val from = points[index - 1]
        val to = points[index]
        val position = doubleArrayOf(
            from[0] + (to[0] - from[0]) * t,
            from[1] + (to[1] - from[1]) * t,
        )
        return position to bearingDegrees(from, to)
    }

    private fun distanceMeters(from: DoubleArray, to: DoubleArray): Double {
        val results = FloatArray(1)
        Location.distanceBetween(from[0], from[1], to[0], to[1], results)
        return results[0].toDouble()
    }

    private fun bearingDegrees(from: DoubleArray, to: DoubleArray): Float {
        val results = FloatArray(2)
        Location.distanceBetween(from[0], from[1], to[0], to[1], results)
        return (results[1] + 360f) % 360f
    }

    private fun formatRemaining(seconds: Int): String {
        val minutes = seconds / 60
        return when {
            minutes >= 60 -> "${minutes / 60} h ${minutes % 60} min"
            minutes >= 1 -> "$minutes min"
            else -> "$seconds s"
        }
    }

    // ------------------------------------------------------------- providers

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
        } catch (e: SecurityException) {
            // Android refused the mock push — almost always because the app
            // is not (or no longer) selected as the mock location app. Tell
            // the user immediately instead of pretending to mock.
            onMockPushRejected()
        } catch (e: Exception) {
            // Transient failure — keep trying.
        }
    }

    /** Heads-up alert so a rejected mock never fails silently. */
    private fun onMockPushRejected() {
        if (pushFailureAlerted) return
        pushFailureAlerted = true
        postAlert(
            "Mock location is NOT working",
            "GPS Mock isn't selected as the mock location app in Developer Options. Tap to fix."
        )
    }

    private fun postAlert(title: String, text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALERT_CHANNEL_ID, "Mocking problems", NotificationManager.IMPORTANCE_HIGH
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
        val openAppIntent = PendingIntent.getActivity(
            this, 2,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val devSettingsIntent = PendingIntent.getActivity(
            this, 3,
            Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent)
            .addAction(0, "Open settings", devSettingsIntent)
            .build()
        getSystemService(NotificationManager::class.java)
            ?.notify(ALERT_NOTIFICATION_ID, notification)
    }

    private fun stopMocking() {
        val wasArrived = status?.get("arrived") == true
        MockStateStore.recordStop(this, wasArrived)
        MockStateStore.setActiveCommand(this, null)
        status = null
        job?.cancel()
        BaseFavoriteTileService.refreshAll(this)
        FavoriteWidgetProvider.refreshAll(this)
        NavigationWidgetProvider.pushIdle(this)
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
        const val EXTRA_FROM_LABEL = "FROM_LABEL"
        const val EXTRA_TO_LABEL = "TO_LABEL"
        const val EXTRA_DISTANCE_METERS = "DISTANCE_METERS"
        const val MODE_FIXED = "fixed"
        const val MODE_ROUTE = "route"
        private const val PROVIDER = LocationManager.GPS_PROVIDER
        private const val NOTIFICATION_ID = 1
        private const val ALERT_NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "mock_gps_channel"
        private const val ALERT_CHANNEL_ID = "mock_gps_alerts"
        private const val TILE_SIZE = 256
        private const val OSM_USER_AGENT =
            "gps-mock/2.0 (https://github.com/Sriharan-S/gps-mock; " +
                "location testing tool for the My Globe navigation app)"

        @Volatile
        private var status: Map<String, Any?>? = null

        /** Snapshot for the getMockStatus channel call and for tiles/widgets. */
        fun statusMap(): Map<String, Any?> = status ?: mapOf("active" to false)

        fun activeFavoriteId(): String? =
            (status?.get("favoriteId") as? String)?.takeIf { it.isNotEmpty() }
    }
}
