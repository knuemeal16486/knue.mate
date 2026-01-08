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
        Log.d(TAG, "위젯 개수: ${appWidgetIds.size}")
        
        // 저장된 모든 데이터 로깅
        val allData = widgetData.all
        Log.d(TAG, "저장된 데이터: $allData")
        
        appWidgetIds.forEach { widgetId ->
            try {
                // 레이아웃 통일: home_widget_layout 사용
                val views = RemoteViews(context.packageName, R.layout.home_widget_layout)
                
                // 데이터 가져오기 (기본값 설정)
                val title = widgetData.getString("title", "오늘 점심") ?: "오늘 점심"
                val content = widgetData.getString("content", "데이터를 불러오는 중...") ?: "데이터를 불러오는 중..."
                val source = widgetData.getString("source", "기숙사 식당") ?: "기숙사 식당"
                val themeMode = widgetData.getInt("themeMode", 0)
                
                // 투명도 처리 (문자열로 저장된 것을 float로 변환)
                val transparency = try {
                    val transStr = widgetData.getString("transparency", "0.0") ?: "0.0"
                    transStr.toFloat()
                } catch (e: Exception) {
                    0.0f
                }.coerceIn(0.0f, 1.0f)
                
                Log.d(TAG, "데이터 - title: $title, source: $source, transparency: $transparency")
                
                // 테마 모드 확인
                val isSystemDark = (context.resources.configuration.uiMode and 
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                
                val isDark = when (themeMode) {
                    0 -> isSystemDark  // 시스템
                    1 -> false         // 라이트
                    2 -> true          // 다크
                    else -> isSystemDark
                }
                
                Log.d(TAG, "ThemeMode: $themeMode, isDark: $isDark")
                
                // 배경색 및 텍스트 색상 설정
                val bgColor = if (isDark) {
                    Color.parseColor("#1E1E1E")  // 다크 모드 배경
                } else {
                    Color.parseColor("#FFFFFF")  // 라이트 모드 배경
                }
                
                val textColor = if (isDark) {
                    Color.parseColor("#FFFFFF")  // 다크 모드 텍스트
                } else {
                    Color.parseColor("#000000")  // 라이트 모드 텍스트
                }
                
                val subTextColor = if (isDark) {
                    Color.parseColor("#CCCCCC")  // 다크 모드 보조 텍스트
                } else {
                    Color.parseColor("#666666")  // 라이트 모드 보조 텍스트
                }
                
                // 투명도 적용
                val alphaValue = 1.0f - transparency  // 1.0 = 완전 불투명, 0.0 = 완전 투명
                val alpha = (alphaValue * 255).toInt().coerceIn(0, 255)
                val finalBgColor = Color.argb(
                    alpha,
                    Color.red(bgColor),
                    Color.green(bgColor),
                    Color.blue(bgColor)
                )
                
                Log.d(TAG, "투명도 계산: transparency=$transparency, alphaValue=$alphaValue, alpha=$alpha")
                
                // 배경색 설정 - 최상위 LinearLayout에 설정
                views.setInt(R.id.widget_layout, "setBackgroundColor", finalBgColor)
                
                // 텍스트 색상 설정
                views.setTextColor(R.id.widget_title, textColor)
                views.setTextColor(R.id.widget_menu, subTextColor)
                
                // 텍스트 내용 설정
                val displayTitle = "$source - $title"
                views.setTextViewText(R.id.widget_title, displayTitle)
                
                // 메뉴 내용 설정 (줄바꿈 유지)
                views.setTextViewText(R.id.widget_menu, content)
                
                // 위젯 업데이트
                appWidgetManager.updateAppWidget(widgetId, views)
                
                Log.d(TAG, "위젯 업데이트 완료: $widgetId - $displayTitle")
                
            } catch (e: Exception) {
                Log.e(TAG, "위젯 $widgetId 업데이트 오류", e)
            }
        }
        
        Log.d(TAG, "=== 위젯 업데이트 종료 ===")
    }
    
    override fun onReceive(context: Context?, intent: android.content.Intent?) {
        super.onReceive(context, intent)
        val action = intent?.action ?: "null"
        Log.d(TAG, "onReceive 액션: $action")
    }
    
    override fun onEnabled(context: Context?) {
        super.onEnabled(context)
        Log.d(TAG, "위젯이 활성화됨")
    }
    
    override fun onDisabled(context: Context?) {
        super.onDisabled(context)
        Log.d(TAG, "위젯이 비활성화됨")
    }
}