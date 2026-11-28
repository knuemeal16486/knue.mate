import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'gemini_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'meal_rating_service.dart';
import 'root_screen.dart';
import 'ui_utils.dart';
import 'meal_rating.dart';
import 'native_ad_card.dart';
import 'features/meal/cafeteria_info_sheet.dart';

// [개편] 식단 탭 전용 페이지 (기존 MealMainScreen)
// [복원] 식단 탭 전용 페이지 (기존 스타일 복구)
class MealTabPage extends StatefulWidget {
  const MealTabPage({super.key});
  @override
  State<MealTabPage> createState() => _MealTabPageState();
}

class _MealTabPageState extends State<MealTabPage> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (idx) => setState(() => _currentIndex = idx),
      children: [
        TodayMealPage(onSwitchTab: _onTabTapped),
        MonthlyMealPage(onSwitchTab: _onTabTapped),
      ],
    );
  }
}

/// 상단 앱바에 자연스럽게 녹아드는 오늘/월간 뷰 모드 캡슐형 세그먼트 버튼
Widget _buildMealModeSegment({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int>? onSwitchTab,
}) {
  if (onSwitchTab == null) return const SizedBox.shrink();
  final primaryColor = themeColor.value;
  final onBrand = KnueTokens.onAccent(primaryColor);
  final activeText = KnueTokens.accentForeground(primaryColor, false);
  return Container(
    height: 32,
    decoration: BoxDecoration(
      color: onBrand == Colors.white
          ? Colors.black.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: onBrand.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          selected: selectedIndex == 0,
          label: "오늘 식단 보기",
          child: GestureDetector(
            onTap: () {
              KnueHaptics.selection();
              onSwitchTab(0);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selectedIndex == 0 ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                "오늘",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selectedIndex == 0 ? FontWeight.w800 : FontWeight.w600,
                  color: selectedIndex == 0 ? activeText : onBrand.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          selected: selectedIndex == 1,
          label: "월간 식단 보기",
          child: GestureDetector(
            onTap: () {
              KnueHaptics.selection();
              onSwitchTab(1);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selectedIndex == 1 ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                "월간",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selectedIndex == 1 ? FontWeight.w800 : FontWeight.w600,
                  color: selectedIndex == 1 ? activeText : onBrand.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// =============================================================================
// 2. 오늘 식단 페이지
// =============================================================================
class TodayMealPage extends StatefulWidget {
  final ValueChanged<int>? onSwitchTab;
  const TodayMealPage({super.key, this.onSwitchTab});
  @override
  State<TodayMealPage> createState() => _TodayMealPageState();
}

class _TodayMealPageState extends State<TodayMealPage>
    with AutomaticKeepAliveClientMixin {
  DateTime _date = DateTime.now();
  MealType _selected = MealType.lunch;
  MealSource _source = defaultSourceNotifier.value;
  bool _loading = false;
  String? _error;
  bool _alarmOn = false;

  /// 교직원 식당 안내(선택식 메뉴·가격)를 열어 봤는지. 안 열어 봤으면 ⓘ에
  /// 빨간 점을 단다 — 거기 메뉴·가격이 있는 걸 사람들이 잘 몰랐다(2026-11-12).
  /// 읽기 전엔 true로 둬서 점이 잠깐 깜빡이지 않게 한다.
  bool _staffInfoSeen = true;

  Map<String, List<String>> _meals = {
    "breakfast": [],
    "lunch": [],
    "dinner": [],
  };
  int _reqId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _updateSelectionByTime();
    _loadAlarmState();
    fetchMeals();
  }

  Future<void> _loadAlarmState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _alarmOn = prefs.getBool('alarm_enabled') ?? false;
        _staffInfoSeen = prefs.getBool(kStaffMenuInfoSeenKey) ?? false;
      });
    }
  }

  Future<void> _markStaffInfoSeen() async {
    if (_staffInfoSeen) return;
    setState(() => _staffInfoSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kStaffMenuInfoSeenKey, true);
    } catch (_) {
      // 화면엔 이미 반영 — 기록만 못 하면 다음에 점이 한 번 더 보일 뿐.
    }
  }

  void _updateSelectionByTime() {
    // 위젯·홈 카드와 같은 규칙(widgetMealSlot) — 식당마다 운영 시간이 다르다.
    _selected = mealTabDefaultType(_source, DateTime.now());
  }

  Future<void> fetchMeals() async {
    final int myReq = ++_reqId;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await fetchMealApi(_date, _source);
      if (myReq != _reqId) return;
      _applyMealsFromBackend(res);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted && myReq == _reqId) {
        setState(() {
          _error = "정보 없음";
          _loading = false;
          _meals = {"breakfast": [], "lunch": [], "dinner": []};
        });
      }
    }
  }

  void _applyMealsFromBackend(dynamic decoded) {
    if (decoded is! Map) return;
    final meals = decoded["meals"];
    if (meals is! Map) return;
    _meals = {
      "breakfast": asStringList(
        meals["조식"] ?? meals["아침"] ?? meals["breakfast"],
      ),
      "lunch": asStringList(meals["중식"] ?? meals["점심"] ?? meals["lunch"]),
      "dinner": asStringList(meals["석식"] ?? meals["저녁"] ?? meals["dinner"]),
    };
  }

  void _goToday() {
    setState(() => _date = DateTime.now());
    fetchMeals();
  }

  void _changeDate(int deltaDays) {
    setState(() {
      _date = _date.add(Duration(days: deltaDays));
    });
    fetchMeals();
  }

  Future<void> _scheduleAlarmsBySource(MealSource source) async {
    final now = DateTime.now();

    Future<void> schedule(
      int id,
      int h,
      int m,
      String title,
      String body,
    ) async {
      await NotificationService().scheduleAlarm(
        id: id,
        title: title,
        body: body,
        scheduledTime: DateTime(now.year, now.month, now.day, h, m),
      );
    }

    await NotificationService().cancelAll();

    // 식당 이름은 MealSource에서 가져온다 — 문구에 직접 박아두면 출처가 바뀔 때
    // 또 어긋난다.
    final name = source.shortLabel;
    if (source == MealSource.a) {
      await schedule(1, 7, 30, "$name 아침 식사 ☀️", "아침 식사가 시작되었습니다. 든든하게 챙겨 드세요!");
      await schedule(2, 8, 50, "$name 아침 마감 임박 ⏰", "10분 뒤 배식이 종료됩니다.");
      await schedule(3, 11, 30, "$name 점심 식사 🍽️", "맛있는 점심 시간입니다!");
      await schedule(4, 13, 20, "$name 점심 마감 임박 🏃‍♂️", "10분 뒤 점심 식사가 종료됩니다.");
      await schedule(5, 17, 30, "$name 저녁 식사 🌙", "저녁 식사가 준비되었습니다.");
      await schedule(6, 18, 50, "$name 저녁 마감 임박 ⚠️", "10분 뒤 저녁 배식이 끝납니다.");
    } else {
      await schedule(3, 11, 00, "$name 점심 시작 🍽️", "$name 점심 식사가 시작되었습니다!");
      await schedule(4, 13, 50, "$name 점심 마감 임박 🏃‍♂️", "10분 뒤 식당이 문을 닫습니다.");
      await schedule(5, 17, 00, "$name 저녁 시작 🌙", "$name 저녁 식사 시간입니다.");
      await schedule(6, 18, 20, "$name 저녁 마감 임박 ⚠️", "10분 뒤 저녁 운영이 종료됩니다.");
    }
  }

  Future<void> _handleAlarmToggle() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      showToast(context, "모바일에서만 가능합니다.");
      return;
    }
    final newState = !_alarmOn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_enabled', newState);
    setState(() => _alarmOn = newState);

    if (newState) {
      // [수정] 권한을 먼저 요청하고, 그 결과(bool)를 받아 허가된 경우에만 알람 예약
      final bool isGranted = await NotificationService()
          .checkAndRequestPermission();

      if (!isGranted) {
        // 권한 거부 — 알람 상태를 OFF로 되돌리고 안내
        await prefs.setBool('alarm_enabled', false);
        if (!mounted) return;
        setState(() => _alarmOn = false);
        showToast(context, "알림 권한이 필요합니다. 설정 > 앱 > 알림에서 허용해주세요.");
        return;
      }

      await _scheduleAlarmsBySource(_source);
      if (!mounted) return;
      final restaurantName = _source.shortLabel;
      showToast(context, "$restaurantName 식당 시간으로 알림이 설정되었습니다.");
    } else {
      await NotificationService().cancelAll();
      if (!mounted) return;
      showToast(context, "알림이 해제되었습니다.");
    }
  }

  Future<void> _onSourceChangedWithAlarmUpdate(MealSource s) async {
    setState(() {
      _source = s;
      // 새 식당이 안 하는 끼니(교직원 식당 조식)를 보고 있었으면 지금 끼니로.
      if (mealTimeRangeFor(_selected, s) == null) {
        _selected = mealTabDefaultType(s, DateTime.now());
      }
    });
    PreferencesService.saveMealSource(s);

    if (_alarmOn) {
      await _scheduleAlarmsBySource(s);
      if (mounted) {
        final restaurantName = s.shortLabel;
        showToast(context, "$restaurantName 시간으로 알림이 업데이트되었습니다.");
      }
    }

    await fetchMeals();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBrand = KnueTokens.onAccent(primaryColor);
    final accentFg = KnueTokens.accentForeground(primaryColor, isDark);

    return Scaffold(
      backgroundColor: KnueTokens.bg(isDark),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 214,
              pinned: true,
              backgroundColor: primaryColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              leading: null, // 햄버거 메뉴 제거
              title: Row(
                children: [
                  Text(
                    "청람밥상",
                    style: TextStyle(
                      color: onBrand,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: KnueTokens.headerShadows(primaryColor),
                    ),
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      KnueHaptics.selection();
                      // 교직원 식당 안내를 열면 빨간 점을 끈다.
                      if (_source == MealSource.b) _markStaffInfoSeen();
                      _showCafeteriaInfo(context);
                    },
                    child: Semantics(
                      label: showStaffMenuInfoDot(_source, seen: _staffInfoSeen)
                          ? '식당 운영 정보, 선택식 메뉴와 가격 새 소식'
                          : '식당 운영 정보',
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: onBrand.withValues(alpha: 0.85),
                              size: 19,
                            ),
                            // 아이폰 앱 아이콘의 새 소식 점처럼.
                            if (showStaffMenuInfoDot(_source, seen: _staffInfoSeen))
                              const Positioned(
                                top: -2,
                                right: -2,
                                child: _NewDot(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                _buildMealModeSegment(
                  context: context,
                  selectedIndex: 0,
                  onSwitchTab: widget.onSwitchTab,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _handleAlarmToggle,
                  icon: Icon(
                    _alarmOn
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: onBrand,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    gradient: KnuePearl.headerGradient(
                      primaryColor,
                      isDark,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 54,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                _buildSegmentBtn(MealSource.a.label, MealSource.a),
                                _buildSegmentBtn(MealSource.b.label, MealSource.b),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        MealDateSwitcher(
                          date: _date,
                          isToday: isToday,
                          onPrev: _loading
                              ? null
                              : () {
                                  KnueHaptics.selection();
                                  _changeDate(-1);
                                },
                          onNext: _loading
                              ? null
                              : () {
                                  KnueHaptics.selection();
                                  _changeDate(1);
                                },
                          onToday: _loading
                              ? null
                              : () {
                                  KnueHaptics.selection();
                                  _goToday();
                                },
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: SingleChildScrollView(
          child: Column(
            children: [
              // [수정] Firebase 앱 초기화 여부 확인 후 Stream 사용
              StreamBuilder<QuerySnapshot>(
                stream: Firebase.apps.isEmpty
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                          .collection('notices')
                          .orderBy('createdAt', descending: true)
                          .limit(1)
                          .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final doc = snapshot.data!.docs.first;
                  final data = doc.data() as Map<String, dynamic>;
                  final String content = data['content'] ?? '';
                  if (content.isEmpty) return const SizedBox.shrink();

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: KnueTokens.cardShadow(isDark),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.campaign_rounded,
                          color: onBrand,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            content,
                            style: TextStyle(
                              color: onBrand,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _MealTabs(
                selected: _selected,
                source: _source,
                onSelect: (t) {
                  KnueHaptics.selection();
                  setState(() => _selected = t);
                },
              ),
              const SizedBox(height: kMealSectionGap),
              if (_loading)
                // 스피너 대신 카드 형태를 미리 그려 로딩→표시 전환에 덜컹임이 없게.
                _MealCardSkeleton(isDark: isDark)
              else if (_error != null)
                _ErrorCard(message: _error!)
              else
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() < 320 || _loading) return;
                    KnueHaptics.selection();
                    _changeDate(v < 0 ? 1 : -1);
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // 날짜·식당을 바꿀 때 내용이 살짝 밀려 들어오게 — 전환이 있었다는
                    // 것만 느껴질 정도의 12px.
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.035),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _MealDetailCard(
                      key: ValueKey("$_date-$_selected-$_source"),
                      status: statusFor(_selected, DateTime.now(), _date, source: _source),
                      type: _selected,
                      source: _source,
                      items: _meals[_selected.stdKey] ?? [],
                      isToday: isToday,
                      date: _date,
                    ),
                  ),
                ),
              if (_source == MealSource.b)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        KnueHaptics.selection();
                        _markStaffInfoSeen();
                        _showCafeteriaInfo(context);
                      },
                      icon: Icon(Icons.restaurant_rounded, size: 16, color: accentFg),
                      label: Text(
                        "선택식 상시 메뉴 · 가격 보기",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accentFg,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: KnueTokens.hairline(isDark)),
                        backgroundColor: KnueTokens.surface(isDark),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: KnueNativeAdCard(isCompact: true, placement: 'meal'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(String title, MealSource val) {
    final isSel = _source == val;
    return Expanded(
      child: GestureDetector(
        onTap: _loading ? null : () => _onSourceChangedWithAlarmUpdate(val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSel ? Colors.black87 : Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _showCafeteriaInfo(BuildContext context) {
    showCafeteriaInfoSheet(context, _source);
  }
}

// =============================================================================
// Helper Widgets
// =============================================================================

/// 교직원 식당 안내를 열어 봤는지 적는 키.
const String kStaffMenuInfoSeenKey = 'meal_staff_menu_info_seen';

/// ⓘ에 빨간 점을 달지 — 교직원 식당을 보고 있고 그 안내(선택식 메뉴·가격)를
/// 아직 안 열어 봤을 때. 순수 함수 — 테스트 대상.
bool showStaffMenuInfoDot(MealSource source, {required bool seen}) =>
    source == MealSource.b && !seen;

/// 새 소식 빨간 점(아이폰 앱 아이콘 배지처럼). 머리 색 위에서도 보이게 흰 테.
class _NewDot extends StatelessWidget {
  const _NewDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30), // iOS 시스템 빨강
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

/// 청람밥상의 끼니 탭(아침·점심·저녁)과 식단 카드 사이 간격.
const double kMealSectionGap = 8;

/// 날짜 위 알약에 쓸 말 — 오늘 기준. 순수 함수 — 테스트 대상.
String mealDayBadge(DateTime date, DateTime today) {
  final d = DateUtils.dateOnly(date).difference(DateUtils.dateOnly(today)).inDays;
  if (d == 0) return '오늘의 식단';
  if (d == -1) return '어제의 식단';
  if (d == 1) return '내일의 식단';
  return d < 0 ? '${-d}일 전 식단' : '$d일 후 식단';
}

/// 청람밥상 머리의 날짜 전환.
///
/// 날짜 위 알약은 **어느 날이든 같은 자리에** 그린다. 예전엔 오늘일 때만
/// "오늘의 식단"을 그려서, 다른 날로 넘기면 그 높이만큼 날짜 묶음이 짧아지고
/// (머리 높이는 240 고정) 날짜 아래가 비었다. 다른 날엔 눌러서 오늘로 돌아간다.
class MealDateSwitcher extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onToday;
  final Color primaryColor;

  const MealDateSwitcher({
    super.key,
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    this.onToday,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    const wd = ["", "월", "화", "수", "목", "금", "토", "일"];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AnimatedScaleButton(
            onTap: onPrev ?? () {},
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: isToday ? null : onToday,
                child: Semantics(
                  button: !isToday,
                  label: isToday ? null : '오늘 식단으로 돌아가기',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // 다른 날은 한 단계 옅게 — 오늘이 아님을 보여 주고, 누를 수 있다.
                      color: isToday
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mealDayBadge(date, DateTime.now()),
                          style: TextStyle(
                            color: isToday ? primaryColor : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!isToday) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.undo_rounded, size: 13, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${wd[date.weekday]}요일",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "${date.year}년 ${date.month.toString().padLeft(2, '0')}월 ${date.day.toString().padLeft(2, '0')}일",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          AnimatedScaleButton(
            onTap: onNext ?? () {},
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.chevron_right, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 3. 월간 식단 페이지
// =============================================================================
class MonthlyMealPage extends StatefulWidget {
  final ValueChanged<int>? onSwitchTab;
  const MonthlyMealPage({super.key, this.onSwitchTab});
  @override
  State<MonthlyMealPage> createState() => _MonthlyMealPageState();
}

class _MonthlyMealPageState extends State<MonthlyMealPage>
    with AutomaticKeepAliveClientMixin {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  MealSource _source = defaultSourceNotifier.value;
  MealType _selectedType = MealType.lunch;
  bool _loading = false;
  String? _error;
  Map<String, List<String>> _meals = {
    "breakfast": [],
    "lunch": [],
    "dinner": [],
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchForSelectedDate();
  }

  Future<void> _fetchForSelectedDate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await fetchMealApi(_selectedDate, _source);
      if (res is Map) {
        final meals = res["meals"];
        if (meals is Map) {
          _meals = {
            "breakfast": asStringList(
              meals["조식"] ?? meals["아침"] ?? meals["breakfast"],
            ),
            "lunch": asStringList(meals["중식"] ?? meals["점심"] ?? meals["lunch"]),
            "dinner": asStringList(
              meals["석식"] ?? meals["저녁"] ?? meals["dinner"],
            ),
          };
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = "정보 없음";
          _loading = false;
        });
    }
  }

  void _changeMonth(int delta) => setState(
    () => _focusedMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + delta,
      1,
    ),
  );

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      if (_focusedMonth.month != date.month)
        _focusedMonth = DateTime(date.year, date.month, 1);
    });
    _fetchForSelectedDate();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출
    final primaryColor = themeColor.value;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: AppleAppBarFlexibleSpace(
          themeColor: primaryColor,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "월간 식단",
          style: TextStyle(
            fontWeight: (!kIsWeb && Platform.isIOS) ? FontWeight.w800 : FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          _buildMealModeSegment(
            context: context,
            selectedIndex: 1,
            onSwitchTab: widget.onSwitchTab,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              final nextSource = _source == MealSource.a
                  ? MealSource.b
                  : MealSource.a;
              setState(() {
                _source = nextSource;
                if (nextSource == MealSource.b) {
                  _selectedDate = DateTime.now();
                  _focusedMonth = DateTime.now();
                }
              });
              _fetchForSelectedDate();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz, size: 15, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _source.shortLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 20,
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        "${_focusedMonth.year}.${_focusedMonth.month.toString().padLeft(2, '0')}",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      Text(
                        "일",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "월",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "화",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "수",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "목",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "금",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "토",
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CalendarGrid(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    onDateSelected: _onDateSelected,
                    primaryColor: primaryColor,
                    source: _source,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _buildLegendItem(
                            context,
                            isToday: true,
                            isSelected: false,
                            label: "오늘",
                            color: primaryColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _buildLegendItem(
                            context,
                            isToday: false,
                            isSelected: true,
                            label: "선택됨",
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_source == MealSource.b)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        "* ${MealSource.b.label}은 이번 주 식단만 제공합니다.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _MealTabs(
              selected: _selectedType,
              source: _source,
              onSelect: (t) => setState(() => _selectedType = t),
            ),
            const SizedBox(height: kMealSectionGap),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ErrorCard(message: _error!)
            else
              _MealDetailCard(
                status: statusFor(
                  _selectedType,
                  DateTime.now(),
                  _selectedDate,
                  source: _source,
                ),
                type: _selectedType,
                source: _source,
                items: _meals[_selectedType.stdKey] ?? [],
                isToday: DateUtils.isSameDay(_selectedDate, DateTime.now()),
                date: _selectedDate,
              ),
            // 광고는 식단 카드 아래 — 가장 자주 보는 탭이라 맨 위 광고는 지저분해
            // 보였다(사용자 결정, 2026-11-12. 0309885에서 위로 올렸던 것을 되돌림).
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: KnueNativeAdCard(isCompact: true, placement: 'meal'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    BuildContext context, {
    required bool isToday,
    required bool isSelected,
    required String label,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: (isToday && !isSelected)
                ? Border.all(color: color, width: 2)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// _BottomNavBar 는 RootNavigationScreen으로 이전되었으므로 삭제됨

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final Color primaryColor;
  final MealSource source;
  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDateSelected,
    required this.primaryColor,
    required this.source,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final daysInMonth = DateUtils.getDaysInMonth(
      focusedMonth.year,
      focusedMonth.month,
    );
    final firstDayWeekday = DateTime(
      focusedMonth.year,
      focusedMonth.month,
      1,
    ).weekday;
    final offset = firstDayWeekday % 7;
    DateTime now = DateTime.now();
    DateTime thisWeekMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    DateTime thisWeekFriday = thisWeekMonday.add(const Duration(days: 4));

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      itemCount: daysInMonth + offset,
      itemBuilder: (context, index) {
        if (index < offset) return const SizedBox();
        final day = index - offset + 1;
        final date = DateTime(focusedMonth.year, focusedMonth.month, day);
        bool isEnabled = true;
        if (source == MealSource.b) {
          if (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)
            isEnabled = false;
          DateTime target = DateTime(date.year, date.month, date.day);
          if (target.isBefore(thisWeekMonday) || target.isAfter(thisWeekFriday))
            isEnabled = false;
        }
        final isSel = DateUtils.isSameDay(date, selectedDate);
        final isToday = DateUtils.isSameDay(date, DateTime.now());
        Color textColor;
        if (!isEnabled)
          textColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
        else if (isSel)
          textColor = Colors.white;
        else if (date.weekday == DateTime.sunday)
          textColor = Colors.redAccent;
        else if (date.weekday == DateTime.saturday)
          textColor = Colors.blueAccent;
        else
          textColor = isDark ? Colors.white : Colors.black87;

        return GestureDetector(
          onTap: isEnabled ? () => onDateSelected(date) : null,
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSel ? primaryColor : null,
              border: (isToday && !isSel)
                  ? Border.all(color: primaryColor, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              "$day",
              style: TextStyle(
                color: textColor,
                fontWeight: (isSel || isToday)
                    ? FontWeight.bold
                    : FontWeight.normal,
                decoration: !isEnabled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MealTabs extends StatelessWidget {
  final MealType selected;
  final MealSource source;
  final ValueChanged<MealType> onSelect;
  const _MealTabs({
    required this.selected,
    required this.source,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? null : Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Row(
          children: MealType.values
              .where((t) {
                if (source == MealSource.b && t == MealType.breakfast)
                  return false;
                return true;
              })
              .map((t) {
                final isSel = t == selected;
                return Expanded(
                  child: AnimatedScaleButton(
                    onTap: () => onSelect(t),
                    scaleFactor: 0.95,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            t.icon,
                            size: 18,
                            color: isSel ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSel ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ),
      ),
    );
  }
}

/// 식단 카드 로딩 자리표시자. 실제 카드와 같은 여백·라운드를 써서
/// 데이터가 도착해도 레이아웃이 튀지 않는다.
class _MealCardSkeleton extends StatelessWidget {
  final bool isDark;
  const _MealCardSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KnueSkeleton(width: 110, height: 24, radius: 8, isDark: isDark),
              const Spacer(),
              KnueSkeleton(width: 76, height: 24, radius: 8, isDark: isDark),
            ],
          ),
          const SizedBox(height: 22),
          KnueSkeleton(width: 130, height: 14, radius: 6, isDark: isDark),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++) ...[
            Row(
              children: [
                KnueSkeleton(width: 6, height: 6, radius: 3, isDark: isDark),
                const SizedBox(width: 12),
                KnueSkeleton(
                  width: 150.0 + (i.isEven ? 60 : 0),
                  height: 15,
                  radius: 6,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: Colors.red)),
  );
}

// -----------------------------------------------------------------------------
// [중요] _MealDetailCard 클래스 정의 (누락되었던 부분)
// -----------------------------------------------------------------------------
class _MealDetailCard extends StatefulWidget {
  final ServeStatus status;
  final MealType type;
  final MealSource source;
  final List<String> items;
  final bool isToday;
  final DateTime date;

  const _MealDetailCard({
    super.key,
    required this.status,
    required this.type,
    required this.source,
    required this.items,
    required this.isToday,
    required this.date,
  });
  @override
  State<_MealDetailCard> createState() => _MealDetailCardState();
}

class _MealDetailCardState extends State<_MealDetailCard> {
  String? _caloriesInfo;
  bool _isCalorieLoading = false;
  bool _isRatingSubmitting = false;
  int? _boldItemIndex;

  @override
  void didUpdateWidget(_MealDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.date != widget.date ||
        oldWidget.source != widget.source) {
      _boldItemIndex = null;
    }
  }

  /// 별점을 **새로** 남길 수 있는 시간인지.
  ///
  /// 판단은 [isRatingOpen]이 한다. 예전엔 이 안에 식당·끼니별 시간표를 통째로
  /// 다시 적어 놓고 있었는데, [mealTimeRangeFor]와 값이 어긋나면 화면마다
  /// 다른 말을 하게 된다. 시간표는 한 곳에만 둔다.
  bool _isRatingAllowed() => isRatingOpen(
    widget.type,
    widget.source,
    DateTime.now(),
    widget.date,
  );

  /// 왜 지금은 새로 못 남기는지. 결과는 여전히 볼 수 있다는 걸 같이 알린다.
  String _getRatingTimeMessage() {
    if (!widget.isToday) return "오늘 식단만 평가할 수 있어요";

    if (mealTimeRangeFor(widget.type, widget.source) == null) {
      return "${widget.source.shortLabel} 식당 ${widget.type.label}은 운영하지 않아요";
    }

    final now = DateTime.now();
    final window = mealServiceWindow(widget.type, widget.source, now);
    if (window != null && now.isBefore(window.start)) {
      return "배식이 시작되면 평가할 수 있어요";
    }
    return "평가는 배식 종료 ${kRatingGracePeriod.inMinutes}분 뒤까지예요";
  }

  /// 별점과 배식 방식을 한 문서로 제출한다.
  /// [style]이 null이면 배식 방식 투표는 하지 않은 것으로 남긴다.
  ///
  /// 실제 제출·중복 방지 로직은 MealRatingService에 있다 — 홈 화면의
  /// "식사하셨나요?" 알림 팝업(meal_reminder.dart)도 같은 서비스를 써서
  /// 두 경로의 중복 방지 키가 어긋나지 않는다.
  Future<void> _submitRating(double rating, {ServingStyle? style}) async {
    // 평가 가능 시간인지 다시 확인
    if (!_isRatingAllowed()) {
      if (mounted) showToast(context, _getRatingTimeMessage());
      return;
    }

    // 체크와 플래그 설정 사이에 await가 없어야 동시 탭에도 한 번만 진행된다.
    if (_isRatingSubmitting) return;
    setState(() => _isRatingSubmitting = true);

    try {
      final errorMsg = await MealRatingService.submit(
        source: widget.source,
        type: widget.type,
        date: widget.date,
        rating: rating,
        style: style,
      );
      if (mounted) {
        if (errorMsg != null) {
          showToast(context, errorMsg);
        } else {
          final styleMsg = style == null ? '' : ' (${style.label})';
          showToast(context, "별점 $rating점$styleMsg 반영되었습니다. 감사합니다 ❤️");
        }
      }
    } catch (e) {
      if (mounted) showToast(context, "별점 저장 중 오류가 발생했어요.");
    } finally {
      if (mounted) setState(() => _isRatingSubmitting = false);
    }
  }

  /// 배식 방식 투표 결과. 어느 쪽이 우세한지와 표 차이를 한 줄로 보여준다.
  Widget _buildServingStyleBar(MealRatingSummary summary, Color warm) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final majority = summary.majorityStyle;
    final label = majority == null
        ? "배식 방식 의견이 갈려요"
        : "${majority.label} (${(summary.majorityRatio * 100).round()}%)";

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              majority == ServingStyle.self
                  ? Icons.restaurant_rounded
                  : Icons.set_meal_rounded,
              size: 15,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
                fontFeatures: KnueTokens.tabularFigures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          "자율 ${summary.selfVotes} · 정량 ${summary.fixedVotes}",
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white38 : Colors.black38,
            fontFeatures: KnueTokens.tabularFigures,
          ),
        ),
      ],
    );
  }

  /// 별점 단계(5.0 → 0.5)별로 몇 명이 투표했는지 막대로 보여준다.
  /// 별 배지를 눌러야만 펼쳐지는 상세 정보 — 기본 화면에는 평균만 보인다.
  Widget _buildRatingBreakdown(MealRatingSummary summary, Color warm) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxCount = summary.maxDistributionCount;
    // 5.0부터 내림차순 — 높은 점수부터 훑어보는 게 자연스럽다.
    final levels = List.generate(10, (i) => 5.0 - i * 0.5);

    return Column(
      children: levels.map((level) {
        final voteCount = summary.distribution[level] ?? 0;
        final ratio = maxCount == 0 ? 0.0 : voteCount / maxCount;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  level.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: warm.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(warm),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 20,
                child: Text(
                  "$voteCount",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStarRatingBar(double rating, Function(double) onRatingChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        double starValue = index + 1.0;
        IconData icon;
        if (rating >= starValue) {
          icon = Icons.star_rounded;
        } else if (rating >= starValue - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }

        return GestureDetector(
          onTapDown: (details) {
            double localPositionX = details.localPosition.dx;
            if (localPositionX < 15) {
              onRatingChanged(starValue - 0.5);
            } else {
              onRatingChanged(starValue);
            }
          },
          child: Icon(icon, color: Colors.amber, size: 30),
        );
      }),
    );
  }

  void _showRatingDialog() {
    // 마감된 뒤에도 **결과는 보여준다.** 닫히는 건 새 등록뿐이다.
    // 예전엔 토스트 한 줄만 띄우고 팝업을 열지 않아서, 배식이 끝나고 나면
    // 몇 명이 어떻게 평가했는지 볼 방법이 아예 없었다.
    final canRate = _isRatingAllowed();

    double currentRating = 4.0;
    ServingStyle? currentStyle;
    // 읽으러 온 사람에게는 분포를 처음부터 펼쳐 준다 — 그게 보러 온 것이다.
    bool showBreakdown = !canRate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              canRate ? "식단은 어떠셨나요?" : "${widget.type.label} 식단 평가",
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: Firebase.apps.isEmpty // Firebase 없이(화면 확인용 테스트) 그릴 때
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                      .collection('meal_ratings')
                      .where(
                        'date',
                        isEqualTo:
                            "${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}",
                      )
                      .where('source', isEqualTo: widget.source.name)
                      .where('mealType', isEqualTo: widget.type.stdKey)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // 집계 규칙은 MealRatingSummary 한 곳에만 둔다 —
                    // 화면마다 따로 세면 값이 어긋난다.
                    final summary = snapshot.hasData
                        ? MealRatingSummary.fromDocs(snapshot.data!.docs
                            .map((d) => d.data() as Map<String, dynamic>))
                        : MealRatingSummary.empty;
                    final warm = KnueTokens.warm(
                      Theme.of(context).brightness == Brightness.dark,
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: warm.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: warm.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: summary.hasRatings
                                  ? () => setDialogState(
                                      () => showBreakdown = !showBreakdown,
                                    )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      color: warm,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      summary.hasRatings
                                          ? "${summary.average.toStringAsFixed(1)}점 (${summary.count}명 참여 중)"
                                          : "아직 평가가 없습니다",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: warm,
                                        fontFeatures: KnueTokens.tabularFigures,
                                      ),
                                    ),
                                    if (summary.hasRatings) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        showBreakdown
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        color: warm,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (showBreakdown && summary.hasRatings) ...[
                            const SizedBox(height: 10),
                            _buildRatingBreakdown(summary, warm),
                          ],
                          if (summary.styleVotes > 0) ...[
                            const SizedBox(height: 8),
                            _buildServingStyleBar(summary, warm),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (!canRate)
                  // 마감 안내. 왜 못 남기는지 말해주지 않으면 고장으로 읽힌다.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_clock_rounded,
                        size: 15,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white38
                            : Colors.black38,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${_getRatingTimeMessage()}\n지난 평가 결과는 그대로 보실 수 있어요.",
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  const Text(
                    "식단이 어떠셨나요?\n맛있게 드셨다면 별점을 남겨주세요!",
                    style: TextStyle(fontSize: 14, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildStarRatingBar(currentRating, (val) {
                    setDialogState(() => currentRating = val);
                  }),
                  const SizedBox(height: 10),
                  Text(
                    "$currentRating 점",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: KnueTokens.warm(
                        Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  // 배식 방식 투표 — 식당에 가기 전 가장 궁금해하는 정보다.
                  // 별점과 같은 문서에 담아 한 번의 제출로 끝낸다.
                  const Text(
                    "메인 반찬은 어떻게 나왔나요?",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "직접 드신 분만 골라주세요 (선택)",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white38
                          : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ServingStyle.values.map((style) {
                      final selected = currentStyle == style;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(style.label),
                          selected: selected,
                          // 다시 누르면 선택 해제 — "잘 모르겠다"를 따로 두지
                          // 않고 고르지 않은 상태로 되돌릴 수 있게 한다.
                          onSelected: (_) => setDialogState(
                            () => currentStyle = selected ? null : style,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: canRate
                ? [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        "취소",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _submitRating(currentRating, style: currentStyle);
                      },
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("평가하기"),
                    ),
                  ]
                : [
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("닫기"),
                    ),
                  ],
          );
        },
      ),
    );
  }

  Future<void> _fetchCalories() async {
    if (widget.items.isEmpty) return;
    if (mounted) {
      setState(() {
        _isCalorieLoading = true;
        _caloriesInfo = null;
      });
    }

    try {
      await Future.delayed(const Duration(milliseconds: 500));
      String result = await GeminiService.estimateCalories(widget.items);
      if (mounted) {
        setState(() {
          _caloriesInfo = result;
          _isCalorieLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _caloriesInfo = "측정 불가";
          _isCalorieLoading = false;
        });
      }
    }
  }

  String _getTimeRangeText() {
    if (widget.source == MealSource.b) {
      switch (widget.type) {
        case MealType.breakfast:
          return "미운영";
        case MealType.lunch:
          return "11:00 ~ 14:00";
        case MealType.dinner:
          return "17:00 ~ 18:30";
      }
    }
    return widget.type.timeRange;
  }

  @override
  Widget build(BuildContext context) {
    bool isStudentHallBreakfast =
        (widget.source == MealSource.b && widget.type == MealType.breakfast);
    final bool unavailable =
        widget.items.isEmpty ||
        widget.items.first.contains("없음") ||
        widget.items.first.contains("미운영") ||
        isStudentHallBreakfast;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final aiTextColor = isDark ? Colors.purpleAccent : Colors.deepPurple;
    final aiIconColor = isDark ? Colors.purpleAccent : Colors.purple;
    final boxBorder = isDark
        ? (widget.isToday
              ? Border.all(color: primary.withValues(alpha: 0.5), width: 2)
              : Border.all(color: Colors.transparent))
        : Border.all(
            color: widget.isToday
                ? primary.withValues(alpha: 0.5)
                : Colors.grey.shade300,
            width: widget.isToday ? 2 : 1,
          );

    // 2색 체계: "지금 배식 중"만 보조색(앰버)으로 띄우고 나머지는 그레이스케일.
    // 초록/파랑을 함께 쓰면 카드마다 신호등이 켜져 시선이 분산된다.
    final mutedStatus = KnueTokens.caption(isDark);
    Color statusColor = KnueTokens.warm(isDark);
    String statusText = "운영 중";
    IconData statusIcon = Icons.soup_kitchen;

    if (isStudentHallBreakfast) {
      statusColor = mutedStatus;
      statusText = "운영 안함";
      statusIcon = Icons.block;
    } else {
      switch (widget.status) {
        case ServeStatus.open:
          statusColor = KnueTokens.warm(isDark);
          statusText = "식당 운영 중";
          break;
        case ServeStatus.waiting:
          statusColor = mutedStatus;
          statusText = "식사 준비 중";
          statusIcon = Icons.access_time;
          break;
        case ServeStatus.closed:
          statusColor = mutedStatus;
          statusText = "운영 종료";
          statusIcon = Icons.block;
          break;
        case ServeStatus.notToday:
          statusColor = mutedStatus;
          statusText = "식당 운영시간 아님";
          statusIcon = Icons.calendar_today_rounded;
          break;
      }
    }

    final timeLeft = _getTimeLeft();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E22).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: boxBorder,
        boxShadow: [
          BoxShadow(
            color: widget.isToday
                ? primary.withValues(alpha: isDark ? 0.1 : 0.05)
                : Colors.black.withValues(alpha: isDark ? 0.05 : 0.015),
            blurRadius: widget.isToday ? 32 : 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.01),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: widget.isToday
                  ? primary.withValues(alpha: 0.03)
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: Firebase.apps.isEmpty // Firebase 없이(화면 확인용 테스트) 그릴 때
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                        .collection('meal_ratings')
                        .where(
                          'date',
                          isEqualTo:
                              "${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}",
                        )
                        .where('source', isEqualTo: widget.source.name)
                        .where('mealType', isEqualTo: widget.type.stdKey)
                        .snapshots(),
                    builder: (context, snapshot) {
                      double avg = 0.0;
                      int count = 0;
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        count = snapshot.data!.docs.length;
                        double sum = 0.0;
                        for (var doc in snapshot.data!.docs) {
                          sum +=
                              (doc.data() as Map<String, dynamic>)['rating'] ??
                              0.0;
                        }
                        avg = sum / count;
                      }

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 16,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isStudentHallBreakfast)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _showRatingDialog,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.star_rounded,
                                          size: 16,
                                          color: KnueTokens.warm(isDark),
                                        ),
                                        if (count > 0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            avg.toStringAsFixed(1),
                                            style: TextStyle(
                                              color: KnueTokens.warm(isDark),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              fontFeatures:
                                                  KnueTokens.tabularFigures,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.status == ServeStatus.open &&
                    timeLeft.isNotEmpty &&
                    !isStudentHallBreakfast)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // 마감 임박은 시간 신호이므로 보조색(앰버).
                      color: KnueTokens.warm(isDark).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: KnueTokens.warm(isDark).withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 12,
                          color: KnueTokens.warm(isDark),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLeft,
                          style: TextStyle(
                            color: KnueTokens.warm(isDark),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFeatures: KnueTokens.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: unavailable
                ? const EdgeInsets.fromLTRB(24, 40, 24, 56)
                : const EdgeInsets.fromLTRB(24, 24, 24, 4),
            child: unavailable
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.no_meals_rounded,
                            size: 38,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "운영하지 않거나 메뉴 정보가 없습니다.",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "다른 날짜나 식당 탭을 확인해보세요.",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white30
                                : Colors.grey.shade400,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: isDark ? Colors.grey : Colors.black45,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getTimeRangeText(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey : Colors.black45,
                                fontFeatures: KnueTokens.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...widget.items.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final e = entry.value;
                        final isBold = _boldItemIndex == idx;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_boldItemIndex == idx) {
                                _boldItemIndex = null;
                              } else {
                                _boldItemIndex = idx;
                              }
                            });
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  // 첫 줄(그날의 메인)만 점을 진하게 — 목록이
                                  // 평평하게 늘어서지 않고 읽는 순서가 생긴다.
                                  margin: EdgeInsets.only(top: idx == 0 ? 8 : 7),
                                  width: idx == 0 ? 7 : 6,
                                  height: idx == 0 ? 7 : 6,
                                  decoration: BoxDecoration(
                                    color: isBold || idx == 0
                                        ? primary
                                        : primary.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 150),
                                    style: TextStyle(
                                      fontSize: idx == 0 ? 16.5 : 15.5,
                                      height: 1.5,
                                      letterSpacing: -0.2,
                                      fontWeight: isBold
                                          ? FontWeight.w900
                                          : (idx == 0
                                                ? FontWeight.w700
                                                : FontWeight.w500),
                                      color: isBold
                                          ? primary
                                          : (isDark
                                                ? (idx == 0
                                                      ? Colors.white
                                                      : Colors.white70)
                                                : (idx == 0
                                                      ? Colors.black87
                                                      : Colors.black.withValues(
                                                          alpha: 0.66))),
                                    ),
                                    child: Text(
                                      e,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
          if (!unavailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.02)
                    : primary.withValues(alpha: 0.015),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _isCalorieLoading ? null : _fetchCalories,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: aiTextColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: aiTextColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          if (_isCalorieLoading)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: aiTextColor,
                              ),
                            )
                          else
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: aiIconColor,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _isCalorieLoading
                                ? "분석 중..."
                                : (_caloriesInfo ?? "AI 칼로리 계산"),
                            style: TextStyle(
                              color: aiTextColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => shareMenu(
                      context,
                      widget.date,
                      widget.source,
                      widget.type,
                      widget.items,
                      calories: _caloriesInfo,
                    ),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text("공유"),
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getTimeLeft() {
    if (!widget.isToday) return "";
    String range = _getTimeRangeText();
    if (range == "미운영") return "";
    final now = DateTime.now();
    try {
      final times = range.split("~")[1].trim().split(":");
      final end = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(times[0]),
        int.parse(times[1]),
      );
      if (now.isAfter(end)) return "마감됨";
      final diff = end.difference(now);
      if (diff.inMinutes < 60) return "마감 ${diff.inMinutes}분 전";
      return "마감 ${diff.inHours}시간 전";
    } catch (e) {
      return "";
    }
  }
}

void showAppSwitchDialog(BuildContext context, String currentLabel) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "앱 바로가기",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            AppSwitchOption(
              icon: Icons.restaurant_menu,
              label: "청람밥상",
              isSelected: currentLabel == "청람밥상",
              color: Colors.orange,
              onTap: () {
                Navigator.pop(ctx);
                RootNavigationScreen.switchTab(AppTab.meal);
              },
            ),
            const SizedBox(height: 12),
            AppSwitchOption(
              icon: Icons.directions_bus,
              label: "청람버스",
              color: Colors.blue,
              isSelected: currentLabel == "청람버스",
              onTap: () {
                Navigator.pop(ctx);
                RootNavigationScreen.switchTab(AppTab.bus);
              },
            ),
            const SizedBox(height: 12),
            AppSwitchOption(
              icon: Icons.directions_run,
              label: "캠퍼스런",
              color: Colors.green,
              isSelected: currentLabel == "캠퍼스런",
              onTap: () {
                Navigator.pop(ctx);
                RootNavigationScreen.switchTab(AppTab.run);
              },
            ),
            const SizedBox(height: 12),
            AppSwitchOption(
              icon: Icons.map_rounded,
              label: "캠퍼스맵",
              color: Colors.deepPurple,
              isSelected: currentLabel == "캠퍼스맵",
              onTap: () {
                Navigator.pop(ctx);
                RootNavigationScreen.switchTab(AppTab.map);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class AppSwitchOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const AppSwitchOption({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: activeColor, size: 24),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: activeColor),
          ],
        ),
      ),
    );
  }
}
