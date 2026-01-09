package com.example.flutter_application_1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

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
        Log.d(TAG, "=== 위젯 업데이트 시작 ===")
        
        appWidgetIds.forEach { widgetId ->
            try {
                // 레이아웃 연결
                val views = RemoteViews(context.packageName, R.layout.home_widget_layout)
                
                // ---------------------------------------------------------------
                // [1] 데이터 가져오기 (키 이름을 Flutter 코드와 통일: widget_title, widget_time, widget_menu)
                // ---------------------------------------------------------------
                
                // 식당 이름 (예: 기숙사 식당)
                val titleText = widgetData.getString("widget_title", "기숙사 식당") ?: "기숙사 식당"
                
                // 시간대 (예: 오늘 점심) -> 이 부분을 새로 추가했습니다.
                val timeText = widgetData.getString("widget_time", "오늘 점심") ?: "오늘 점심"
                
                // 메뉴 내용
                val menuText = widgetData.getString("widget_menu", "데이터를 불러오는 중...") ?: "정보 없음"
                
                // 기타 설정값
                val themeMode = widgetData.getInt("themeMode", 0)
                val transparency = try {
                    widgetData.getString("transparency", "0.0")?.toFloat() ?: 0.0f
                } catch (e: Exception) {
                    0.0f
                }.coerceIn(0.0f, 1.0f)
                
                Log.d(TAG, "데이터확인 - title: $titleText, time: $timeText")
                
                // ---------------------------------------------------------------
                // [2] 테마 및 디자인 설정 (다크모드/투명도)
                // ---------------------------------------------------------------
                val isSystemDark = (context.resources.configuration.uiMode and 
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                
                val isDark = when (themeMode) {
                    0 -> isSystemDark  // 시스템
                    1 -> false         // 라이트
                    2 -> true          // 다크
                    else -> isSystemDark
                }
                
                // 색상 정의
                val bgColor = if (isDark) Color.parseColor("#1E1E1E") else Color.parseColor("#FFFFFF")
                val textColor = if (isDark) Color.parseColor("#FFFFFF") else Color.parseColor("#333333") // 제목용 진한색
                val subTextColor = if (isDark) Color.parseColor("#CCCCCC") else Color.parseColor("#666666") // 내용용 연한색
                
                // 투명도 적용한 배경색 계산
                val alphaValue = 1.0f - transparency
                val alpha = (alphaValue * 255).toInt().coerceIn(0, 255)
                val finalBgColor = Color.argb(alpha, Color.red(bgColor), Color.green(bgColor), Color.blue(bgColor))
                
                // ---------------------------------------------------------------
                // [3] 뷰에 데이터 꽂아넣기 (여기가 핵심!)
                // ---------------------------------------------------------------
                
                // 배경색 적용
                views.setInt(R.id.widget_layout, "setBackgroundColor", finalBgColor)
                
                // 1. 식당 이름 (widget_title)
                views.setTextViewText(R.id.widget_title, titleText)
                views.setTextColor(R.id.widget_title, textColor)
                
                // 2. 시간대 (widget_time) -> 아까 XML에서 만든 그 ID입니다.
                views.setTextViewText(R.id.widget_time, timeText)
                views.setTextColor(R.id.widget_time, textColor) // 식당 이름과 같은 색 혹은 subTextColor 사용 가능
                
                // 3. 메뉴 내용 (widget_menu)
                views.setTextViewText(R.id.widget_menu, menuText)
                views.setTextColor(R.id.widget_menu, subTextColor)

                // 위젯 매니저에게 업데이트 명령
                appWidgetManager.updateAppWidget(widgetId, views)
                
            } catch (e: Exception) {
                Log.e(TAG, "위젯 $widgetId 업데이트 오류", e)
            }
        }
    }
}