package com.sriharan.gps_mock.tiles

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.sriharan.gps_mock.MockControlActivity
import com.sriharan.gps_mock.MockController
import com.sriharan.gps_mock.MockStateStore

/**
 * Quick-settings tiles: one per saved favorite (first four, in list order).
 * Turning a tile on mocks that favorite without opening the app; because
 * only one location can be mocked at a time, activating a tile automatically
 * deactivates the others.
 */
abstract class BaseFavoriteTileService : TileService() {
    protected abstract val slotIndex: Int

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val favorite = MockStateStore.getFavorites(this).getOrNull(slotIndex)
        if (favorite == null) {
            tile.state = Tile.STATE_UNAVAILABLE
            tile.label = "GPS Mock"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "No favorite saved"
            }
        } else {
            val activeId = MockStateStore.getActiveCommand(this)?.optString("favoriteId")
            val active = activeId == favorite.id
            tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = favorite.name
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = if (active) "Mocking" else "Off"
            }
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val favorite = MockStateStore.getFavorites(this).getOrNull(slotIndex) ?: return
        if (isLocked) {
            unlockAndRun { toggle(favorite.id) }
        } else {
            toggle(favorite.id)
        }
    }

    private fun toggle(favoriteId: String) {
        // A location foreground service cannot reliably be started while the
        // app is backgrounded on Android 12+ (and Android 14 enforces this
        // before our service can enter the foreground). Always use the tiny
        // foreground trampoline so tile taps work from a cold process too.
        toggleViaTrampoline(favoriteId)
    }

    private fun toggleViaTrampoline(favoriteId: String) {
        val intent = Intent(this, MockControlActivity::class.java).apply {
            action = MockControlActivity.ACTION_TOGGLE_FAVORITE
            putExtra(MockControlActivity.EXTRA_FAVORITE_ID, favoriteId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this, slotIndex, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }

    companion object {
        private val TILE_CLASSES = listOf(
            FavoriteTileService1::class.java,
            FavoriteTileService2::class.java,
            FavoriteTileService3::class.java,
            FavoriteTileService4::class.java,
        )

        /** Re-syncs every tile's label/state, e.g. after the active mock or
         *  the favorites list changes. */
        fun refreshAll(context: Context) {
            TILE_CLASSES.forEach { tileClass ->
                try {
                    requestListeningState(context, ComponentName(context, tileClass))
                } catch (e: Exception) {
                    // Quick settings unavailable — ignore.
                }
            }
        }
    }
}

class FavoriteTileService1 : BaseFavoriteTileService() {
    override val slotIndex = 0
}

class FavoriteTileService2 : BaseFavoriteTileService() {
    override val slotIndex = 1
}

class FavoriteTileService3 : BaseFavoriteTileService() {
    override val slotIndex = 2
}

class FavoriteTileService4 : BaseFavoriteTileService() {
    override val slotIndex = 3
}
