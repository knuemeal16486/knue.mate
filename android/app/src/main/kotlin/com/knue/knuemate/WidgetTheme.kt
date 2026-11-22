package com.knue.knuemate

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.widget.RemoteViews

/**
 * 식단·버스·공지 위젯이 같이 쓰는 테마·투명도.
 *
 * 값은 식단 위젯 설정(lib/constants.dart의 _updateWidgetDataInternal)이 넣는다.
 *   themeMode     Int     ThemeMode.index (0 system / 1 light / 2 dark)
 *   transparency  String  0.0~1.0
 */
data class WidgetColors(
    val isDark: Boolean,
    val background: Int,
    val alpha: Int,
    val title: Int,
    val body: Int,
    val muted: Int,
    val accent: Int,
) {
    /** 배경: 모양(둥근 모서리)은 drawable이 유지하고 색·투명도만 입힌다.
     *  setBackgroundColor를 쓰면 drawable이 단색으로 갈아끼워져 모서리가 사라진다. */
    fun applyBackground(views: RemoteViews, bgId: Int) {
        views.setInt(bgId, "setColorFilter", background)
        views.setInt(bgId, "setImageAlpha", alpha)
    }

    companion object {
        fun read(context: Context, prefs: SharedPreferences): WidgetColors {
            val themeMode = prefs.getInt("themeMode", 0)
            val transparency = prefs.getString("transparency", "0.0")?.toFloatOrNull() ?: 0f
            val isSystemDark = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            val isDark = when (themeMode) {
                1 -> false
                2 -> true
                else -> isSystemDark
            }
            return WidgetColors(
                isDark = isDark,
                background = Color.parseColor(if (isDark) "#1E1E1E" else "#FFFFFF"),
                alpha = ((1.0f - transparency) * 255).toInt().coerceIn(0, 255),
                title = Color.parseColor(if (isDark) "#FFFFFF" else "#000000"),
                body = Color.parseColor(if (isDark) "#BBBBBB" else "#555555"),
                muted = Color.parseColor(if (isDark) "#888888" else "#999999"),
                accent = Color.parseColor("#4285F4"),
            )
        }
    }
}
