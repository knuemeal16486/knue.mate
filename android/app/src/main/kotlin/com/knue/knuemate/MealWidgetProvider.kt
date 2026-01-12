package com.knue.knuemate // [수정]

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import com.knue.knuemate.R

class MealWidgetProvider : HomeWidgetProvider() {
    
    companion object {
        private const val TAG = "MealWidgetProvider"
    }
    
    override fun onUpdate(
        context: Context, 
        appWidgetManager: AppWidgetManager, 
        appWidgetIds: IntArray, 
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.home_widget_layout)
                
                // 데이터 읽기
                val title = widgetData.getString("widget_title", "기숙사 식당") ?: "기숙사 식당"
                val time = widgetData.getString("widget_time", "시간 정보") ?: ""
                val menu = widgetData.getString("widget_menu", "정보를 불러오는 중...") ?: "정보 없음"
                
                // 투명도 및 테마 읽기
                val themeMode = widgetData.getInt("themeMode", 0) // 0:System, 1:Light, 2:Dark
                val transStr = widgetData.getString("transparency", "0.0") ?: "0.0"
                val transparency = try { transStr.toFloat() } catch(e: Exception) { 0.0f }
                
                // 다크모드 판별
                val isSystemDark = (context.resources.configuration.uiMode and 
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                val isDark = when(themeMode) {
                    1 -> false
                    2 -> true
                    else -> isSystemDark
                }

                // 색상 결정
                val bgColor = if(isDark) Color.parseColor("#1E1E1E") else Color.parseColor("#FFFFFF")
                val textColor = if(isDark) Color.parseColor("#FFFFFF") else Color.parseColor("#000000")
                val subColor = if(isDark) Color.parseColor("#BBBBBB") else Color.parseColor("#555555")
                val dividerColor = if(isDark) Color.parseColor("#444444") else Color.parseColor("#E0E0E0")

                // 투명도 적용
                val alpha = ((1.0f - transparency) * 255).toInt().coerceIn(0, 255)
                val finalBg = Color.argb(alpha, Color.red(bgColor), Color.green(bgColor), Color.blue(bgColor))

                // 뷰에 적용
                views.setInt(R.id.widget_layout, "setBackgroundColor", finalBg)
                views.setTextViewText(R.id.widget_title, title)
                views.setTextColor(R.id.widget_title, textColor)
                views.setTextViewText(R.id.widget_time, time)
                views.setTextColor(R.id.widget_time, subColor)
                views.setTextViewText(R.id.widget_menu, menu)
                views.setTextColor(R.id.widget_menu, subColor)
                views.setInt(R.id.widget_divider, "setBackgroundColor", dividerColor)

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Update Failed", e)
            }
        }
    }
}