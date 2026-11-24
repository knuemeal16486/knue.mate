package com.knue.knuemate

/**
 * 버스 위젯 "곧 떠나는 차" — 모든 노선을 합쳐 가장 먼저 떠나는 차를 크게(2칸),
 * 넓으면 시각 순으로 5대. 그리는 법·알람은 BusWidgetProvider와 같다.
 */
class BusNextWidgetProvider : BusWidgetProvider() {
    override val nextStyle: Boolean = true
}
