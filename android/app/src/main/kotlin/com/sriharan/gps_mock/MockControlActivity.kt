package com.sriharan.gps_mock

import android.app.Activity
import android.os.Bundle

/**
 * Invisible trampoline used as a fallback by quick-settings tiles and by
 * home-screen widgets. Starting a location foreground service directly from
 * the background can be restricted; briefly entering the foreground via this
 * transparent activity makes the start reliable everywhere.
 */
class MockControlActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent?.action) {
            ACTION_TOGGLE_FAVORITE ->
                intent.getStringExtra(EXTRA_FAVORITE_ID)?.let {
                    MockController.toggleFavoriteDirect(this, it)
                }
            ACTION_STOP_MOCK -> MockController.stopDirect(this)
        }
        finish()
    }

    companion object {
        const val ACTION_TOGGLE_FAVORITE = "com.sriharan.gps_mock.TOGGLE_FAVORITE"
        const val ACTION_STOP_MOCK = "com.sriharan.gps_mock.STOP_MOCK"
        const val EXTRA_FAVORITE_ID = "FAVORITE_ID"
    }
}
