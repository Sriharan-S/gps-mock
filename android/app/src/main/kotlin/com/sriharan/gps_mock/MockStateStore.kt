package com.sriharan.gps_mock

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native-side state shared between the Flutter engine, the mocking service,
 * quick-settings tiles and home-screen widgets. Kept in plain
 * SharedPreferences so every component can read it without the Flutter
 * engine running.
 */
object MockStateStore {
    private const val PREFS = "gps_mock_state"
    private const val KEY_ACTIVE_COMMAND = "active_command"
    private const val KEY_FAVORITES = "favorites_json"
    private const val KEY_WIDGET_FAVORITE_PREFIX = "widget_favorite_"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The command the MockingService is currently executing (or should
     *  resume after a sticky restart). Null when mocking is off. */
    fun setActiveCommand(context: Context, command: JSONObject?) {
        prefs(context).edit().apply {
            if (command == null) remove(KEY_ACTIVE_COMMAND)
            else putString(KEY_ACTIVE_COMMAND, command.toString())
        }.apply()
    }

    fun getActiveCommand(context: Context): JSONObject? =
        prefs(context).getString(KEY_ACTIVE_COMMAND, null)?.let {
            try { JSONObject(it) } catch (e: Exception) { null }
        }

    /** Favorites mirrored from Flutter (see the syncFavorites channel call). */
    fun setFavoritesJson(context: Context, json: String) {
        prefs(context).edit().putString(KEY_FAVORITES, json).apply()
    }

    fun getFavorites(context: Context): List<Favorite> {
        val raw = prefs(context).getString(KEY_FAVORITES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                Favorite(
                    id = item.optString("id"),
                    name = item.optString("name"),
                    address = item.optString("address"),
                    latitude = item.optDouble("latitude"),
                    longitude = item.optDouble("longitude"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun findFavorite(context: Context, id: String): Favorite? =
        getFavorites(context).firstOrNull { it.id == id }

    /** Home-screen widget id -> favorite id binding (set by the widget's
     *  configuration activity). */
    fun setWidgetFavorite(context: Context, widgetId: Int, favoriteId: String) {
        prefs(context).edit()
            .putString(KEY_WIDGET_FAVORITE_PREFIX + widgetId, favoriteId).apply()
    }

    fun getWidgetFavorite(context: Context, widgetId: Int): String? =
        prefs(context).getString(KEY_WIDGET_FAVORITE_PREFIX + widgetId, null)

    fun clearWidgetFavorite(context: Context, widgetId: Int) {
        prefs(context).edit().remove(KEY_WIDGET_FAVORITE_PREFIX + widgetId).apply()
    }

    data class Favorite(
        val id: String,
        val name: String,
        val address: String,
        val latitude: Double,
        val longitude: Double,
    )
}
