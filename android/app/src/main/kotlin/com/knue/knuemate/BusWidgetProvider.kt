package com.knue.knuemate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import com.knue.knuemate.R

class BusWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val TAG = "BusWidgetProvider"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.bus_widget_layout)

                // 데이터 읽기
                val outgoingNext = widgetData.getString("bus_outgoing_next", "--:--") ?: "--:--"
                val incomingNext = widgetData.getString("bus_incoming_next", "--:--") ?: "--:--"
                val upcoming = widgetData.getString("bus_upcoming", "") ?: ""
                val updatedAt = widgetData.getString("bus_updated_at", "") ?: ""

                // 테마 읽기
                val themeMode = widgetData.getInt("themeMode", 0)
                val isSystemDark = (context.resources.configuration.uiMode and
                        Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                val isDark = when (themeMode) {
                    1 -> false
                    2 -> true
                    else -> isSystemDark
                }

                // 색상
                val bgColor = if (isDark) Color.parseColor("#1E1E1E") else Color.parseColor("#FFFFFF")
                val textColor = if (isDark) Color.parseColor("#FFFFFF") else Color.parseColor("#000000")
                val subColor = if (isDark) Color.parseColor("#AAAAAA") else Color.parseColor("#888888")
                val outColor = if (isDark) Color.parseColor("#82B1FF") else Color.parseColor("#4285F4")
                val inColor = if (isDark) Color.parseColor("#80CBC4") else Color.parseColor("#00897B")

                // 뷰 적용
                views.setInt(R.id.bus_widget_layout, "setBackgroundColor", bgColor)
                views.setTextViewText(R.id.bus_widget_title, "청람버스")
                views.setTextColor(R.id.bus_widget_title, textColor)
                views.setTextViewText(R.id.bus_widget_updated, updatedAt)
                views.setTextColor(R.id.bus_widget_updated, subColor)
                views.setTextViewText(R.id.bus_outgoing_next, outgoingNext)
                views.setTextColor(R.id.bus_outgoing_next, outColor)
                views.setTextViewText(R.id.bus_incoming_next, incomingNext)
                views.setTextColor(R.id.bus_incoming_next, inColor)
                views.setTextViewText(R.id.bus_widget_upcoming, upcoming)
                views.setTextColor(R.id.bus_widget_upcoming, subColor)

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Bus Widget Update Failed", e)
            }
        }
    }
}
