package com.sriharan.gps_mock

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Invisible trampoline used as a fallback by quick-settings tiles and by
 * home-screen widgets. Starting a location foreground service directly from
 * the background can be restricted; briefly entering the foreground via this
 * transparent activity makes the start reliable everywhere.
 */
class MockControlActivity : Activity() {
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onPostResume() {
        super.onPostResume()
        if (handled) return
        handled = true

        // Wait until this activity is genuinely in the foreground before
        // starting the location FGS. Doing this from onCreate races Android's
        // background-start checks and caused cold quick-tile launches to die.
        val started = when (intent?.action) {
            ACTION_TOGGLE_FAVORITE ->
                intent.getStringExtra(EXTRA_FAVORITE_ID)?.let {
                    MockController.toggleFavoriteDirect(this, it)
                } ?: false
            ACTION_STOP_MOCK -> MockController.stopDirect(this)
            else -> false
        }

        if (!started) {
            // Keep the failure recoverable: open the normal app so the user can
            // grant/setup the required mock-location permission.
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        window.decorView.postDelayed({ finish() }, 250)
    }

    companion object {
        const val ACTION_TOGGLE_FAVORITE = "com.sriharan.gps_mock.TOGGLE_FAVORITE"
        const val ACTION_STOP_MOCK = "com.sriharan.gps_mock.STOP_MOCK"
        const val EXTRA_FAVORITE_ID = "FAVORITE_ID"
    }
}
