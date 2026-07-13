package com.sriharan.gps_mock.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.sriharan.gps_mock.MainActivity
import com.sriharan.gps_mock.MockControlActivity
import com.sriharan.gps_mock.MockStateStore
import com.sriharan.gps_mock.R

/**
 * Home-screen widget bound to one saved favorite (chosen when the widget is
 * placed). Tapping it toggles mocking of that favorite without opening the
 * app.
 */
class FavoriteWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { MockStateStore.clearWidgetFavorite(context, it) }
    }

    companion object {
        /** Redraws every placed favorite widget (active mock or favorites
         *  list changed). */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, FavoriteWidgetProvider::class.java)
            )
            ids.forEach { updateWidget(context, manager, it) }
        }

        fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_favorite)
            val favoriteId = MockStateStore.getWidgetFavorite(context, widgetId)
            val favorite = favoriteId?.let { MockStateStore.findFavorite(context, it) }

            if (favorite == null) {
                views.setTextViewText(R.id.widget_name, "Favorite removed")
                views.setTextViewText(R.id.widget_status, "Tap to open GPS Mock")
                views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_bg)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context, widgetId,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            } else {
                val activeId =
                    MockStateStore.getActiveCommand(context)?.optString("favoriteId")
                val active = activeId == favorite.id
                views.setTextViewText(R.id.widget_name, favorite.name)
                views.setTextViewText(
                    R.id.widget_status,
                    if (active) "Mocking — tap to stop" else "Off — tap to mock"
                )
                views.setInt(
                    R.id.widget_root, "setBackgroundResource",
                    if (active) R.drawable.widget_bg_active else R.drawable.widget_bg
                )
                val toggleIntent = Intent(context, MockControlActivity::class.java).apply {
                    action = MockControlActivity.ACTION_TOGGLE_FAVORITE
                    putExtra(MockControlActivity.EXTRA_FAVORITE_ID, favorite.id)
                }
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context, widgetId, toggleIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
            manager.updateAppWidget(widgetId, views)
        }
    }
}
