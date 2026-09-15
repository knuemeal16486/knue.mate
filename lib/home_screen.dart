import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bus_timetable_data.dart';
import 'calendar_screen.dart';
import 'campus_run_screen.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'club_events_screen.dart';
import 'constants.dart';
import 'housing_screen.dart';
import 'notice_model.dart';
import 'notice_screen.dart';
import 'firebase_sync_service.dart';
import 'meal_rating.dart';
import 'notice_service.dart';
import 'offline_cache.dart';
import 'root_screen.dart';
import 'schedule_model.dart';
import 'staff_contacts_screen.dart';
import 'native_ad_card.dart';
import 'ui_utils.dart';

/// 홈 대시보드 (Apple Inset Grouped & Settings Aesthetic)
/// 애플 설정(Settings) 및 iOS 기본 앱 특유의 절제된 심플함,
/// 정교한 스퀘어클(Squircle) 시스템 아이콘, 인셋 그룹(Inset Grouped) 레이아웃을
/// 완벽하게 반영한 미니멀하고 직관적인 홈 화면.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scraper = KnueScraper();

  // 식단 상태
  bool _mealLoading = true;
  bool _mealError = false;
  MealType _nextMealType = MealType.breakfast;
  List<String> _nextMealItems = const [];
  MealSource _currentMealSource = MealSource.a;

  /// 다음 끼니의 평가 집계. Firestore가 막혀 있으면 null로 남고, 그때는
  /// 카드에 아무것도 표시하지 않는다(빈 자리를 만들지 않기 위해).
  MealRatingSummary? _mealRating;

  // 버스 상태
  bool _busLoading = true;
  bool _busError = false;
  String _busLabel = "운행 종료";
  String _busRemainingHint = "";

  // 키워드 알림 상태
  bool _keywordLoading = true;
  bool _keywordError = false;
  List<Notice> _keywordMatches = const [];

  // 공지 미리보기 상태
  bool _noticeLoading = true;
  bool _noticeError = false;
  List<Notice> _favNotices = const [];

  // 일정 상태
  bool _upcomingLoading = true;
  bool _upcomingError = false;
  List<CalendarEvent> _upcomingAcademic = const [];
  List<DdayItem> _upcomingDdays = const [];

  // 동아리 행사 상태
  bool _clubLoading = true;
  bool _clubError = false;
  List<ClubEvent> _clubEvents = const [];

  // 강내면 실시간 날씨
  KnueWeatherInfo? _weather;

  @override
  void initState() {
    super.initState();
    _currentMealSource = defaultSourceNotifier.value;
    _refreshAll();

    // 리스너 연결.
    // 각 카드는 캐시를 먼저 그리고 네트워크 갱신은 뒤에서 돈다. 갱신이 끝나면
    // revision이 올라오고, 그때 최신 데이터로 다시 그린다.
    defaultSourceNotifier.addListener(_onSourceChanged);
    NoticeCache.revision.addListener(_onNoticeCacheUpdated);
    PreferencesService.favoriteBoards.addListener(_onNoticeCacheUpdated);
    PreferencesService.noticeKeywords.addListener(_onNoticeCacheUpdated);
    ClubEventCache.revision.addListener(_loadClubEvents);
    MealCache.revision.addListener(_loadMeal);
    CalendarCache.revision.addListener(_loadUpcoming);
  }

  @override
  void dispose() {
    defaultSourceNotifier.removeListener(_onSourceChanged);
    NoticeCache.revision.removeListener(_onNoticeCacheUpdated);
    PreferencesService.favoriteBoards.removeListener(_onNoticeCacheUpdated);
    PreferencesService.noticeKeywords.removeListener(_onNoticeCacheUpdated);
    ClubEventCache.revision.removeListener(_loadClubEvents);
    MealCache.revision.removeListener(_loadMeal);
    CalendarCache.revision.removeListener(_loadUpcoming);
    super.dispose();
  }

  void _onSourceChanged() {
    _currentMealSource = defaultSourceNotifier.value;
    _loadMeal();
  }

  void _onNoticeCacheUpdated() {
    _loadKeywordAlerts();
    _loadNoticePreview();
  }

  /// 사용자가 직접 당겨서 새로고침할 때. 갱신 제한을 풀어 즉시 다시 받아온다.
  Future<void> _pullToRefresh() async {
    RefreshThrottle.reset();
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadMeal(),
      _loadBus(),
      _loadKeywordAlerts(),
      _loadNoticePreview(),
      _loadUpcoming(),
      _loadClubEvents(),
      _loadWeather(),
    ]);
  }

  // ---------------------------------------------------------------------
  // 데이터 로딩 로직
  // ---------------------------------------------------------------------

  ({MealType type, DateTime date}) _resolveNextMeal(DateTime now) {
    final source = defaultSourceNotifier.value;
    for (final type in [MealType.breakfast, MealType.lunch, MealType.dinner]) {
      final status = statusFor(type, now, now, source: source);
      if (status == ServeStatus.waiting || status == ServeStatus.open) {
        return (type: type, date: now);
      }
    }
    final tomorrowFirstMeal = source == MealSource.b
        ? MealType.lunch
        : MealType.breakfast;
    return (type: tomorrowFirstMeal, date: now.add(const Duration(days: 1)));
  }

  Future<void> _loadMeal() async {
    if (mounted)
      setState(() {
        _mealLoading = true;
        _mealError = false;
      });
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
      // 별점은 식단이 그려진 뒤에 따로 채운다 — 이걸 기다리느라 카드가
      // 늦게 뜨면 안 된다.
      _loadMealRating(next.date, source, next.type);
    } catch (e) {
      if (mounted)
        setState(() {
          _mealLoading = false;
          _mealError = true;
        });
    }
  }

  Future<void> _loadMealRating(
    DateTime date,
    MealSource source,
    MealType type,
  ) async {
    final summary = await FirebaseSyncService.getMealRatingSummary(
      date: date,
      source: source,
      mealType: type,
    );
    if (!mounted) return;
    setState(() => _mealRating = summary);
  }

  Future<void> _loadBus() async {
    if (mounted)
      setState(() {
        _busLoading = true;
        _busError = false;
      });
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
        if (best != null && bestRoute != null) {
          _busLabel = "$bestRoute번";
          _busRemainingHint = "$best 출발";
        } else {
          _busLabel = "운행 종료";
          _busRemainingHint = "첫차 05:30";
        }
        _busLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _busLoading = false;
          _busError = true;
        });
    }
  }

  Future<void> _loadKeywordAlerts() async {
    if (mounted)
      setState(() {
        _keywordLoading = true;
        _keywordError = false;
      });
    try {
      final cached = await NoticeCache.load() ?? [];
      final keywords = PreferencesService.noticeKeywords.value;
      final favBoards = PreferencesService.favoriteBoards.value;
      final matches = keywords.isEmpty
          ? <Notice>[]
          : cached
                .where(
                  (n) => favBoards.isEmpty || favBoards.contains(n.category),
                )
                .where(
                  (n) => keywords.any(
                    (kw) => n.title.toLowerCase().contains(kw.toLowerCase()),
                  ),
                )
                .take(3)
                .toList();
      if (!mounted) return;
      setState(() {
        _keywordMatches = matches;
        _keywordLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _keywordLoading = false;
          _keywordError = true;
        });
    }
  }

  Future<void> _loadNoticePreview() async {
    if (mounted) {
      setState(() {
        _noticeLoading = _favNotices.isEmpty;
        _noticeError = false;
      });
    }
    try {
      var favBoards = PreferencesService.favoriteBoards.value.toSet();
      if (favBoards.isEmpty) {
        favBoards = const {"대학소식", "학사공지", "청람소양", "장학금"};
      }

      // 1. 오프라인 캐시에서 먼저 즉시 로드
      final cached = await NoticeCache.load();
      if (cached != null && cached.isNotEmpty && mounted) {
        final cachedFiltered = cached
            .where((n) => favBoards.contains(n.category))
            .take(4)
            .toList();
        if (cachedFiltered.isNotEmpty) {
          setState(() {
            _favNotices = cachedFiltered;
            _noticeLoading = false;
          });
        }
      }

      // 2. 최신 공지 스크래핑
      final fetched = await _scraper.fetchAllNotices(onlyCategories: favBoards);
      final filtered = fetched
          .where((n) => favBoards.contains(n.category))
          .take(4)
          .toList();

      if (!mounted) return;
      setState(() {
        if (filtered.isNotEmpty) {
          _favNotices = filtered;
        }
        _noticeLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _noticeLoading = false;
          if (_favNotices.isEmpty) {
            _noticeError = true;
          }
        });
      }
    }
  }

  Future<void> _loadUpcoming() async {
    if (mounted)
      setState(() {
        _upcomingLoading = true;
        _upcomingError = false;
      });
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final events = await _scraper.fetchCalendarEvents(now.year, now.month);
      final upcoming = events.where((e) {
        final end = DateTime(e.endDate.year, e.endDate.month, e.endDate.day);
        return !end.isBefore(today);
      }).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));

      final ddays = List<DdayItem>.from(PreferencesService.ddayItems.value)
        ..sort((a, b) => a.daysLeft(now).compareTo(b.daysLeft(now)));

      if (!mounted) return;
      setState(() {
        _upcomingAcademic = upcoming.take(3).toList();
        _upcomingDdays = ddays.take(3).toList();
        _upcomingLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _upcomingLoading = false;
          _upcomingError = true;
        });
    }
  }

  Future<void> _loadClubEvents() async {
    if (mounted)
      setState(() {
        _clubLoading = true;
        _clubError = false;
      });
    try {
      final all = await ClubEventService.fetchAll();
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
      if (mounted)
        setState(() {
          _clubLoading = false;
          _clubError = true;
        });
    }
  }

  Future<void> _loadWeather() async {
    try {
      final info = await fetchGangnaeWeather();
      if (!mounted || info == null) return;
      setState(() {
        _weather = info;
        _greeting = pickGreeting(DateTime.now(), weather: info);
      });
    } catch (_) {}
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
          backgroundColor: KnueTokens.bg(isDark),
          body: RefreshIndicator(
            onRefresh: _pullToRefresh,
            color: color,
            edgeOffset: 120,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 브랜드 히어로 헤더 (청람 그라디언트 + 오늘의 브리핑)
                  //    — 청람밥상/청람버스 헤더와 같은 색 공식을 써서 첫 화면부터
                  //    같은 앱이라는 감각을 만든다.
                  _buildHeroHeader(color, isDark),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 2. 주요 서비스 빠른 실행 (테마색 단일 톤)
                        const KnueSectionHeader(title: "빠른 실행"),
                        _buildQuickActionsGrid(color, isDark),
                        const SizedBox(height: 22),

                        // 3. 학사일정 및 D-Day
                        KnueSectionHeader(
                          title: "학사일정 & D-DAY",
                          actionText: "전체보기",
                          actionColor: color,
                          onAction: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CalendarScreen(),
                            ),
                          ),
                        ),
                        _buildUpcomingInsetGroup(color, isDark),
                        const SizedBox(height: 20),

                        // 스폰서 / 추천 네이티브 카드
                        const KnueNativeAdCard(placement: 'home'),
                        const SizedBox(height: 22),

                        // 4. 키워드 맞춤 알림
                        KnueSectionHeader(
                          title: "키워드 알림",
                          actionText: "설정",
                          actionColor: color,
                          onAction: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NoticeScreen(),
                            ),
                          ),
                        ),
                        _buildKeywordInsetGroup(color, isDark),
                        const SizedBox(height: 22),

                        // 5. 청람 공지사항
                        KnueSectionHeader(
                          title: "청람 공지사항",
                          actionText: "전체보기",
                          actionColor: color,
                          onAction: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NoticeScreen(),
                            ),
                          ),
                        ),
                        _buildNoticeInsetGroup(color, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // 1. 애플 스타일 헤더 (iOS Large Title & Date Caption)
  // ---------------------------------------------------------------------

  Widget _buildHeroHeader(Color color, bool isDark) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 청람밥상 앱바와 같은 펄 공식 + 날씨 앰비언트(비, 바람, 눈 등) 미세 조색
        gradient: KnueWeatherAtmosphere.headerGradient(color, isDark, _weather),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // 날씨에 맞춰 은은하게 떠다니는 비/눈/바람 결. 배경색은 이미
          // KnueWeatherAtmosphere가 날씨별로 조색해 두므로, 여기서는 움직임만
          // 더한다.
          Positioned.fill(child: WeatherParticlesOverlay(weather: _weather)),
          _buildHeroHeaderContent(),
        ],
      ),
    );
  }

  Widget _buildHeroHeaderContent() {
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko_KR').format(now);
    return SafeArea(
      bottom: false,
      // 헤더 안의 모든 흰 글씨·아이콘에 그림자를 한 번에 건다. 개별 Text가
      // shadows를 지정하지 않으면 이 값이 상속되므로, 색을 밝은 노랑으로
      // 바꿔도 글씨가 묻히지 않는다.
      child: DefaultTextStyle.merge(
        style: TextStyle(shadows: KnueTokens.headerTextShadow),
        child: IconTheme.merge(
          data: IconThemeData(shadows: KnueTokens.headerTextShadow),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: Colors.white.withValues(alpha: 0.9),
                            shadows: KnueTokens.headerTextShadow,
                          ),
                        ),
                        if (_weather != null)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              "${_weather!.emoji} ${_weather!.temp.round()}°",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.95),
                                fontFeatures: KnueTokens.tabularFigures,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "KNUE Mate",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _greeting,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: Colors.white,
                    shadows: KnueTokens.headerTextShadow,
                  ),
                ),
                const SizedBox(height: 16),
                // 오늘의 브리핑 — 식단/버스 요약을 반투명 타일로 헤더 안에 담는다.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildHeroTile(
                          icon: Icons.restaurant_menu_rounded,
                          title: "오늘의 식단",
                          chip:
                              "${_nextMealType.label} · ${_currentMealSource.shortLabel}",
                          footer: "식단 상세",
                          extra: _buildHeroMealRating(),
                          onTap: () =>
                              RootNavigationScreen.switchTab(AppTab.meal),
                          body: _buildHeroMealBody(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildHeroTile(
                          icon: Icons.directions_bus_rounded,
                          title: "다음 버스",
                          chip: "조치원·청주",
                          footer: "실시간 위치",
                          onTap: () =>
                              RootNavigationScreen.switchTab(AppTab.bus),
                          body: _buildHeroBusBody(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 히어로 위 흰 글씨용 그림자. 유리 타일은 반투명 흰색을 덧씌워 배경을 더
  /// 밝게 만들기 때문에, 헤더 본문보다 오히려 대비가 불리하다 — 같은 그림자를
  /// 타일 글씨에도 깐다.
  List<Shadow> get _heroShadow => KnueTokens.headerTextShadow;

  /// 히어로 안의 반투명 브리핑 타일 한 장. 흰 텍스트 + 유리 질감.
  Widget _buildHeroTile({
    required IconData icon,
    required String title,
    required String chip,
    required String footer,
    required VoidCallback onTap,
    required Widget body,

    /// 하단 링크 줄 위에 덧붙일 한 줄(식단 타일의 별점 등).
    Widget? extra,
  }) {
    return AnimatedScaleButton(
      onTap: onTap,
      scaleFactor: 0.96,
      child: GlassContainer(
        opacity: 0.12,
        blur: 12,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(12),
        border: Border.all(
          color: KnueWeatherAtmosphere.tileBorderColor(_weather),
          width: 1.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 17, color: Colors.white),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: Colors.white,
                shadows: _heroShadow,
              ),
            ),
            const SizedBox(height: 5),
            body,
            const Spacer(),
            if (extra != null) ...[const SizedBox(height: 6), extra],
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  footer,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 식단 타일의 별점 줄. 평가가 하나도 없거나 불러오지 못했으면 아무것도
  /// 그리지 않는다 — "0.0점" 같은 표시가 오히려 오해를 부른다.
  Widget? _buildHeroMealRating() {
    final s = _mealRating;
    if (s == null || !s.hasRatings) return null;
    final style = s.majorityStyle;
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 13, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          s.average.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFeatures: KnueTokens.tabularFigures,
            shadows: _heroShadow,
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            style == null ? "· ${s.count}명" : "· ${style.label}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
              fontFeatures: KnueTokens.tabularFigures,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroMealBody() {
    if (_mealLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (_mealError) {
      return Text(
        "불러오기 실패 · 당겨서 새로고침",
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      );
    }
    if (_nextMealItems.isEmpty) {
      return Text(
        "등록된 식단 없음",
        style: TextStyle(
          fontSize: 11.5,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      );
    }
    return Text(
      _nextMealItems.take(3).join('\n'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: Colors.white,
      ),
    );
  }

  Widget _buildHeroBusBody() {
    if (_busLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (_busError) {
      return Text(
        "불러오기 실패 · 당겨서 새로고침",
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _busLabel,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
            fontFeatures: KnueTokens.tabularFigures,
          ),
        ),
        Text(
          _busRemainingHint,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.8),
            fontFeatures: KnueTokens.tabularFigures,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 2. 주요 서비스 빠른 실행 — 테마색 단일 톤 (2색 체계)
  // ---------------------------------------------------------------------

  Widget _buildQuickActionsGrid(Color themeClr, bool isDark) {
    // 공연·행사 캡션: 예정 행사 수를 라벨 아래 그레이로만 — 뱃지 금지.
    final String clubCaption = _clubLoading
        ? "확인 중"
        : _clubError
        ? "확인 실패"
        : _clubEvents.isEmpty
        ? "예정 없음"
        : "행사 ${_clubEvents.length}건";

    return KnueCard(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          // 네 개가 나란히 붙어 있어 같은 색이면 가장 단조로워 보이는 자리.
          // 게시판과 같은 잉크 팔레트로 서로만 구분되게 한다.
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.festival_rounded,
              tint: KnueTokens.categoryColor('공연·행사', isDark),
              label: "공연·행사",
              caption: clubCaption,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClubEventsScreen()),
              ),
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.apartment_rounded,
              tint: KnueTokens.categoryColor('자취방', isDark),
              label: "자취방",
              caption: "월세·연락처",
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HousingScreen()),
              ),
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.directions_run_rounded,
              tint: KnueTokens.categoryColor('캠퍼스런', isDark),
              label: "캠퍼스런",
              caption: "얼른뛰어!",
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CampusRunScreen()),
              ),
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.phone_in_talk_rounded,
              tint: KnueTokens.categoryColor('교직원 연락처', isDark),
              label: "연락처",
              caption: "교직원",
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaffContactsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required Color tint,
    required String label,
    required String caption,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return AnimatedScaleButton(
      onTap: onTap,
      scaleFactor: 0.92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // 잉크 워시 배경 + 같은 색 아이콘 — 원색 스쿼클보다 훨씬 잔잔하다.
              color: tint.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            caption,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: KnueTokens.caption(isDark),
              fontFeatures: KnueTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 4. 학사일정 & D-Day (Inset Grouped)
  // ---------------------------------------------------------------------

  Widget _buildUpcomingInsetGroup(Color themeClr, bool isDark) {
    return KnueCard(
      isDark: isDark,
      child: _upcomingLoading
          ? const _AppleLoading()
          : _upcomingError
          ? _AppleErrorRetry(onRetry: _loadUpcoming)
          : Column(
              children: [
                // D-Day 목록
                if (_upcomingDdays.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _upcomingDdays.map((d) {
                        final left = d.daysLeft(DateTime.now());
                        // 2색 체계: 임박(D-3 이내)만 보조색(앰버)으로 켠다.
                        final urgent = left >= 0 && left <= 3;
                        final warmClr = KnueTokens.warm(isDark);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: urgent
                                ? warmClr.withValues(
                                    alpha: isDark ? 0.16 : 0.10,
                                  )
                                : (isDark
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFFF2F2F7)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDday(left),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: KnueTokens.tabularFigures,
                                  color: urgent ? warmClr : themeClr,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                d.title,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1C1C1E),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_upcomingAcademic.isNotEmpty)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
                    ),
                ],

                // 학사 일정 목록
                if (_upcomingAcademic.isEmpty && _upcomingDdays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(
                      child: Text(
                        "예정된 일정이 없습니다",
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ),
                  )
                else if (_upcomingAcademic.isNotEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _upcomingAcademic.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      indent: 48,
                      thickness: 0.5,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
                    ),
                    itemBuilder: (context, index) {
                      final event = _upcomingAcademic[index];
                      final dateStr =
                          "${event.startDate.month}/${event.startDate.day}";
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            _TintSquircle(
                              icon: Icons.event_note_rounded,
                              tint: themeClr,
                              isDark: isDark,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF000000),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------
  // 5. 키워드 맞춤 알림 (Inset Grouped)
  // ---------------------------------------------------------------------

  Widget _buildKeywordInsetGroup(Color themeClr, bool isDark) {
    final registeredKeywords = PreferencesService.noticeKeywords.value;

    return KnueCard(
      isDark: isDark,
      child: _keywordLoading
          ? const _AppleLoading()
          : _keywordError
          ? _AppleErrorRetry(onRetry: _loadKeywordAlerts)
          : (registeredKeywords.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _TintSquircle(
                          icon: Icons.notifications_active_rounded,
                          tint: themeClr,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "관심 키워드 등록",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF000000),
                                ),
                              ),
                              Text(
                                "장학, 수강신청 등 키워드 알림 받기",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? const Color(0xFF8E8E93)
                                      : const Color(0xFF8E8E93),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NoticeScreen(),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: themeClr,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "등록",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : (_keywordMatches.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: Center(
                            child: Text(
                              "일치하는 새로운 키워드 공지가 없습니다",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _keywordMatches.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 0.5,
                            indent: 48,
                            thickness: 0.5,
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                          ),
                          itemBuilder: (context, index) {
                            final notice = _keywordMatches[index];
                            return _buildSettingsNoticeRow(
                              notice: notice,
                              // 게시판마다 고정 식별색 — 어느 게시판 글인지
                              // 제목을 읽기 전에 색으로 먼저 구분된다.
                              iconColor: KnueTokens.categoryColor(
                                notice.category,
                                isDark,
                              ),
                              icon: Icons.notifications_rounded,
                              isDark: isDark,
                              onTap: () => _openNoticeUrl(notice.link),
                            );
                          },
                        ))),
    );
  }

  // ---------------------------------------------------------------------
  // 6. 청람 공지사항 (Inset Grouped)
  // ---------------------------------------------------------------------

  Widget _buildNoticeInsetGroup(Color themeClr, bool isDark) {
    return KnueCard(
      isDark: isDark,
      child: _noticeLoading
          ? const _AppleLoading()
          : _noticeError
          ? _AppleErrorRetry(onRetry: _loadNoticePreview)
          : (_favNotices.isEmpty
                ? InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NoticeScreen()),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          _TintSquircle(
                            icon: Icons.campaign_rounded,
                            tint: themeClr,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "공지사항 바로가기",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "대학소식, 학사공지 등 실시간 확인하기",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? const Color(0xFF8E8E93)
                                        : const Color(0xFF8E8E93),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: isDark ? Colors.white38 : Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _favNotices.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      indent: 48,
                      thickness: 0.5,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
                    ),
                    itemBuilder: (context, index) {
                      final notice = _favNotices[index];
                      return _buildSettingsNoticeRow(
                        notice: notice,
                        iconColor: KnueTokens.categoryColor(
                          notice.category,
                          isDark,
                        ),
                        icon: Icons.campaign_rounded,
                        isDark: isDark,
                        onTap: () => _openNoticeUrl(notice.link),
                      );
                    },
                  )),
    );
  }

  Widget _buildSettingsNoticeRow({
    required Notice notice,
    required Color iconColor,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _TintSquircle(icon: icon, tint: iconColor, isDark: isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          // 뱃지도 아이콘과 같은 게시판 색을 옅게 깔아,
                          // 둘이 한 덩어리로 읽히게 한다.
                          color: iconColor.withValues(
                            alpha: isDark ? 0.20 : 0.11,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          notice.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                      ),
                      if (notice.isNew) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // 새 공지 = 시간 신호이므로 보조색(앰버).
                            color: KnueTokens.warm(isDark),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notice.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 헬퍼 메소드
  // ---------------------------------------------------------------------

  Future<void> _openNoticeUrl(String? url) async {
    if (url == null || url.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NoticeScreen()),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NoticeScreen()),
      );
    }
  }

  /// 이번 접속에 쓸 인사말. 날씨가 로드되면 날씨 맞춤형 멘트로 업데이트된다.
  String _greeting = pickGreeting(DateTime.now());

  String _formatDday(int left) {
    if (left == 0) return "D-DAY";
    return left > 0 ? "D-$left" : "D+${-left}";
  }
}

// ===========================================================================
// 컴포넌트: 테마색 워시 스쿼클 아이콘 (2색 체계)
// — 원색 배경 + 흰 아이콘이던 iOS 설정st 스쿼클을, 틴트 워시 배경 + 틴트
//   아이콘으로 바꿔 어떤 테마색에서도 무지개가 생기지 않게 한다.
// ===========================================================================

class _TintSquircle extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final bool isDark;

  const _TintSquircle({
    required this.icon,
    required this.tint,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(icon, size: 16, color: tint)),
    );
  }
}

// ===========================================================================
// 컴포넌트: 로딩 및 에러
// ===========================================================================

class _AppleLoading extends StatelessWidget {
  const _AppleLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _AppleErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _AppleErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text("불러오기 실패 · 다시 시도", style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF3B30),
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
