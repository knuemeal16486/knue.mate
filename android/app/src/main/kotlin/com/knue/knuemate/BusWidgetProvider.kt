package com.knue.knuemate

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Calendar

/**
 * 버스 시간표 위젯 — 학교에서 나가는 차의 다음 출발 시각.
 *
 * 시간표는 앱이 위젯 저장소에 넣는다(lib/home_widgets.dart의
 * busWidgetTimetableJson, 키 "bus_timetable_json"). 위젯은 인터넷 없이 이 표로
 * 스스로 다음 차를 고르고, AlarmManager로 다음 출발(또는 5분 뒤) 때 다시 그린다.
 * 정확 알람이 아니라 몇 분 늦을 수 있어서, 그리는 순간에 지난 차를 다시 거른다.
 *
 * 모양이 두 가지라 위젯 고르는 화면에 둘 다 있다 — 노선별(이 클래스)과 곧 떠나는 차
 * (BusNextWidgetProvider). 레이아웃(bus_widget_layout.xml)은 같이 쓴다.
 */
open class BusWidgetProvider : HomeWidgetProvider() {

    /** false = 노선마다 다음 차, true = 곧 떠나는 차 순서. */
    protected open val nextStyle: Boolean = false

    companion object {
        private const val TAG = "BusWidgetProvider"
        const val ACTION_TICK = "com.knue.knuemate.BUS_TICK"

        /** 5분마다는 다시 그려 "N분 뒤"가 크게 낡지 않게 한다. */
        private const val MAX_GAP_MIN = 5

        private val LABEL_IDS = intArrayOf(
            R.id.bus_label_0, R.id.bus_label_1, R.id.bus_label_2, R.id.bus_label_3, R.id.bus_label_4,
        )
        private val TIMES_IDS = intArrayOf(
            R.id.bus_times_0, R.id.bus_times_1, R.id.bus_times_2, R.id.bus_times_3, R.id.bus_times_4,
        )
        private val BAR_IDS = intArrayOf(
            R.id.bus_bar_0, R.id.bus_bar_1, R.id.bus_bar_2, R.id.bus_bar_3, R.id.bus_bar_4,
        )
        private val ETA_IDS = intArrayOf(
            R.id.bus_eta_0, R.id.bus_eta_1, R.id.bus_eta_2, R.id.bus_eta_3, R.id.bus_eta_4,
        )

        fun minutesOf(hhmm: String): Int? {
            val p = hhmm.split(":")
            if (p.size != 2) return null
            val h = p[0].toIntOrNull() ?: return null
            val m = p[1].toIntOrNull() ?: return null
            return h * 60 + m
        }

        /**
         * Dart `nextDepartures`와 같은 규칙: 지금 분보다 뒤인 차 앞에서 n대.
         * 같은 분에 떠나는 차는 방금 떠난 차로 본다.
         *
         * | 지금 | 시각표 06:20·14:27·15:35 | n | 결과 |
         * |---|---|---|---|
         * | 14:00 | | 2 | 14:27, 15:35 |
         * | 14:27:30 | | 2 | 15:35 |
         * | 00:05 | | 1 | 06:20 |
         * | 23:30 | | 2 | (없음) |
         */
        fun nextDepartures(times: List<String>, nowMinutes: Int, n: Int): List<String> =
            times.filter { (minutesOf(it) ?: -1) > nowMinutes }.take(n)

        /** 다음 차가 가장 먼저 오는 노선(같은 분이면 여럿). iOS soonestRoutes와 같다. */
        fun soonestRoutes(firstMinutes: List<Int?>): Set<Int> {
            val best = firstMinutes.filterNotNull().minOrNull() ?: return emptySet()
            return firstMinutes.indices.filter { firstMinutes[it] == best }.toSet()
        }

        /**
         * 모든 노선을 합쳐 지금 이후 떠나는 차를 시각 순으로 n대(노선 번호, 시각).
         * 같은 분이면 노선 순서. iOS upcomingDepartures와 같다.
         *
         * | 지금 | 513: 14:27·15:35 / 518: 14:25·15:15 | n | 결과 |
         * |---|---|---|---|
         * | 14:00 | | 3 | 518 14:25, 513 14:27, 518 15:15 |
         * | 14:25 | | 2 | 513 14:27, 518 15:15 |
         */
        fun upcomingDepartures(routeTimes: List<List<String>>, nowMinutes: Int, n: Int): List<Pair<Int, String>> =
            routeTimes.flatMapIndexed { i, times ->
                nextDepartures(times, nowMinutes, n).mapNotNull { t -> minutesOf(t)?.let { Triple(i, t, it) } }
            }
                .sortedWith(compareBy({ it.third }, { it.first }))
                .take(n)
                .map { Pair(it.first, it.second) }

        /**
         * 노선 막대 색 — 공지 게시판 색(NoticeWidgetProvider.BOARD_COLORS)에서 고른다:
         * 513 파랑, 514 초록, 518 주황, 913 평동행 보라, 913 미호행 분홍. iOS kBusRouteColorIndex와 같다.
         */
        val ROUTE_COLOR_INDEX = intArrayOf(0, 1, 2, 3, 6)

        fun routeColor(route: Int, isDark: Boolean): Int {
            val (light, dark) = NoticeWidgetProvider.BOARD_COLORS[ROUTE_COLOR_INDEX[route % ROUTE_COLOR_INDEX.size]]
            return (if (isDark) dark else light) or 0xFF000000.toInt()
        }

        /** 앱 버스 화면과 같다: 토·일이면 주말 시간표. */
        fun isBusHoliday(cal: Calendar): Boolean {
            val wd = cal.get(Calendar.DAY_OF_WEEK)
            return wd == Calendar.SATURDAY || wd == Calendar.SUNDAY
        }

        data class Route(val label: String, val weekday: List<String>, val holiday: List<String>)

        fun parseRoutes(json: String?): List<Route>? {
            if (json.isNullOrEmpty()) return null
            return try {
                val arr = JSONObject(json).getJSONArray("routes")
                (0 until arr.length()).map { i ->
                    val o = arr.getJSONObject(i)
                    fun list(key: String): List<String> {
                        val a = o.optJSONArray(key) ?: return emptyList()
                        return (0 until a.length()).map { a.getString(it) }
                    }
                    Route(o.getString("label"), list("weekday"), list("holiday"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "시간표 읽기 실패", e)
                null
            }
        }

    }

    /** 위젯 종류마다 따로 예약한다(같은 요청 번호면 서로 덮어쓴다). */
    private fun tickIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            if (nextStyle) 1 else 0,
            Intent(context, javaClass).setAction(ACTION_TICK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TICK) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
            if (ids.isNotEmpty()) onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
            return
        }
        super.onReceive(context, intent)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(tickIntent(context))
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = Calendar.getInstance()
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val holiday = isBusHoliday(now)
        val routes = parseRoutes(widgetData.getString("bus_timetable_json", null))
        val colors = WidgetColors.read(context, widgetData)

        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.bus_widget_layout)
                colors.applyBackground(views, R.id.bus_bg)
                val day = if (holiday) "주말" else "평일"

                // 좁으면(2칸) 머리글이 위, 넓으면 왼쪽 칸.
                val widthDp = appWidgetManager.getAppWidgetOptions(widgetId)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                // 곧 떠나는 차는 넓혀도 small 모양(넓은 모양은 노선별과 겹쳐 뺐다 — 2026-11-25).
                val wide = !nextStyle && widthDp >= 220
                val hasRoutes = !routes.isNullOrEmpty()
                val side = wide && hasRoutes
                views.setViewVisibility(R.id.bus_side, if (side) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.bus_top, if (side) View.GONE else View.VISIBLE)
                if (side) {
                    views.setTextColor(R.id.bus_side_title, colors.title)
                    views.setTextColor(R.id.bus_side_sub, colors.muted)
                    views.setTextViewText(R.id.bus_side_day, day)
                    views.setTextColor(R.id.bus_side_day, colors.muted)
                } else {
                    views.setTextColor(R.id.bus_header, colors.title)
                    views.setTextViewText(R.id.bus_day, "학교 출발 · $day")
                    views.setTextColor(R.id.bus_day, colors.muted)
                }

                views.setViewVisibility(R.id.bus_rows, View.GONE)
                views.setViewVisibility(R.id.bus_next, View.GONE)
                views.setViewVisibility(R.id.bus_empty, View.GONE)
                if (routes.isNullOrEmpty()) {
                    views.setViewVisibility(R.id.bus_empty, View.VISIBLE)
                    views.setTextColor(R.id.bus_empty, colors.body)
                } else {
                    val routeTimes = routes.map { if (holiday) it.holiday else it.weekday }
                    when {
                        !nextStyle -> drawRoutes(views, routes, routeTimes, nowMin, wide, colors)
                        else -> drawNextSmall(views, routes, routeTimes, nowMin, colors)
                    }
                }

                views.setOnClickPendingIntent(
                    R.id.bus_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("knuemate://bus"),
                    ),
                )
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Update Failed", e)
            }
        }
        scheduleNext(context, routes, holiday, now, nowMin)
    }

    private fun clearRow(views: RemoteViews, i: Int) {
        views.setViewVisibility(BAR_IDS[i], View.INVISIBLE)
        views.setTextViewText(LABEL_IDS[i], "")
        views.setTextViewText(TIMES_IDS[i], "")
        views.setTextViewText(ETA_IDS[i], "")
    }

    /** 노선 이름 칸 — 넓으면 폭을 맞춰 시각이 한 줄로 서게, 좁으면 이름만큼. */
    private fun labelRow(views: RemoteViews, i: Int, route: Int, label: String, wide: Boolean, colors: WidgetColors) {
        views.setViewVisibility(BAR_IDS[i], View.VISIBLE)
        colors.applyBar(views, BAR_IDS[i], routeColor(route, colors.isDark))
        views.setTextViewText(LABEL_IDS[i], label)
        views.setTextColor(LABEL_IDS[i], colors.title)
        views.setTextViewTextSize(LABEL_IDS[i], android.util.TypedValue.COMPLEX_UNIT_SP, if (wide) 13f else 12f)
        views.setInt(LABEL_IDS[i], "setMinWidth", if (wide) dpToPx(72) else 0)
    }

    private fun dpToPx(dp: Int): Int =
        (dp * android.content.res.Resources.getSystem().displayMetrics.density).toInt()

    /** 노선별: 노선마다 다음 차(넓으면 2대 + "N분 뒤"). 가장 먼저 오는 차는 주황. */
    private fun drawRoutes(
        views: RemoteViews, routes: List<Route>, routeTimes: List<List<String>>,
        nowMin: Int, wide: Boolean, colors: WidgetColors,
    ) {
        views.setViewVisibility(R.id.bus_rows, View.VISIBLE)
        val soonest = soonestRoutes(routeTimes.map { t -> nextDepartures(t, nowMin, 1).firstOrNull()?.let { minutesOf(it) } })
        for (i in LABEL_IDS.indices) {
            val route = routes.getOrNull(i)
            if (route == null) { clearRow(views, i); continue }
            labelRow(views, i, i, route.label, wide, colors)
            val next = nextDepartures(routeTimes[i], nowMin, if (wide) 2 else 1)
            val hot = i in soonest
            if (next.isEmpty()) {
                // 좁으면 오른쪽 칸(eta)에 쓴다 — 시각이 오른쪽 끝에 붙는다.
                views.setTextViewText(TIMES_IDS[i], if (wide) "  오늘 운행 끝" else "")
                views.setTextColor(TIMES_IDS[i], colors.muted)
                views.setTextViewText(ETA_IDS[i], if (wide) "" else "운행 끝")
                views.setTextColor(ETA_IDS[i], colors.muted)
            } else if (wide) {
                val times = SpannableStringBuilder(next[0])
                times.setSpan(
                    ForegroundColorSpan(if (hot) colors.highlight else colors.body),
                    0, next[0].length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                if (next.size > 1) {
                    val from = times.length
                    times.append("  ").append(next[1])
                    times.setSpan(ForegroundColorSpan(colors.muted), from, times.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                views.setTextViewText(TIMES_IDS[i], times)
                views.setTextViewText(ETA_IDS[i], etaText((minutesOf(next[0]) ?: nowMin) - nowMin))
                views.setTextColor(ETA_IDS[i], if (hot) colors.highlight else colors.muted)
            } else {
                views.setTextViewText(TIMES_IDS[i], "")
                views.setTextViewText(ETA_IDS[i], next[0])
                views.setTextColor(ETA_IDS[i], if (hot) colors.highlight else colors.body)
                views.setTextViewTextSize(ETA_IDS[i], android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
            }
        }
    }

    /** 곧 떠나는 차(좁은 위젯): 첫 차를 크게, 아래에 그다음 두 대. */
    private fun drawNextSmall(
        views: RemoteViews, routes: List<Route>, routeTimes: List<List<String>>,
        nowMin: Int, colors: WidgetColors,
    ) {
        val up = upcomingDepartures(routeTimes, nowMin, 3)
        val first = up.firstOrNull()
        if (first == null) {
            views.setViewVisibility(R.id.bus_empty, View.VISIBLE)
            views.setTextViewText(R.id.bus_empty, "오늘 운행 끝")
            views.setTextColor(R.id.bus_empty, colors.muted)
            return
        }
        views.setViewVisibility(R.id.bus_next, View.VISIBLE)
        colors.applyBar(views, R.id.bus_next_bar, routeColor(first.first, colors.isDark))
        views.setTextViewText(R.id.bus_next_label, routes[first.first].label)
        views.setTextColor(R.id.bus_next_label, colors.title)
        val eta = etaText((minutesOf(first.second) ?: nowMin) - nowMin)
        val text = SpannableStringBuilder(first.second).append("  ").append(eta)
        text.setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, first.second.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        text.setSpan(android.text.style.RelativeSizeSpan(0.8f), first.second.length, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        views.setTextViewText(R.id.bus_next_time, text)
        views.setTextColor(R.id.bus_next_time, colors.highlight)
        views.setTextViewText(
            R.id.bus_next_more,
            up.drop(1).joinToString("\n") { "다음 ${routes[it.first].label} ${it.second}" },
        )
        views.setTextColor(R.id.bus_next_more, colors.muted)
    }

    private fun etaText(min: Int): String =
        if (min >= 60) "${min / 60}시간 ${min % 60}분 뒤" else "${min}분 뒤"

    /** 다음 출발 분(그 분부터 지난 차) 또는 5분 뒤 중 이른 때. 남은 차가 없으면 내일 00:01. */
    private fun scheduleNext(
        context: Context,
        routes: List<Route>?,
        holiday: Boolean,
        now: Calendar,
        nowMin: Int,
    ) {
        val nextDeparture = routes.orEmpty()
            .mapNotNull { r ->
                (if (holiday) r.holiday else r.weekday).mapNotNull { minutesOf(it) }.firstOrNull { it > nowMin }
            }
            .minOrNull()
        val at = (now.clone() as Calendar).apply {
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (nextDeparture == null) {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 1)
            } else {
                val target = minOf(nextDeparture, nowMin + MAX_GAP_MIN)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                add(Calendar.MINUTE, target)
            }
        }
        try {
            // 정확 알람이 아니다 — 권한이 필요 없고, 화면이 꺼져 있으면 미뤄진다.
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .set(AlarmManager.RTC, at.timeInMillis, tickIntent(context))
        } catch (e: Exception) {
            Log.e(TAG, "알람 예약 실패", e)
        }
    }
}
