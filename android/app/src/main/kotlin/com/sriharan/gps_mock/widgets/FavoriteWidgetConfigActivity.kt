package com.sriharan.gps_mock.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import com.sriharan.gps_mock.MockStateStore

/** Shown when a favorite widget is placed: pick which saved location the
 *  widget controls. */
class FavoriteWidgetConfigActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        title = "Choose a favorite"
        val favorites = MockStateStore.getFavorites(this)
        if (favorites.isEmpty()) {
            setContentView(TextView(this).apply {
                text = "No saved locations yet.\n\n" +
                    "Open GPS Mock and save a favorite first, then add this widget again."
                textSize = 16f
                setPadding(48, 48, 48, 48)
            })
            return
        }

        val listView = ListView(this)
        listView.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            favorites.map { favorite ->
                if (favorite.address.isEmpty()) favorite.name
                else "${favorite.name} — ${favorite.address}"
            }
        )
        listView.setOnItemClickListener { _, _, position, _ ->
            val favorite = favorites[position]
            MockStateStore.setWidgetFavorite(this, widgetId, favorite.id)
            FavoriteWidgetProvider.updateWidget(
                this, AppWidgetManager.getInstance(this), widgetId
            )
            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            )
            finish()
        }
        setContentView(listView)
    }
}
