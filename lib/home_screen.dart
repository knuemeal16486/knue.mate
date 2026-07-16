import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'bus_timetable_data.dart';
import 'calendar_screen.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'club_events_screen.dart';
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

  // 동아리 행사 카드
  bool _clubLoading = true;
  bool _clubError = false;
  List<ClubEvent> _clubEvents = const [];

  @override
  void initState() {
    super.initState();
    _loadMeal();
    _loadBus();
    _loadKeywordAlerts();
    _loadNoticePreview();
    _loadUpcoming();
    _loadClubEvents();
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

  Future<void> _loadClubEvents() async {
    if (mounted) setState(() { _clubLoading = true; _clubError = false; });
    try {
      final all = await ClubEventService.fetchAll();
      // 녹출 우선 + 다가오는(시작일 오늘 이후) 순, 상위 3건
      final now = DateTime.now();
      final upcoming = all
          .where((e) => (e.endDate ?? e.startDate).isAfter(now))
          .toList();
      upcoming.sort((a, b) {
        if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
        return a.startDate.compareTo(b.startDate);
      });
      if (!mounted) return;
      setState(() {
        _clubEvents = upcoming.take(3).toList();
        _clubLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _clubLoading = false; _clubError = true; });
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
          body: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroHeader(color, isDark),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKeywordAlertsCard(color, isDark),
                      const SizedBox(height: 12),
                      _buildNoticePreviewCard(color, isDark),
                      const SizedBox(height: 12),
                      _buildUpcomingCard(color, isDark),
                      const SizedBox(height: 12),
                      _buildClubEventsCard(color, isDark),
                      // 3단계: 자취방 카드 삽입 지점
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- 1. 히어로 헤더 (브랜디드 그라디언트 + 오늘 브리핑) ---------------

  Widget _buildHeroHeader(Color color, bool isDark) {
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko_KR').format(now);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // themeColor 기반 그라디언트 — 설정에서 앱 색 바꾸면 헤더도 함께 변경.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.12)!,
            color,
            Color.lerp(color, Colors.black, 0.22)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _greeting(now),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 15),
              // 두 타일 높이를 맞추기 위해 IntrinsicHeight로 Row 높이를 한정한다.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _HeroTile(
                        icon: Icons.restaurant_menu_rounded,
                        label: _nextMealType.label,
                        onTap: () =>
                            RootNavigationScreen.switchTab(AppTab.meal),
                        child: _mealHeroChild(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroTile(
                        icon: Icons.directions_bus_rounded,
                        label: "다음 버스",
                        onTap: () =>
                            RootNavigationScreen.switchTab(AppTab.bus),
                        child: _busHeroChild(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroLoading() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );

  Widget _heroRetry(VoidCallback onRetry) => GestureDetector(
        onTap: onRetry,
        child: Text(
          "다시 시도",
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.9),
            decoration: TextDecoration.underline,
          ),
        ),
      );

  Widget _mealHeroChild() {
    if (_mealLoading) return _heroLoading();
    if (_mealError) return _heroRetry(_loadMeal);
    if (_nextMealItems.isEmpty) {
      return Text(
        "등록된 메뉴가 없습니다",
        style:
            TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
      );
    }
    return Text(
      _nextMealItems.take(3).join('\n'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _busHeroChild() {
    if (_busLoading) return _heroLoading();
    if (_busError) return _heroRetry(_loadBus);
    return Text(
      _busLabel,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 9) return "좋은 아침이에요";
    if (hour < 14) return "점심 맛있게 드세요";
    if (hour < 19) return "오늘 하루도 힘내세요";
    return "편안한 저녁 보내세요";
  }

  // --- 2. 키워드 알림 카드 ------------------------------------------------

  Widget _buildKeywordAlertsCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "키워드 알림",
      icon: Icons.notifications_active_outlined,
      color: color,
      accentColor: const Color(0xFFF59E0B),
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
      accentColor: const Color(0xFFFB923C),
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
      accentColor: const Color(0xFF8B5CF6),
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

  // --- 5. 동아리 행사 카드 --------------------------------------------------

  Widget _buildClubEventsCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "동아리 공연·행사",
      icon: Icons.celebration_outlined,
      color: color,
      accentColor: const Color(0xFFEC4899),
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClubEventsScreen()),
      ),
      child: _clubLoading
          ? const _CardLoading()
          : _clubError
              ? _CardFailure(onRetry: _loadClubEvents)
              : (_clubEvents.isEmpty
                  ? Text(
                      "예정된 공연·행사가 없습니다",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _clubEvents.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            if (e.isFeatured) ...[
                              Icon(Icons.star, size: 12, color: color),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                "${e.title} · ${e.clubName}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              _formatShortDate(e.startDate),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
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

/// 히어로 헤더 안의 오늘 브리핑 타일(식단/버스) — 컬러 헤더 위 반투명 흰색 카드.
class _HeroTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  const _HeroTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            child,
          ],
        ),
      ),
    );
  }
}

/// 세로 섹션 카드(키워드/공지/일정) 공통 셸. "전체 보기" 액션은 선택적.
/// [accentColor]로 카드 왼쪽 컬러 띠 + 같은 색 아이콘 칩을 줘 종류별 위계를 준다.
/// "전체 보기" 링크 색은 앱 포인트 색([color], themeColor)을 그대로 따라 통일감 유지.
class _SectionCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color color;
  final Color accentColor;
  final Widget child;
  final VoidCallback? onSeeAll;

  const _SectionCard({
    required this.isDark,
    required this.title,
    required this.icon,
    required this.color,
    required this.accentColor,
    required this.child,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      // IntrinsicHeight로 Row 높이를 콘텐츠에 맞춰 한정 → 왼쪽 액센트 띠가
      // 카드 전체 높이로 stretch 되게 한다.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(icon, size: 17, color: accentColor),
                        ),
                        const SizedBox(width: 9),
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
              ),
            ),
          ],
        ),
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
