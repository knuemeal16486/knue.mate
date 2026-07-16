import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'bus_timetable_data.dart';
import 'calendar_screen.dart';
import 'constants.dart';
import 'notice_model.dart';
import 'notice_screen.dart';
import 'notice_service.dart';
import 'root_screen.dart';
import 'schedule_model.dart';

/// 홈 대시보드. 식단/버스/공지/일정 서브시스템을 한 화면에 모아 보여준다.
/// 세로 스크롤, 섹션별 독립 위젯 — 2·3단계 카드 추가 시 구조 변경 없이 삽입 가능.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scraper = KnueScraper();

  // 식단 카드
  bool _mealLoading = true;
  bool _mealError = false;
  MealType _nextMealType = MealType.breakfast;
  List<String> _nextMealItems = const [];

  // 버스 카드
  bool _busLoading = true;
  bool _busError = false;
  String _busLabel = "운행 종료";

  // 키워드 알림 카드
  bool _keywordLoading = true;
  bool _keywordError = false;
  List<Notice> _keywordMatches = const [];

  // 공지 미리보기 카드
  bool _noticeLoading = true;
  bool _noticeError = false;
  List<Notice> _favNotices = const [];

  // 일정 카드
  bool _upcomingLoading = true;
  bool _upcomingError = false;
  List<CalendarEvent> _upcomingAcademic = const [];
  List<DdayItem> _upcomingDdays = const [];

  @override
  void initState() {
    super.initState();
    _loadMeal();
    _loadBus();
    _loadKeywordAlerts();
    _loadNoticePreview();
    _loadUpcoming();
  }

  // ---------------------------------------------------------------------
  // 데이터 로딩 (섹션별 독립 — 하나가 실패해도 다른 섹션은 정상 표시)
  // ---------------------------------------------------------------------

  /// 현재 시각 기준 다음 끼니 판정. statusFor로 아직 끝나지 않은(대기중 또는
  /// 제공중) 첫 끼니를 찾고, 저녁까지 모두 지났으면 내일 아침으로 넘어간다.
  ({MealType type, DateTime date}) _resolveNextMeal(DateTime now) {
    for (final type in [MealType.breakfast, MealType.lunch, MealType.dinner]) {
      final status = statusFor(type, now, now);
      if (status == ServeStatus.waiting || status == ServeStatus.open) {
        return (type: type, date: now);
      }
    }
    return (type: MealType.breakfast, date: now.add(const Duration(days: 1)));
  }

  Future<void> _loadMeal() async {
    if (mounted) setState(() { _mealLoading = true; _mealError = false; });
    try {
      final now = DateTime.now();
      final source = defaultSourceNotifier.value;
      final next = _resolveNextMeal(now);
      final result = await fetchMealApi(next.date, source);
      final meals = (result is Map ? result['meals'] : null) as Map?;
      final items = asStringList(meals?[next.type.stdKey] ?? []);
      if (!mounted) return;
      setState(() {
        _nextMealType = next.type;
        _nextMealItems = items;
        _mealLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _mealLoading = false; _mealError = true; });
    }
  }

  Future<void> _loadBus() async {
    if (mounted) setState(() { _busLoading = true; _busError = false; });
    try {
      final isWeekday = DateTime.now().weekday <= 5;
      String? best;
      String? bestRoute;
      for (final route in const ["513", "514", "518"]) {
        final t = BusTimetableData.getNextBusTime(route, true, isWeekday);
        if (t != null && (best == null || t.compareTo(best) < 0)) {
          best = t;
          bestRoute = route;
        }
      }
      if (!mounted) return;
      setState(() {
        _busLabel = (best != null && bestRoute != null)
            ? "$bestRoute번 · $best"
            : "운행 종료";
        _busLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _busLoading = false; _busError = true; });
    }
  }

  Future<void> _loadKeywordAlerts() async {
    if (mounted) setState(() { _keywordLoading = true; _keywordError = false; });
    try {
      final cached = await NoticeCache.load() ?? [];
      final keywords = PreferencesService.noticeKeywords.value;
      final matches = keywords.isEmpty
          ? <Notice>[]
          : cached
              .where((n) => keywords.any(
                  (kw) => n.title.toLowerCase().contains(kw.toLowerCase())))
              .take(3)
              .toList();
      if (!mounted) return;
      setState(() {
        _keywordMatches = matches;
        _keywordLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _keywordLoading = false; _keywordError = true; });
    }
  }

  Future<void> _loadNoticePreview() async {
    if (mounted) setState(() { _noticeLoading = true; _noticeError = false; });
    try {
      final favBoards = PreferencesService.favoriteBoards.value.toSet();
      final all = await _scraper.fetchAllNotices(onlyCategories: favBoards);
      final filtered = favBoards.isEmpty
          ? <Notice>[]
          : all.where((n) => favBoards.contains(n.category)).take(5).toList();
      if (!mounted) return;
      setState(() {
        _favNotices = filtered;
        _noticeLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _noticeLoading = false; _noticeError = true; });
    }
  }

  Future<void> _loadUpcoming() async {
    if (mounted) setState(() { _upcomingLoading = true; _upcomingError = false; });
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final events = await _scraper.fetchCalendarEvents(now.year, now.month);
      final upcoming = events.where((e) {
        final end = DateTime(e.endDate.year, e.endDate.month, e.endDate.day);
        return !end.isBefore(today);
      }).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final ddays = List<DdayItem>.from(PreferencesService.ddayItems.value)
        ..sort((a, b) => a.daysLeft(now).compareTo(b.daysLeft(now)));

      if (!mounted) return;
      setState(() {
        _upcomingAcademic = upcoming.take(3).toList();
        _upcomingDdays = ddays.take(2).toList();
        _upcomingLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _upcomingLoading = false; _upcomingError = true; });
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text("홈"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTodayBriefingHeader(color, isDark),
                const SizedBox(height: 12),
                _buildKeywordAlertsCard(color, isDark),
                const SizedBox(height: 12),
                _buildNoticePreviewCard(color, isDark),
                const SizedBox(height: 12),
                _buildUpcomingCard(color, isDark),
                const SizedBox(height: 12),
                // 2단계: 동아리 공연 카드 / 3단계: 자취방 카드 삽입 지점
              ],
            ),
          ),
        );
      },
    );
  }

  // --- 1. 오늘 브리핑 헤더 ---------------------------------------------

  Widget _buildTodayBriefingHeader(Color color, bool isDark) {
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko_KR').format(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _greeting(now),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildMealBriefCard(color, isDark)),
            const SizedBox(width: 10),
            Expanded(child: _buildBusBriefCard(color, isDark)),
          ],
        ),
      ],
    );
  }

  String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 9) return "좋은 아침이에요";
    if (hour < 14) return "점심 맛있게 드세요";
    if (hour < 19) return "오늘 하루도 힘내세요";
    return "편안한 저녁 보내세요";
  }

  Widget _buildMealBriefCard(Color color, bool isDark) {
    return _BriefCard(
      isDark: isDark,
      onTap: () => RootNavigationScreen.switchTab(AppTab.meal),
      icon: Icons.restaurant_menu_rounded,
      color: color,
      title: _nextMealType.label,
      child: _mealLoading
          ? const _CardLoading()
          : _mealError
              ? _CardFailure(onRetry: _loadMeal)
              : (_nextMealItems.isEmpty
                  ? Text(
                      "등록된 메뉴가 없습니다",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    )
                  : Text(
                      _nextMealItems.take(3).join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    )),
    );
  }

  Widget _buildBusBriefCard(Color color, bool isDark) {
    return _BriefCard(
      isDark: isDark,
      onTap: () => RootNavigationScreen.switchTab(AppTab.bus),
      icon: Icons.directions_bus_rounded,
      color: color,
      title: "다음 버스",
      child: _busLoading
          ? const _CardLoading()
          : _busError
              ? _CardFailure(onRetry: _loadBus)
              : Text(
                  _busLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
    );
  }

  // --- 2. 키워드 알림 카드 ------------------------------------------------

  Widget _buildKeywordAlertsCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "키워드 알림",
      icon: Icons.notifications_active_outlined,
      color: color,
      child: _keywordLoading
          ? const _CardLoading()
          : _keywordError
              ? _CardFailure(onRetry: _loadKeywordAlerts)
              : (PreferencesService.noticeKeywords.value.isEmpty
                  ? _buildEmptyKeywordPrompt(color, isDark)
                  : (_keywordMatches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            "일치하는 새 공지가 없습니다",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _keywordMatches
                              .map((n) => _NoticeRow(notice: n, color: color, isDark: isDark))
                              .toList(),
                        ))),
    );
  }

  Widget _buildEmptyKeywordPrompt(Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "관심 키워드를 등록해 보세요",
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: OutlinedButton(
            // NoticeScreen 내부 키워드 관리 바텀시트는 private 위젯이라 홈에서
            // 직접 열 수 없어, 청람공지 화면으로 이동시키는 것으로 단순화했다.
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NoticeScreen()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text("키워드 등록하기", style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // --- 3. 공지 미리보기 카드 ----------------------------------------------

  Widget _buildNoticePreviewCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "즐겨찾는 공지",
      icon: Icons.campaign_outlined,
      color: color,
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NoticeScreen()),
      ),
      child: _noticeLoading
          ? const _CardLoading()
          : _noticeError
              ? _CardFailure(onRetry: _loadNoticePreview)
              : (_favNotices.isEmpty
                  ? Text(
                      "즐겨찾는 게시판의 공지가 없습니다",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _favNotices
                          .map((n) => _NoticeRow(notice: n, color: color, isDark: isDark))
                          .toList(),
                    )),
    );
  }

  // --- 4. 일정 카드 --------------------------------------------------------

  Widget _buildUpcomingCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "다가오는 일정",
      icon: Icons.event_note_outlined,
      color: color,
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CalendarScreen()),
      ),
      child: _upcomingLoading
          ? const _CardLoading()
          : _upcomingError
              ? _CardFailure(onRetry: _loadUpcoming)
              : (_upcomingAcademic.isEmpty && _upcomingDdays.isEmpty
                  ? Text(
                      "등록된 일정이 없습니다",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._upcomingAcademic.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Icon(Icons.circle,
                                      size: 5, color: color),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    _formatShortDate(e.startDate),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (_upcomingAcademic.isNotEmpty && _upcomingDdays.isNotEmpty)
                          const SizedBox(height: 6),
                        if (_upcomingDdays.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _upcomingDdays.map((d) {
                              final left = d.daysLeft(DateTime.now());
                              return Chip(
                                label: Text(
                                  "${_ddayLabel(left)} ${d.title}",
                                  style: TextStyle(
                                      fontSize: 11, color: color),
                                ),
                                backgroundColor: color.withValues(alpha: 0.12),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                      ],
                    )),
    );
  }

  String _formatShortDate(DateTime d) =>
      "${d.month}.${d.day.toString().padLeft(2, '0')}";

  String _ddayLabel(int daysLeft) {
    if (daysLeft == 0) return "D-DAY";
    return daysLeft > 0 ? "D-$daysLeft" : "D+${-daysLeft}";
  }
}

// ===========================================================================
// 공용 카드 부품
// ===========================================================================

/// 오늘 브리핑의 가로 2카드(식단/버스) 공통 셸.
class _BriefCard extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  const _BriefCard({
    required this.isDark,
    required this.onTap,
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// 세로 섹션 카드(키워드/공지/일정) 공통 셸. "전체 보기" 액션은 선택적.
class _SectionCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onSeeAll;

  const _SectionCard({
    required this.isDark,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Text(
                    "전체 보기",
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  final Notice notice;
  final Color color;
  final bool isDark;

  const _NoticeRow({required this.notice, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              notice.category,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              notice.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            notice.date,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _CardFailure extends StatelessWidget {
  final VoidCallback onRetry;
  const _CardFailure({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          "불러오기 실패 · 다시 시도",
          style: TextStyle(fontSize: 12, color: Colors.redAccent),
        ),
      ),
    );
  }
}
