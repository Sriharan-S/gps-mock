package com.sriharan.gps_mock

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle

/**
 * Invisible trampoline used by quick-settings tiles and home-screen widgets.
 * Starting a location foreground service directly from the background is
 * restricted on newer Android versions; briefly entering the foreground via
 * this transparent activity makes the start reliable everywhere.
 */
class MockControlActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent?.action) {
            ACTION_TOGGLE_FAVORITE ->
                intent.getStringExtra(EXTRA_FAVORITE_ID)?.let { toggleFavorite(it) }
            ACTION_STOP_MOCK -> stopMock()
        }
        finish()
    }

    private fun toggleFavorite(favoriteId: String) {
        val activeId = MockStateStore.getActiveCommand(this)?.optString("favoriteId")
        if (activeId == favoriteId) {
            stopMock()
            return
        }
        val favorite = MockStateStore.findFavorite(this, favoriteId) ?: return
        val serviceIntent = Intent(this, MockingService::class.java).apply {
            action = MockingService.ACTION_START_FIXED
            putExtra(MockingService.EXTRA_LAT, favorite.latitude)
            putExtra(MockingService.EXTRA_LNG, favorite.longitude)
            putExtra(MockingService.EXTRA_LABEL, favorite.name)
            putExtra(MockingService.EXTRA_FAVORITE_ID, favorite.id)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopMock() {
        val serviceIntent = Intent(this, MockingService::class.java)
            .setAction(MockingService.ACTION_STOP)
        startService(serviceIntent)
    }

    companion object {
        const val ACTION_TOGGLE_FAVORITE = "com.sriharan.gps_mock.TOGGLE_FAVORITE"
        const val ACTION_STOP_MOCK = "com.sriharan.gps_mock.STOP_MOCK"
        const val EXTRA_FAVORITE_ID = "FAVORITE_ID"
    }
}
