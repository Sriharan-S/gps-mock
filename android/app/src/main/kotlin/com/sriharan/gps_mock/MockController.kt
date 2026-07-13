package com.sriharan.gps_mock

import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Shared start/stop logic for everything that controls mocking from outside
 * the Flutter UI (quick-settings tiles, widgets, the trampoline activity).
 */
object MockController {

    /** Toggles mocking of [favoriteId] by talking to the service directly.
     *  Returns false when the platform refuses the background start — the
     *  caller should then fall back to the [MockControlActivity] trampoline. */
    fun toggleFavoriteDirect(context: Context, favoriteId: String): Boolean {
        val activeId = MockStateStore.getActiveCommand(context)?.optString("favoriteId")
        return if (activeId == favoriteId) {
            stopDirect(context)
        } else {
            startFavoriteDirect(context, favoriteId)
        }
    }

    fun startFavoriteDirect(context: Context, favoriteId: String): Boolean {
        val favorite = MockStateStore.findFavorite(context, favoriteId) ?: return true
        val intent = Intent(context, MockingService::class.java).apply {
            action = MockingService.ACTION_START_FIXED
            putExtra(MockingService.EXTRA_LAT, favorite.latitude)
            putExtra(MockingService.EXTRA_LNG, favorite.longitude)
            putExtra(MockingService.EXTRA_LABEL, favorite.name)
            putExtra(MockingService.EXTRA_FAVORITE_ID, favorite.id)
        }
        return startService(context, intent)
    }

    fun stopDirect(context: Context): Boolean {
        val intent = Intent(context, MockingService::class.java)
            .setAction(MockingService.ACTION_STOP)
        return startService(context, intent)
    }

    private fun startService(context: Context, intent: Intent): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // The service enters the foreground for every command
                // (including stop), so startForegroundService is always safe.
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (e: Exception) {
            // Background FGS start rejected (device-specific policy) — the
            // caller falls back to the foreground trampoline.
            false
        }
    }
}
