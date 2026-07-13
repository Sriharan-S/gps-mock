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
    private const val KEY_HISTORY = "history_json"
    private const val HISTORY_LIMIT = 100

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

    // ------------------------------------------------------------- history

    fun getHistoryJson(context: Context): String =
        prefs(context).getString(KEY_HISTORY, null) ?: "[]"

    fun clearHistory(context: Context) {
        prefs(context).edit().remove(KEY_HISTORY).apply()
    }

    /** Records the start of a mock session. Retargeting a running fixed
     *  mock (pin moved while mocking) updates the open entry instead of
     *  spamming a new one; switching modes closes the previous entry. */
    fun recordStart(context: Context, command: JSONObject) {
        val history = historyArray(context)
        val now = System.currentTimeMillis()
        val last = if (history.length() > 0) history.optJSONObject(history.length() - 1) else null
        val lastOpen = last != null && last.optLong("endedAt", 0L) == 0L
        val mode = command.optString("mode", "fixed")

        if (lastOpen && last!!.optString("mode") == "fixed" && mode == "fixed") {
            last.put("lat", command.optDouble("lat"))
            last.put("lng", command.optDouble("lng"))
            last.put("label", command.optString("label"))
            saveHistory(context, history)
            return
        }
        if (lastOpen) last!!.put("endedAt", now)

        history.put(JSONObject().apply {
            put("mode", mode)
            put("label", command.optString("label"))
            put("startedAt", now)
            if (mode == "route") {
                put("fromLabel", command.optString("fromLabel"))
                put("toLabel", command.optString("toLabel"))
                put("distanceMeters", command.optDouble("distanceMeters", 0.0))
                put("durationSeconds", command.optInt("durationSeconds", 0))
            } else {
                put("lat", command.optDouble("lat"))
                put("lng", command.optDouble("lng"))
            }
        })
        saveHistory(context, history)
    }

    /** Marks the open session as ended (mock stopped). */
    fun recordStop(context: Context, arrived: Boolean) {
        val history = historyArray(context)
        if (history.length() == 0) return
        val last = history.optJSONObject(history.length() - 1) ?: return
        if (last.optLong("endedAt", 0L) != 0L) return
        last.put("endedAt", System.currentTimeMillis())
        if (arrived) last.put("arrived", true)
        saveHistory(context, history)
    }

    /** Marks the open route session as having reached its destination. */
    fun recordArrived(context: Context) {
        val history = historyArray(context)
        if (history.length() == 0) return
        val last = history.optJSONObject(history.length() - 1) ?: return
        if (last.optLong("endedAt", 0L) != 0L || last.optBoolean("arrived")) return
        last.put("arrived", true)
        last.put("arrivedAt", System.currentTimeMillis())
        saveHistory(context, history)
    }

    private fun historyArray(context: Context): JSONArray =
        try {
            JSONArray(getHistoryJson(context))
        } catch (e: Exception) {
            JSONArray()
        }

    private fun saveHistory(context: Context, history: JSONArray) {
        val trimmed = if (history.length() > HISTORY_LIMIT) {
            JSONArray().also {
                for (i in history.length() - HISTORY_LIMIT until history.length()) {
                    it.put(history.get(i))
                }
            }
        } else {
            history
        }
        prefs(context).edit().putString(KEY_HISTORY, trimmed.toString()).apply()
    }
}
