package com.sriharan.gps_mock.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.view.View
import android.widget.RemoteViews
import com.sriharan.gps_mock.MainActivity
import com.sriharan.gps_mock.MockingService
import com.sriharan.gps_mock.R

/**
 * Home-screen widget showing the state of a running mock route: remaining
 * (mock) time, progress, and a periodically refreshed map snapshot of the
 * simulated position, pushed by the MockingService while it runs.
 */
class NavigationWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // Render the current state immediately; the running service pushes
        // richer updates (with the map snapshot) on its own cadence.
        push(context, MockingService.statusMap(), null)
    }

    companion object {
        fun hasWidgets(context: Context): Boolean =
            AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, NavigationWidgetProvider::class.java)
            ).isNotEmpty()

        fun pushIdle(context: Context) = push(context, mapOf("active" to false), null)

        fun push(context: Context, status: Map<String, Any?>, mapBitmap: Bitmap?) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, NavigationWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return

            val views = RemoteViews(context.packageName, R.layout.widget_navigation)
            val isRoute = status["active"] == true &&
                status["mode"] == MockingService.MODE_ROUTE

            if (isRoute) {
                views.setViewVisibility(R.id.nav_idle, View.GONE)
                views.setViewVisibility(R.id.nav_overlay, View.VISIBLE)
                val label = (status["label"] as? String).orEmpty()
                views.setTextViewText(
                    R.id.nav_label,
                    label.ifEmpty { "Mock route" }
                )
                val arrived = status["arrived"] == true
                val remaining = (status["remainingSeconds"] as? Int) ?: 0
                views.setTextViewText(
                    R.id.nav_remaining,
                    if (arrived) "Arrived — holding position"
                    else "${formatRemaining(remaining)} remaining"
                )
                val progress = (status["progress"] as? Double) ?: 0.0
                views.setProgressBar(
                    R.id.nav_progress, 1000, (progress * 1000).toInt(), false
                )
                if (mapBitmap != null) {
                    views.setImageViewBitmap(R.id.nav_map, mapBitmap)
                    views.setViewVisibility(R.id.nav_map, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.nav_map, View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.nav_idle, View.VISIBLE)
                views.setViewVisibility(R.id.nav_overlay, View.GONE)
                views.setViewVisibility(R.id.nav_map, View.GONE)
            }

            views.setOnClickPendingIntent(
                R.id.nav_root,
                PendingIntent.getActivity(
                    context, 0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun formatRemaining(seconds: Int): String {
            val minutes = seconds / 60
            return when {
                minutes >= 60 -> "${minutes / 60} h ${minutes % 60} min"
                minutes >= 1 -> "$minutes min"
                else -> "$seconds s"
            }
        }
    }
}
