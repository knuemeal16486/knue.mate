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
 */
class BusWidgetProvider : HomeWidgetProvider() {

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

        private fun tickIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, BusWidgetProvider::class.java).setAction(ACTION_TICK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TICK) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, BusWidgetProvider::class.java))
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
                views.setTextColor(R.id.bus_header, colors.accent)
                views.setTextViewText(R.id.bus_day, if (holiday) "주말" else "평일")
                views.setTextColor(R.id.bus_day, colors.muted)

                // 좁으면(2칸) 다음 차 1대만, 넓으면 2대 + "N분 뒤".
                val widthDp = appWidgetManager.getAppWidgetOptions(widgetId)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val wide = widthDp >= 220

                if (routes.isNullOrEmpty()) {
                    views.setViewVisibility(R.id.bus_rows, View.GONE)
                    views.setViewVisibility(R.id.bus_empty, View.VISIBLE)
                    views.setTextColor(R.id.bus_empty, colors.body)
                } else {
                    views.setViewVisibility(R.id.bus_rows, View.VISIBLE)
                    views.setViewVisibility(R.id.bus_empty, View.GONE)
                    // 넓은 위젯에서 가장 먼저 오는 차는 주황으로 눈에 띄게.
                    val soonest = if (wide) soonestRoutes(routes.map { r ->
                        nextDepartures(if (holiday) r.holiday else r.weekday, nowMin, 1)
                            .firstOrNull()?.let { minutesOf(it) }
                    }) else emptySet()
                    for (i in LABEL_IDS.indices) {
                        val route = routes.getOrNull(i)
                        if (route == null) {
                            views.setTextViewText(LABEL_IDS[i], "")
                            views.setTextViewText(TIMES_IDS[i], "")
                            views.setTextViewText(ETA_IDS[i], "")
                            continue
                        }
                        val next = nextDepartures(
                            if (holiday) route.holiday else route.weekday, nowMin, if (wide) 2 else 1,
                        )
                        views.setTextViewText(LABEL_IDS[i], route.label)
                        views.setTextColor(LABEL_IDS[i], colors.title)
                        if (next.isEmpty()) {
                            views.setTextViewText(TIMES_IDS[i], "오늘 운행 끝")
                            views.setTextColor(TIMES_IDS[i], colors.muted)
                            views.setTextViewText(ETA_IDS[i], "")
                        } else {
                            val hot = i in soonest
                            val times = SpannableStringBuilder(next.joinToString("  "))
                            if (hot) {
                                times.setSpan(
                                    ForegroundColorSpan(colors.highlight),
                                    0, next[0].length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                                )
                            }
                            views.setTextViewText(TIMES_IDS[i], times)
                            views.setTextColor(TIMES_IDS[i], colors.body)
                            val eta = (minutesOf(next[0]) ?: nowMin) - nowMin
                            views.setTextViewText(ETA_IDS[i], if (wide) etaText(eta) else "")
                            views.setTextColor(ETA_IDS[i], if (hot) colors.highlight else colors.accent)
                        }
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
