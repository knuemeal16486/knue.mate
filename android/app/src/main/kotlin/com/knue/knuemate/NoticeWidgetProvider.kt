package com.knue.knuemate

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * 공지 위젯 — 즐겨찾기 게시판마다 최신 글 하나씩.
 *
 * Android는 위젯이 직접 받지 않는다. 앱과 1시간 백그라운드 공지 작업이 공지
 * 캐시를 바꿀 때 lib/home_widgets.dart의 pushNoticeWidget이 고른 줄을
 * "notice_rows_json"([{"b","t","d","l"}])에 넣고 이 위젯을 다시 그리게 한다.
 * 줄을 누르면 그 글을 브라우저로 바로 연다(앱을 거치지 않는다).
 */
class NoticeWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val TAG = "NoticeWidgetProvider"

        // 레이아웃(notice_widget_layout.xml) 치수(dp, 글꼴 배율 1 기준).
        private const val PADDING_DP = 14f * 2
        private const val HEADER_DP = 18f
        private const val ROW_DP = 25f  // 13sp 한 줄 + 위아래 4dp

        private val ROW_IDS = intArrayOf(
            R.id.notice_row_0, R.id.notice_row_1, R.id.notice_row_2, R.id.notice_row_3,
            R.id.notice_row_4, R.id.notice_row_5, R.id.notice_row_6, R.id.notice_row_7,
        )
        private val TITLE_IDS = intArrayOf(
            R.id.notice_title_0, R.id.notice_title_1, R.id.notice_title_2, R.id.notice_title_3,
            R.id.notice_title_4, R.id.notice_title_5, R.id.notice_title_6, R.id.notice_title_7,
        )
        private val DATE_IDS = intArrayOf(
            R.id.notice_date_0, R.id.notice_date_1, R.id.notice_date_2, R.id.notice_date_3,
            R.id.notice_date_4, R.id.notice_date_5, R.id.notice_date_6, R.id.notice_date_7,
        )

        data class Row(val board: String, val title: String, val date: String, val link: String)

        fun parseRows(json: String?): List<Row>? {
            if (json.isNullOrEmpty()) return null
            return try {
                val arr = JSONArray(json)
                (0 until arr.length()).map { i ->
                    val o = arr.getJSONObject(i)
                    Row(o.optString("b"), o.optString("t"), o.optString("d"), o.optString("l"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "공지 줄 읽기 실패", e)
                null
            }
        }

        /** Dart widgetLinkAllowed와 같은 규칙: https이면서 knue.ac.kr 계열. */
        fun linkAllowed(link: String): Boolean {
            val uri = try { Uri.parse(link) } catch (e: Exception) { return false }
            if (uri.scheme != "https") return false
            val host = uri.host?.lowercase() ?: return false
            return host == "knue.ac.kr" || host.endsWith(".knue.ac.kr")
        }

        /** "2026-11-20" → "11/20" */
        fun shortDate(d: String): String {
            val p = d.split("-")
            return if (p.size == 3) "${p[1]}/${p[2]}" else d
        }

        /** 위젯 높이에 들어가는 줄 수(1~8). */
        fun rowCapacity(heightDp: Float, fontScale: Float): Int {
            val room = heightDp - PADDING_DP - HEADER_DP * fontScale
            return (room / (ROW_DP * fontScale)).toInt().coerceIn(1, 8)
        }
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

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rows = parseRows(widgetData.getString("notice_rows_json", null))
        val colors = WidgetColors.read(context, widgetData)
        val fontScale = context.resources.configuration.fontScale

        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.notice_widget_layout)
                colors.applyBackground(views, R.id.notice_bg)
                views.setTextColor(R.id.notice_header, colors.accent)

                val openNotice = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("knuemate://notice"),
                )
                views.setOnClickPendingIntent(R.id.notice_root, openNotice)

                val heightDp = appWidgetManager.getAppWidgetOptions(widgetId)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                    .takeIf { it > 0 }?.toFloat() ?: 150f
                val capacity = rowCapacity(heightDp, fontScale)

                if (rows == null || rows.isEmpty()) {
                    views.setViewVisibility(R.id.notice_empty, View.VISIBLE)
                    views.setTextViewText(
                        R.id.notice_empty,
                        if (rows == null) "앱을 한 번 열면\n공지를 불러옵니다." else "즐겨찾기 게시판의 글이 아직 없어요.",
                    )
                    views.setTextColor(R.id.notice_empty, colors.body)
                    ROW_IDS.forEach { views.setViewVisibility(it, View.GONE) }
                } else {
                    views.setViewVisibility(R.id.notice_empty, View.GONE)
                    for (i in ROW_IDS.indices) {
                        val row = rows.getOrNull(i)
                        if (row == null || i >= capacity) {
                            views.setViewVisibility(ROW_IDS[i], View.GONE)
                            continue
                        }
                        views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                        val head = "[${row.board}] "
                        val text = SpannableStringBuilder(head + row.title).apply {
                            setSpan(ForegroundColorSpan(colors.accent), 0, head.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                            setSpan(StyleSpan(Typeface.BOLD), 0, head.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        }
                        views.setTextViewText(TITLE_IDS[i], text)
                        views.setTextColor(TITLE_IDS[i], colors.title)
                        views.setTextViewText(DATE_IDS[i], shortDate(row.date))
                        views.setTextColor(DATE_IDS[i], colors.muted)
                        // 학교 링크만 브라우저로 연다. 아니면 앱 공지로.
                        val click = if (linkAllowed(row.link)) {
                            PendingIntent.getActivity(
                                context,
                                widgetId * 10 + i,
                                Intent(Intent.ACTION_VIEW, Uri.parse(row.link)),
                                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                            )
                        } else {
                            openNotice
                        }
                        views.setOnClickPendingIntent(ROW_IDS[i], click)
                    }
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Update Failed", e)
            }
        }
    }
}
