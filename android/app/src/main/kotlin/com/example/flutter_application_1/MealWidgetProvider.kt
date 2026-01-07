package com.example.flutter_application_1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MealWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            
            // 데이터 가져오기
            val title = widgetData.getString("title", "식단 정보 없음")
            val menu = widgetData.getString("menu", "앱을 실행하여 데이터를 불러오세요.")
            
            // 스타일 데이터 가져오기 (Type Safety Fix)
            val themeMode = widgetData.getInt("themeMode", 0) 
            
            // [Fix] ClassCastException 방지: getFloat가 실패하면 기본값 0.0f 사용
            val transparency = try {
                widgetData.getFloat("transparency", 0.0f)
            } catch (e: Exception) {
                0.0f
            }

            // 다크모드 여부 판별
            val isSystemDark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            val isDark = when (themeMode) {
                1 -> false // Light
                2 -> true  // Dark
                else -> isSystemDark // System
            }

            // 배경색 및 글자색 설정
            val bgColor = if (isDark) Color.parseColor("#1E1E1E") else Color.parseColor("#FFFFFF")
            val textColor = if (isDark) Color.parseColor("#FFFFFF") else Color.parseColor("#000000")
            val subTextColor = if (isDark) Color.parseColor("#CCCCCC") else Color.parseColor("#333333")

            // 투명도 적용 (Alpha: 0~255)
            val alpha = ((1.0 - transparency) * 255).toInt().coerceIn(0, 255)
            val finalColor = Color.argb(alpha, Color.red(bgColor), Color.green(bgColor), Color.blue(bgColor))

            // 뷰에 적용
            views.setInt(R.id.widget_container, "setBackgroundColor", finalColor)
            views.setTextColor(R.id.widget_title, textColor)
            views.setTextColor(R.id.widget_menu, subTextColor)
            
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_menu, menu)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}