package com.knue.knuemate // [수정]

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
import org.json.JSONObject
import java.util.Calendar

class MealWidgetProvider : HomeWidgetProvider() {
    
    companion object {
        private const val TAG = "MealWidgetProvider"
        const val ACTION_TICK = "com.knue.knuemate.MEAL_TICK"
        /** 위젯 저장소 키 — Dart kMealWeekJsonKey와 같다. */
        const val MEAL_WEEK_KEY = "meal_week_json"
        /** 위젯 버튼으로 고른 식당 id — Dart kMealWidgetSourceKey와 같다. 앱에서 바꾸면 지운다. */
        const val SOURCE_KEY = "meal_widget_source"
        const val ACTION_TOGGLE = "com.knue.knuemate.MEAL_TOGGLE_SOURCE"

        /**
         * 식당 바꾸기 버튼을 누르면 갈 식당 id. Dart nextMealWidgetSource와 같다:
         * [current]가 없으면 selected에서 출발, JSON 식당 순서대로 다음(끝이면 처음),
         * 식당이 하나뿐이면 null(버튼을 안 보인다).
         */
        fun nextSource(json: String, current: String?): String? = try {
            val week = JSONObject(json)
            val sources = week.getJSONArray("sources")
            val ids = (0 until sources.length()).map { sources.getJSONObject(it).optString("id") }
            if (ids.size < 2) null else {
                val i = ids.indexOf(current ?: week.optString("selected"))
                ids[(i + 1) % ids.size]
            }
        } catch (e: Exception) {
            null
        }

        const val NO_MENU = "등록된 메뉴가 없습니다."
        const val NO_DATA = "앱을 한 번 열면\n식단을 불러옵니다."
        fun closedText(tomorrow: Boolean) = "${if (tomorrow) "내일" else "오늘"}은 식당을 운영하지 않아요 🥺"

        data class MealText(val title: String, val time: String, val menu: String)

        fun dayKey(c: Calendar): String = String.format(
            "%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
        )

        /** [now]와 같은 날 "HH:mm"(초 0). */
        private fun at(now: Calendar, hhmm: String): Calendar? {
            val p = hhmm.split(":")
            val h = p.getOrNull(0)?.toIntOrNull() ?: return null
            val m = p.getOrNull(1)?.toIntOrNull() ?: return null
            return (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
        }

        private fun source(week: JSONObject, want: String?): JSONObject? {
            val sources = week.optJSONArray("sources") ?: return null
            if (sources.length() == 0) return null
            val id = want ?: week.optString("selected")
            for (i in 0 until sources.length()) {
                val s = sources.getJSONObject(i)
                if (s.optString("id") == id) return s
            }
            return sources.getJSONObject(0)
        }

        /**
         * 한 주치(meal_week_json)에서 [now]에 그릴 글. Dart lib/meal_widget.dart의
         * resolveMealWidget과 같다(기준 표 test/meal_widget_test.dart):
         * 오늘 아직 안 끝난 첫 끼니(끝나는 분 00초까지 그 끼니) → 다 끝났으면 내일 첫 끼니.
         * 그날 캐시 없음 → NO_DATA, closed → closedText, 그 끼니 빈 목록 → NO_MENU.
         * JSON이 깨졌으면 null(옛 키로 그린다).
         */
        fun resolve(json: String, now: Calendar, want: String? = null): MealText? = try {
            val week = JSONObject(json)
            val src = source(week, want)
            if (src == null) null else {
                val title = src.optString("label")
                val meals = src.getJSONArray("meals")
                if (meals.length() == 0) MealText(title, "", NO_DATA) else {
                    var pick: JSONObject? = null
                    for (i in 0 until meals.length()) {
                        val m = meals.getJSONObject(i)
                        val end = at(now, m.optString("end"))
                        if (end != null && !now.after(end)) { pick = m; break }
                    }
                    val tomorrow = pick == null
                    val chosen = pick ?: meals.getJSONObject(0)
                    val time = "${if (tomorrow) "내일" else "오늘"} ${chosen.optString("label")}"
                    val date = (now.clone() as Calendar).apply { if (tomorrow) add(Calendar.DAY_OF_YEAR, 1) }
                    val day = src.optJSONObject("days")?.optJSONObject(dayKey(date))
                    when {
                        day == null -> MealText(title, time, NO_DATA)
                        day.optBoolean("closed", false) -> MealText(title, time, closedText(tomorrow))
                        else -> {
                            val list = day.optJSONArray(chosen.optString("key"))
                            val items = (0 until (list?.length() ?: 0)).map { list!!.getString(it) }
                            MealText(title, time, if (items.isEmpty()) NO_MENU else items.joinToString("\n") { "· $it" })
                        }
                    }
                }
            }
        } catch (e: Exception) {
            null
        }

        /** 다음에 글이 바뀌는 때: 오늘·내일 끼니가 끝난 1초 뒤, 또는 자정 중 가장 이른 것. */
        fun nextSwitch(json: String, now: Calendar): Calendar? = try {
            val meals = source(JSONObject(json), null)?.getJSONArray("meals")
            val candidates = mutableListOf<Calendar>()
            for (offset in 0..1) {
                val day = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, offset) }
                if (offset > 0) candidates.add(at(day, "00:00")!!)
                for (i in 0 until (meals?.length() ?: 0)) {
                    at(day, meals!!.getJSONObject(i).optString("end"))?.let {
                        it.add(Calendar.SECOND, 1); candidates.add(it)
                    }
                }
            }
            candidates.filter { it.after(now) }.minByOrNull { it.timeInMillis }
        } catch (e: Exception) {
            null
        }

        // 레이아웃(home_widget_layout.xml)과 맞춘 치수(dp, 글꼴 배율 1 기준).
        // 에뮬레이터 화면을 재서 정한 값이다(2026-11-23, Pixel 9 Pro): 한국어 글꼴은
        // 줄 높이가 글자 크기의 1.4배쯤이라 13sp 한 줄이 실제로 약 22dp를 먹는다.
        // 작게 잡으면 마지막 줄이 말줄임표 없이 반쯤 잘려 보인다.
        private const val PADDING_DP = 14f * 2
        private const val HEADER_DP = 63f      // 큰 끼니(20sp) + 가로 막대 + 식당·날 + 아래 여백(좁은 위젯만)
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
                // 한 주치가 있으면 지금 시각으로 끼니를 고른다(앱을 안 열어도 넘어간다).
                // 없으면 옛 키(앱이 고른 끼니 글).
                val week = widgetData.getString(MEAL_WEEK_KEY, null)
                val resolved = week?.let { resolve(it, Calendar.getInstance(), widgetData.getString(SOURCE_KEY, null)) }
                val title = resolved?.title
                    ?: (widgetData.getString("widget_title", "기숙사 식당") ?: "기숙사 식당")
                val time = resolved?.time ?: (widgetData.getString("widget_time", "") ?: "")
                val menu = resolved?.menu ?: (widgetData.getString("widget_menu", NO_DATA) ?: NO_DATA)
                
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

                // 끼니 밑 짧은 가로 막대 — 앱 테마 색.
                colors.applyBar(views, if (wide) R.id.meal_side_line else R.id.meal_top_line, colors.accent, 255)
                // 안내 문구(앱을 열어야 함·운영 안 함)면 흐리게 그대로.
                val message = isMessage(menu)
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

                // 식당 바꾸기 버튼 — 식당이 둘 이상일 때만. 앱을 열지 않고 바꾼다.
                val canToggle = week != null && nextSource(week, null) != null
                views.setViewVisibility(R.id.meal_toggle, if (canToggle) View.VISIBLE else View.GONE)
                if (canToggle) {
                    views.setInt(R.id.meal_toggle, "setColorFilter", colors.muted)
                    views.setOnClickPendingIntent(R.id.meal_toggle, toggleIntent(context))
                }

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
        scheduleNext(context, widgetData)
    }

    private fun tickIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, 0,
            Intent(context, javaClass).setAction(ACTION_TICK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun toggleIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, 1,
            Intent(context, javaClass).setAction(ACTION_TOGGLE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val prefs = HomeWidgetPlugin.getData(context)
            val week = prefs.getString(MEAL_WEEK_KEY, null)
            val next = week?.let { nextSource(it, prefs.getString(SOURCE_KEY, null)) }
            if (next != null) prefs.edit().putString(SOURCE_KEY, next).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
            if (ids.isNotEmpty()) onUpdate(context, manager, ids, prefs)
            return
        }
        if (intent.action == ACTION_TICK) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
            if (ids.isNotEmpty()) onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(tickIntent(context))
    }

    /** 끼니가 끝나는 때(또는 자정)에 다시 그린다. 정확 알람이 아니라 권한이 필요 없다. */
    private fun scheduleNext(context: Context, widgetData: SharedPreferences) {
        val json = widgetData.getString(MEAL_WEEK_KEY, null) ?: return
        val at = nextSwitch(json, Calendar.getInstance()) ?: return
        try {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .set(AlarmManager.RTC, at.timeInMillis, tickIntent(context))
        } catch (e: Exception) {
            Log.e(TAG, "알람 예약 실패", e)
        }
    }
}