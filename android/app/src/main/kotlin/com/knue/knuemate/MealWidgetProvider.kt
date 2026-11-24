package com.knue.knuemate // [수정]

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import com.knue.knuemate.R

class MealWidgetProvider : HomeWidgetProvider() {
    
    companion object {
        private const val TAG = "MealWidgetProvider"

        // 레이아웃(home_widget_layout.xml)과 맞춘 치수(dp, 글꼴 배율 1 기준).
        // 에뮬레이터 화면을 재서 정한 값이다(2026-11-23, Pixel 9 Pro): 한국어 글꼴은
        // 줄 높이가 글자 크기의 1.4배쯤이라 13sp 한 줄이 실제로 약 22dp를 먹는다.
        // 작게 잡으면 마지막 줄이 말줄임표 없이 반쯤 잘려 보인다.
        private const val PADDING_DP = 14f * 2
        private const val HEADER_DP = 54f      // 큰 끼니(20sp) + 식당·날 + 아래 여백(좁은 위젯만)
        private const val MENU_LINE_DP = 22f   // 13sp 한 줄 + lineSpacingExtra 3dp

        /**
         * 메뉴를 위젯 크기에 맞춘다.
         *
         * 한 줄에 하나씩 다 들어가면 그대로 두고, 안 들어가면 "쌀밥 · 김치찌개 · …"처럼
         * 이어 써서 줄바꿈이 폭을 채우게 한다. 예전엔 늘 한 줄에 하나씩이라
         * 2×2 위젯에서 메뉴가 4개까지만 보이고 나머지는 반쯤 잘려 나왔다.
         *
         * @return 표시할 글과 최대 줄 수(넘치면 말줄임표).
         */
        fun fitMenu(menu: String, heightDp: Float, fontScale: Float, headerOnTop: Boolean = true): Pair<String, Int> {
            val lineDp = MENU_LINE_DP * fontScale
            val room = heightDp - PADDING_DP - (if (headerOnTop) HEADER_DP * fontScale else 0f)
            val capacity = (room / lineDp).toInt().coerceAtLeast(1)
            val lines = menu.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
            if (lines.size <= capacity) return Pair(lines.joinToString("\n"), capacity)
            // 줄은 메뉴 **사이**에서만 바뀌게 한다. 한국어는 글자마다 줄을 바꿀 수 있어
            // "배추김/치"처럼 쪼개지므로, 메뉴 글자 사이에 보이지 않는 연결 문자
            // (WORD JOINER, U+2060)를 넣고 빈칸은 붙임표 빈칸으로 바꾼다. 가운뎃점도
            // 앞 메뉴에 붙여 줄 첫머리에 "·"가 오지 않게 한다.
            val inline = lines.joinToString("\u00A0· ") { item ->
                item.removePrefix("·").trim().replace(' ', '\u00A0')
                    .toList().joinToString("\u2060")
            }
            return Pair(inline, capacity)
        }

        /** 큰 머리글로 쓸 끼니와 날. "오늘 점심" → ("점심", "오늘"). iOS mealHeaderParts와 같다. */
        fun headerParts(time: String): Pair<String, String> {
            val t = time.trim()
            if (t.isEmpty()) return Pair("식단", "")
            val sp = t.lastIndexOf(' ')
            if (sp < 0) return Pair(t, "")
            return Pair(t.substring(sp + 1), t.substring(0, sp).trim())
        }

        /** 메뉴가 아니라 안내 문구인지 — 앱은 메뉴 줄마다 "· "를 붙인다. */
        fun isMessage(menu: String): Boolean =
            menu.split("\n").none { it.trim().startsWith("·") }

        /** 메뉴 줄의 "· " 머리를 뗀다(막대가 대신한다). */
        fun stripBullets(menu: String): String =
            menu.split("\n").map { it.trim().removePrefix("·").trim() }.filter { it.isNotEmpty() }
                .joinToString("\n")
    }

    // 사용자가 위젯 크기를 바꾸면 메뉴를 새 크기에 맞춰 다시 그린다.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
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
                
                val colors = WidgetColors.read(context, widgetData)
                colors.applyBackground(views, R.id.widget_bg)
                val textColor = colors.title
                val subColor = colors.body

                // 넓으면(4칸) 머리글을 왼쪽 칸에, 좁으면 위에.
                val options = appWidgetManager.getAppWidgetOptions(widgetId)
                val wide = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) >= 220
                val (meal, day) = headerParts(time)
                views.setViewVisibility(R.id.meal_side, if (wide) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.meal_top, if (wide) View.GONE else View.VISIBLE)
                if (wide) {
                    views.setTextViewText(R.id.meal_side_meal, meal)
                    views.setTextColor(R.id.meal_side_meal, textColor)
                    views.setTextViewText(R.id.meal_side_place, title)
                    views.setTextColor(R.id.meal_side_place, colors.muted)
                    views.setTextViewText(R.id.meal_side_day, day)
                    views.setTextColor(R.id.meal_side_day, colors.muted)
                } else {
                    views.setTextViewText(R.id.widget_time, meal)
                    views.setTextColor(R.id.widget_time, textColor)
                    views.setTextViewText(R.id.widget_title, listOf(title, day).filter { it.isNotEmpty() }.joinToString(" · "))
                    views.setTextColor(R.id.widget_title, colors.muted)
                }

                // 안내 문구(앱을 열어야 함·운영 안 함)면 막대 없이 그대로.
                val message = isMessage(menu)
                views.setViewVisibility(R.id.meal_bar, if (message) View.GONE else View.VISIBLE)
                colors.applyBar(views, R.id.meal_bar, colors.accent)
                // 세로 화면 기준 높이(MAX_HEIGHT). 값이 없으면 2×2 정도로 본다.
                val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                    .takeIf { it > 0 }?.toFloat() ?: 150f
                val (menuText, maxLines) = fitMenu(
                    if (message) menu else stripBullets(menu), heightDp,
                    context.resources.configuration.fontScale, headerOnTop = !wide,
                )
                views.setTextViewText(R.id.widget_menu, menuText)
                views.setInt(R.id.widget_menu, "setMaxLines", maxLines)
                views.setTextColor(R.id.widget_menu, if (message) subColor else textColor)

                // 위젯을 누르면 앱이 knuemate://meal 로 열린다.
                // Flutter 쪽(main.dart)이 이 URI를 보고 식단 탭으로 이동한다.
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("knuemate://meal")
                    )
                )

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Update Failed", e)
            }
        }
    }
}