import 'package:flutter/material.dart';
import 'bus_timetable_data.dart';
import 'ui_utils.dart';

class CallBusBottomSheet extends StatefulWidget {
  const CallBusBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CallBusBottomSheet(),
    );
  }

  @override
  State<CallBusBottomSheet> createState() => _CallBusBottomSheetState();
}

class _CallBusBottomSheetState extends State<CallBusBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),

          // 헤더 영역
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.directions_bus_filled_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "콜버스 특정시간대 고정노선",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "청주시 DRT(수요응답형) 고정시간표 운행",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ],
            ),
          ),

          // 콜버스 이용 안내 — "바로 DRT" 앱으로 예약해야 탄다는 걸 모르는
          // 학생이 많다. 여기서 시간표만 보고 정류장에 그냥 나가면 못 탄다.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        children: [
                          const TextSpan(text: "'"),
                          TextSpan(
                            text: "바로 DRT",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          const TextSpan(
                            text: "' 앱을 설치해서 예약해야 탈 수 있어요. "
                                "요금은 성인 기준 카드 650원 · 현금 700원이에요.",
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 탭 바
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor:
                  isDark ? Colors.white60 : Colors.grey.shade700,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: "강내콜버스 (前 51번)"),
                Tab(text: "오송콜버스 (前 52번)"),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 탭 뷰 콘텐츠
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScheduleList(
                  isDark: isDark,
                  primaryColor: primaryColor,
                  schedules: BusTimetableData.gangnaeCallBusSchedules,
                  routeName: "강내 특정시간대 고정노선",
                  routeDesc: "미호 ↔ 탑연리 ↔ 월탄리 ↔ 다락리 ↔ 태성리 ↔ 산단리 ↔ 저산리 ↔ 당곡리/사곡리",
                ),
                _buildScheduleList(
                  isDark: isDark,
                  primaryColor: primaryColor,
                  schedules: BusTimetableData.osongCallBusSchedules,
                  routeName: "오송 특정시간대 고정노선",
                  routeDesc: "오송읍 ↔ 오송역 ↔ 쌍청1리 ↔ 호계리 ↔ 상정리 ↔ 공북리 ↔ 조치원",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList({
    required bool isDark,
    required Color primaryColor,
    required List<CallBusScheduleItem> schedules,
    required String routeName,
    required String routeDesc,
  }) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    int nextIndex = -1;
    for (int i = 0; i < schedules.length; i++) {
      try {
        final parts = schedules[i].departureTime.split(":");
        final depMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        if (depMinutes >= currentMinutes) {
          nextIndex = i;
          break;
        }
      } catch (_) {}
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // 노선 요약 정보 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: isDark ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primaryColor.withValues(alpha: isDark ? 0.25 : 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 16,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    routeName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                routeDesc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 회차별 카드 목록
        ...schedules.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isNext = index == nextIndex;

          int depMinutes = 0;
          try {
            final parts = item.departureTime.split(":");
            depMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          } catch (_) {}

          final bool isPassed = nextIndex != -1 && index < nextIndex;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isNext
                  ? (isDark
                      ? primaryColor.withValues(alpha: 0.18)
                      : primaryColor.withValues(alpha: 0.08))
                  : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isNext
                    ? primaryColor
                    : (isDark ? Colors.white12 : Colors.grey.shade200),
                width: isNext ? 1.8 : 1,
              ),
              boxShadow: isNext
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: isDark ? 0.2 : 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 회차 뱃지 + 출발/도착 시간
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isNext
                                ? primaryColor
                                : (isDark
                                    ? Colors.white12
                                    : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${item.round}회차",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isNext
                                  ? Colors.white
                                  : (isDark
                                      ? Colors.white70
                                      : Colors.grey.shade800),
                            ),
                          ),
                        ),
                        if (isNext) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: KnueTokens.warm(isDark),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${depMinutes - currentMinutes}분 후 출발",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isPassed)
                      Text(
                        "운행 종료",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white30 : Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // 출발지 -> 종점 타임라인
                Row(
                  children: [
                    // 출발 정보
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "출발 (${item.departurePlace})",
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.departureTime,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFeatures: KnueTokens.tabularFigures,
                              color: isPassed
                                  ? Colors.grey
                                  : (isDark ? Colors.white : Colors.black87),
                              decoration:
                                  isPassed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 화살표 아이콘
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: isNext
                            ? primaryColor
                            : (isDark ? Colors.white24 : Colors.grey.shade400),
                      ),
                    ),

                    // 도착 정보
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "도착 (${item.arrivalPlace})",
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.arrivalTime,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFeatures: KnueTokens.tabularFigures,
                              color: isPassed
                                  ? Colors.grey
                                  : (isDark ? Colors.white : Colors.black87),
                              decoration:
                                  isPassed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 경유지 칩
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "경유",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.stops.join(" ➔ "),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: isPassed
                                ? Colors.grey
                                : (isDark
                                    ? Colors.white70
                                    : Colors.grey.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
