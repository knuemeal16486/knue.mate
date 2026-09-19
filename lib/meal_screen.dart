import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';
import 'gemini_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'tab_edit_screen.dart';
import 'notice_alert_settings_screen.dart';
import 'meal_rating_service.dart';
import 'rewarded_ad_service.dart';
import 'root_screen.dart';
import 'ui_utils.dart';
import 'meal_rating.dart';
import 'club_event_admin_screen.dart';
import 'housing_admin_screen.dart';
import 'sponsor_admin_screen.dart';
import 'native_ad_card.dart';

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
  return Container(
    height: 32,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onSwitchTab(0),
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
                color: selectedIndex == 0 ? primaryColor : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onSwitchTab(1),
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
                color: selectedIndex == 1 ? primaryColor : Colors.white.withValues(alpha: 0.85),
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
      });
    }
  }

  void _updateSelectionByTime() {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour < 9) {
      _selected = MealType.breakfast;
    } else if (hour < 14) {
      _selected = MealType.lunch;
    } else {
      _selected = MealType.dinner;
    }
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
    setState(() => _source = s);
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

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              backgroundColor: primaryColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              leading: null, // 햄버거 메뉴 제거
              title: Row(
                children: [
                  const Text(
                    "청람밥상",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showCafeteriaInfo(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.white.withOpacity(0.8),
                        size: 18,
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
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(30),
                    ),
                    gradient: KnuePearl.headerGradient(
                      primaryColor,
                      Theme.of(context).brightness == Brightness.dark,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 60,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                _buildSegmentBtn(MealSource.a.label, MealSource.a),
                                _buildSegmentBtn(MealSource.b.label, MealSource.b),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        _DateSwitcher(
                          date: _date,
                          isToday: isToday,
                          onPrev: _loading ? null : () => _changeDate(-1),
                          onNext: _loading ? null : () => _changeDate(1),
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
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _MealTabs(
                selected: _selected,
                source: _source,
                onSelect: (t) => setState(() => _selected = t),
              ),
              const SizedBox(height: 16),
              if (_loading)
                // 스피너 대신 카드 형태를 미리 그려 로딩→표시 전환에 덜컹임이 없게.
                _MealCardSkeleton(
                  isDark: Theme.of(context).brightness == Brightness.dark,
                )
              else if (_error != null)
                _ErrorCard(message: _error!)
              else
                AnimatedSwitcher(
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
                    onShare: () => shareMenu(
                      context,
                      _date,
                      _source,
                      _selected,
                      _meals[_selected.stdKey],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: KnueNativeAdCard(isCompact: true, placement: 'meal'),
              ),
              const SizedBox(height: 32),
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
              color: isSel ? Colors.black87 : Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _showCafeteriaInfo(BuildContext context) {
    // a = 사도교육원 식당(관리동 1층, 의무입사생 무료), b = 교직원 식당(학생회관 1층 느티헌).
    final isSado = _source == MealSource.a;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "식당 운영 정보",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoRow(
                        Icons.place,
                        "위치",
                        isSado ? "관리동 1층" : "학생회관 1층",
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.attach_money,
                        "가격",
                        isSado ? "의무입사생 무료" : "6,000원 (느티헌)",
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.access_time,
                        "운영",
                        isSado ? "연중무휴" : "주말/공휴일 휴무",
                      ),
                      if (!isSado) ...[
                        const SizedBox(height: 24),
                        const SizedBox(
                          width: double.infinity,
                          child: Text(
                            "선택식 메뉴",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...[
                          {
                            "category": "🍲 한식 & 찌개",
                            "items": [
                              {"name": "느티헌 교원백반", "price": "6,000"},
                              {"name": "매화헌 교원백반", "price": "6,000"},
                              {"name": "촌돼지김치찌개", "price": "6,500"},
                            ],
                          },
                          {
                            "category": "🍜 라면",
                            "items": [
                              {"name": "해장라면+공기밥", "price": "5,000"},
                              {"name": "떡만두라면+공기밥", "price": "5,200"},
                              {"name": "치즈라면+공기밥", "price": "5,200"},
                              {"name": "부대라면+공기밥", "price": "5,500"},
                            ],
                          },
                          {
                            "category": "🍛 돈까스 & 알밥",
                            "items": [
                              {"name": "등심돈까스", "price": "6,000"},
                              {"name": "등심돈까스+알밥", "price": "6,500"},
                              {"name": "치즈돈까스", "price": "6,500"},
                              {"name": "치즈돈까스+알밥", "price": "7,000"},
                              {"name": "고구마치즈돈까스", "price": "6,500"},
                              {"name": "고구마치즈돈까스+알밥", "price": "7,000"},
                              {"name": "치킨까스", "price": "6,000"},
                              {"name": "치킨까스+알밥", "price": "6,500"},
                            ],
                          },
                        ].map((group) {
                          final category = group["category"] as String;
                          final items =
                              group["items"] as List<Map<String, String>>;
                          final bool isDark =
                              Theme.of(context).brightness == Brightness.dark;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.grey[900]
                                        : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[800]!
                                          : Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    children: items.map((menu) {
                                      final isLast = items.last == menu;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          border: isLast
                                              ? null
                                              : Border(
                                                  bottom: BorderSide(
                                                    color: isDark
                                                        ? Colors.grey[800]!
                                                        : Colors.grey[200]!,
                                                  ),
                                                ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                menu["name"]!,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              "${menu["price"]}원",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.grey[300]
                                                    : Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "닫기",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Helper Widgets
// =============================================================================

class _DateSwitcher extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Color primaryColor;

  const _DateSwitcher({
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
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
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "오늘의 식단",
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                "${wd[date.weekday]}요일",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
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
        centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
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
                    color: Colors.black.withOpacity(0.05),
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
            const SizedBox(height: 24),
            _MealTabs(
              selected: _selectedType,
              source: _source,
              onSelect: (t) => setState(() => _selectedType = t),
            ),
            const SizedBox(height: 16),
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

// =============================================================================
// 4. 설정 페이지
// =============================================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _localTransparency = 0.0;
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    _localTransparency = widgetTransparency.value;
  }

  // 더보기 화면이 없어지면서 옮겨온 숨김 진입로 — 버전 텍스트 7번 탭하면 관리 화면 선택 시트.
  void _onVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      _showAdminMenu();
    }
  }

  void _showAdminMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "관리자 메뉴",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text("공연·행사 관리"),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ClubEventAdminScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text("제휴·광고 관리"),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SponsorAdminScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.house_outlined),
              title: const Text("자취방 정보 관리"),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HousingAdminScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _forceUpdateWidget(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("위젯 갱신 중..."),
        duration: Duration(milliseconds: 800),
      ),
    );
    try {
      await fetchMealApi(DateTime.now(), widgetSource.value);
      if (mounted) showToast(context, "위젯 업데이트 완료!");
    } catch (e) {
      await forceUpdateWidgetWithCurrentSettings();
      if (mounted) showToast(context, "위젯 설정 업데이트 완료!");
    }
  }

  Widget _buildAppInfoItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const FeedbackDialog());
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = themeColor.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBorder = isDark ? null : Border.all(color: Colors.grey.shade300);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: currentColor,
            centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                "설정",
                style: TextStyle(
                  fontWeight: (!kIsWeb && Platform.isIOS)
                      ? FontWeight.w800
                      : FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSectionTitle("맞춤 설정"),
                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.swap_calls_rounded,
                      title: "하단 탭 순서 및 시작화면",
                      subtitle: "내비게이션 탭의 순서를 변경하거나 시작 화면 설정",
                      iconColor: Colors.deepPurple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => const TabEditScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.notifications_active_rounded,
                      title: "공지 알림",
                      subtitle: "알림 켜고 끄기, 알림 받을 키워드 관리",
                      iconColor: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => const NoticeAlertSettingsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionTitle("앱 테마"),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: boxBorder,
                      ),
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeNotifier,
                        builder: (context, mode, _) => Row(
                          children: [
                            _ThemeOption(
                              label: "라이트",
                              icon: Icons.light_mode,
                              selected: mode == ThemeMode.light,
                              onTap: () {
                                themeModeNotifier.value = ThemeMode.light;
                                PreferencesService.saveThemeMode(
                                  ThemeMode.light,
                                );
                              },
                            ),
                            _ThemeOption(
                              label: "다크",
                              icon: Icons.dark_mode,
                              selected: mode == ThemeMode.dark,
                              onTap: () {
                                themeModeNotifier.value = ThemeMode.dark;
                                PreferencesService.saveThemeMode(
                                  ThemeMode.dark,
                                );
                              },
                            ),
                            _ThemeOption(
                              label: "시스템",
                              icon: Icons.settings_brightness,
                              selected: mode == ThemeMode.system,
                              onTap: () {
                                themeModeNotifier.value = ThemeMode.system;
                                PreferencesService.saveThemeMode(
                                  ThemeMode.system,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle("테마 색상"),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: boxBorder,
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: rainbowModeNotifier,
                        builder: (context, rainbowOn, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 무지개 모드가 켜져 있으면 색을 직접 고를 수 없다는
                            // 걸 흐리게 해서 보여준다(탭은 아래에서 막는다).
                            Opacity(
                              opacity: rainbowOn ? 0.4 : 1.0,
                              child: IgnorePointer(
                                ignoring: rainbowOn,
                                // Wrap은 한 줄에 몇 개가 들어가는지가 스와치
                                // 폭(고정 40)으로만 정해져서, 5개를 채우고 남는
                                // 자투리 폭이 전부 오른쪽 끝 빈 공간으로 남았다.
                                // GridView는 5열로 폭을 균등하게 나눠 쓰므로
                                // 그 여백이 스와치 사이 간격으로 흡수된다.
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                  ),
                                  itemCount: kColorPalette.length,
                                  itemBuilder: (context, i) {
                                    final c = kColorPalette[i];
                                    return Center(
                                      child: _ColorPickerItem(
                                        color: c,
                                        isSelected: !rainbowOn &&
                                            c.value == currentColor.value,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            _RainbowModeTile(isOn: rainbowOn),
                            const SizedBox(height: 4),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            // 무지개 모드가 켜져 있으면 색을 매일 자동으로
                            // 덮어쓰므로, 뽑아봐야 소용이 없어 같이 잠근다.
                            _RandomColorTile(disabled: rainbowOn),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "위젯 미리보기",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: widgetTheme,
                      builder: (context, mode, _) {
                        final bool wIsDark =
                            mode == ThemeMode.dark ||
                            (mode == ThemeMode.system &&
                                Theme.of(context).brightness ==
                                    Brightness.dark);
                        return ValueListenableBuilder<MealSource>(
                          valueListenable: widgetSource,
                          builder: (context, src, _) {
                            final now = DateTime.now();
                            final hour = now.hour;
                            String mealType = "";
                            if (src == MealSource.a) {
                              mealType = hour < 9
                                  ? "아침"
                                  : hour < 13
                                  ? "점심"
                                  : "저녁";
                            } else {
                              mealType = hour < 14 ? "점심" : "저녁";
                            }
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    (wIsDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white)
                                        .withOpacity(1.0 - _localTransparency),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.restaurant_menu,
                                        size: 16,
                                        color: wIsDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        src.label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: wIsDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "오늘 $mealType",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: wIsDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "· 쌀밥\n· 돈육김치찌개\n· 계란말이\n· 깍두기",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: wIsDark
                                          ? Colors.white
                                          : Colors.black87,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "투명도: ${(_localTransparency * 100).toInt()}%",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: wIsDark
                                          ? Colors.white54
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle("위젯 설정"),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: boxBorder,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "표시할 식당",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<MealSource>(
                            valueListenable: widgetSource,
                            builder: (context, src, _) => Row(
                              children: [
                                _WidgetOption(
                                  label: MealSource.a.shortLabel,
                                  isSelected: src == MealSource.a,
                                  onTap: () async {
                                    await saveWidgetSettingsAndUpdate(
                                      widgetTransparency.value,
                                      widgetTheme.value,
                                      MealSource.a,
                                      context,
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                _WidgetOption(
                                  label: MealSource.b.shortLabel,
                                  isSelected: src == MealSource.b,
                                  onTap: () async {
                                    await saveWidgetSettingsAndUpdate(
                                      widgetTransparency.value,
                                      widgetTheme.value,
                                      MealSource.b,
                                      context,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "위젯 배경 테마",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<ThemeMode>(
                            valueListenable: widgetTheme,
                            builder: (context, mode, _) => Row(
                              children: [
                                _ThemeOption(
                                  label: "라이트",
                                  icon: Icons.light_mode,
                                  selected: mode == ThemeMode.light,
                                  onTap: () {
                                    widgetTheme.value = ThemeMode.light;
                                    PreferencesService.saveWidgetSettings(
                                      widgetTransparency.value,
                                      ThemeMode.light,
                                      widgetSource.value,
                                    );
                                    _forceUpdateWidget(context);
                                  },
                                ),
                                _ThemeOption(
                                  label: "다크",
                                  icon: Icons.dark_mode,
                                  selected: mode == ThemeMode.dark,
                                  onTap: () {
                                    widgetTheme.value = ThemeMode.dark;
                                    PreferencesService.saveWidgetSettings(
                                      widgetTransparency.value,
                                      ThemeMode.dark,
                                      widgetSource.value,
                                    );
                                    _forceUpdateWidget(context);
                                  },
                                ),
                                _ThemeOption(
                                  label: "시스템",
                                  icon: Icons.settings_brightness,
                                  selected: mode == ThemeMode.system,
                                  onTap: () {
                                    widgetTheme.value = ThemeMode.system;
                                    PreferencesService.saveWidgetSettings(
                                      widgetTransparency.value,
                                      ThemeMode.system,
                                      widgetSource.value,
                                    );
                                    _forceUpdateWidget(context);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "배경 투명도",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _localTransparency,
                                  min: 0.0,
                                  max: 0.8,
                                  divisions: 8,
                                  activeColor: currentColor,
                                  onChanged: (v) {
                                    setState(() => _localTransparency = v);
                                    widgetTransparency.value = v;
                                  },
                                  onChangeEnd: (v) async {
                                    await saveWidgetSettingsAndUpdate(
                                      v,
                                      widgetTheme.value,
                                      widgetSource.value,
                                      context,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                width: 50,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: currentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "${(_localTransparency * 100).toInt()}%",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: currentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "투명도가 높을수록 위젯 배경이 투명해집니다.",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _forceUpdateWidget(context),
                              icon: const Icon(Icons.refresh),
                              label: const Text("위젯 데이터 즉시 업데이트"),
                              style: FilledButton.styleFrom(
                                backgroundColor: currentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: testBasicWidgetFunction,
                              icon: const Icon(Icons.verified),
                              label: const Text("기본 위젯 테스트"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: currentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle("앱 정보"),

                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.face,
                      title: "개발자 정보",
                      subtitle: "만든 사람 소개",
                      iconColor: currentColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DeveloperInfoPage(),
                        ),
                      ),
                    ),

                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.feedback_outlined,
                      title: "사용자 의견 보내기",
                      subtitle: "버그 제보 및 기능 제안",
                      iconColor: Colors.amber[700]!,
                      onTap: () => _showFeedbackDialog(context),
                    ),

                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.description_outlined,
                      title: "오픈소스 라이선스",
                      subtitle: "사용된 라이브러리 정보",
                      iconColor: Colors.blueGrey,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: "KNUE All-in-One",
                        applicationVersion: "5.8.0",
                      ),
                    ),

                    _buildAppInfoItem(
                      context: context,
                      icon: Icons.refresh_rounded,
                      title: "설정 초기화",
                      subtitle: "앱 설정을 기본값으로 되돌리기",
                      iconColor: Colors.redAccent,
                      onTap: () async {
                        await PreferencesService.clearAll();
                        setState(() => _localTransparency = 0.0);
                        await forceUpdateWidgetWithCurrentSettings();
                        showToast(context, "초기화되었습니다.");
                      },
                    ),

                    const SizedBox(height: 12),
                    _buildSectionTitle("스폰서 & 제휴"),
                    const KnueNativeAdCard(isCompact: true, placement: 'settings'),
                    const SizedBox(height: 18),

                    Center(
                      child: GestureDetector(
                        onTap: _onVersionTap,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          "버전 5.8.0 (Final)",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// 사용자 의견 보내기 - 팝업 Dialog 위젯
// -----------------------------------------------------------------------------
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final TextEditingController _feedbackController = TextEditingController();
  bool _isAgreed = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  Future<void> _sendFeedback() async {
    if (_feedbackController.text.isEmpty || !_isAgreed) return;

    const String developerEmail = 'knuemeal16486@gmail.com';
    const String subject = '[KNUE Mate] 사용자 의견 및 제보';
    final String body = _feedbackController.text;

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: developerEmail,
      query: _encodeQueryParameters(<String, String>{
        'subject': subject,
        'body': '내용:\n$body\n\n----------------------------',
      }),
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) showToast(context, "기본 이메일 앱을 실행할 수 없습니다.");
      }
    } catch (e) {
      if (mounted) showToast(context, "오류가 발생했습니다: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isButtonEnabled =
        _feedbackController.text.isNotEmpty && _isAgreed;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "사용자 의견 보내기",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "KNUE Mate를 더 나은 앱으로 만들기 위해\n여러분의 소중한 의견을 들려주세요.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade300 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                child: TextField(
                  controller: _feedbackController,
                  maxLines: 6,
                  onChanged: (text) => setState(() {}),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "불편했던 점, 개선할 점, 칭찬하고 싶은 점 등을 자유롭게 적어주세요.",
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _isAgreed = !_isAgreed),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _isAgreed,
                        activeColor: primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (value) =>
                            setState(() => _isAgreed = value ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: "개인정보 수집 및 이용에 동의합니다. ",
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.black87,
                          ),
                          children: [
                            TextSpan(
                              text: "(필수)",
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isButtonEnabled ? _sendFeedback : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    disabledBackgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey.shade500,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "이메일로 보내기",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DeveloperInfoPage (아이콘 색상 및 디자인 개선, 정렬 수정)
// -----------------------------------------------------------------------------
class DeveloperInfoPage extends StatelessWidget {
  const DeveloperInfoPage({super.key});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
        title: Text(
          "개발자 정보",
          style: TextStyle(
            fontWeight: (!kIsWeb && Platform.isIOS) ? FontWeight.w800 : FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withOpacity(0.1),
                border: Border.all(color: primary, width: 3),
              ),
              child: Icon(Icons.person, size: 60, color: primary),
            ),
            const SizedBox(height: 20),
            const Text(
              "Hwang",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "KNUE Physics & Primary Education 23",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      context: context,
                      icon: Icons.school,
                      label: "소속",
                      content: "한국교원대학교 물리교육과",
                      color: Colors.blue,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      context: context,
                      icon: Icons.code,
                      label: "관심 분야",
                      content: "Physical Computing, Embedded System , AI",
                      color: Colors.orange,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      context: context,
                      icon: Icons.email,
                      label: "이메일",
                      content: "knuemeal16486@gmail.com",
                      color: Colors.green,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      context: context,
                      icon: Icons.money,
                      label: "후원",
                      content: "고생한 개발자를 위해 커피 사주기\n신한 110-334-965296",
                      color: Colors.pink,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: _buildInfoRow(
                  context: context,
                  icon: Icons.handshake_rounded,
                  label: "Special Help",
                  content: "Hyunsu, Oh\nSNU Nuclear Engineering",
                  color: Colors.deepPurple,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "© 2026 KNUE Mate",
              style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String content,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? Colors.grey.withOpacity(0.2) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [Icon(icon), Text(label)]),
      ),
    ),
  );
}

class _WidgetOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _WidgetOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey.withOpacity(0.5),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey,
          ),
        ),
      ),
    ),
  );
}

/// 무지개 모드 토글 한 줄. 오늘 배정된 색을 미리 보여줘서, 켜면 무슨 일이
/// 벌어지는지 켜기 전에 알 수 있게 한다.
class _RainbowModeTile extends StatelessWidget {
  final bool isOn;
  const _RainbowModeTile({required this.isOn});

  @override
  Widget build(BuildContext context) {
    final today = colorOfDay(DateTime.now());
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 무지개 팔레트 전체를 원 하나에 담아 무슨 모드인지 보여준다.
            gradient: SweepGradient(colors: [
              ...kRainbowPalette,
              kRainbowPalette.first,
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "무지개 모드",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    isOn ? "오늘의 색 · " : "매일 색이 바뀌어요",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black54,
                    ),
                  ),
                  if (isOn)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: KnuePearl.swatchGradient(today),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: isOn,
          onChanged: (v) => _handleToggle(context, v),
        ),
      ],
    );
  }

  /// 끄는 건 바로 처리하지만, 켜는 건 보상형 광고를 끝까지 봐야 켜진다.
  Future<void> _handleToggle(BuildContext context, bool wantsOn) async {
    if (!wantsOn) {
      await PreferencesService.setRainbowMode(false);
      return;
    }
    showToast(context, "광고를 보면 무지개 모드가 켜져요 🌈");
    await RewardedAdService.show(
      onEarned: () => PreferencesService.setRainbowMode(true),
      onUnavailable: () {
        if (context.mounted) {
          showToast(context, "지금은 광고를 불러올 수 없어요. 잠시 후 다시 시도해주세요.");
        }
      },
    );
  }
}

/// 광고를 끝까지 보면 테마 색을 무작위로 하나 뽑아 적용한다.
/// 팔레트를 훑어보기 귀찮은 사람을 위한 "아무거나 골라줘" 버튼.
class _RandomColorTile extends StatelessWidget {
  /// 무지개 모드가 켜져 있으면 색이 매일 자동으로 덮어써지므로 잠근다.
  final bool disabled;
  const _RandomColorTile({required this.disabled});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: IgnorePointer(
        ignoring: disabled,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themeColor.value.withValues(alpha: isDark ? 0.22 : 0.12),
              ),
              child: Icon(
                Icons.casino_rounded,
                size: 19,
                color: themeColor.value,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "랜덤 테마 색",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    disabled ? "무지개 모드를 끄면 쓸 수 있어요" : "광고 보고 색 하나 뽑기",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _roll(context),
              child: const Text("뽑기"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _roll(BuildContext context) async {
    showToast(context, "광고를 보면 색이 바뀌어요 🎲");
    await RewardedAdService.show(
      onEarned: () async {
        // 지금 색은 후보에서 빠지므로 광고를 보고도 그대로인 일은 없다.
        final picked = pickRandomThemeColor(themeColor.value);
        themeColor.value = picked;
        await PreferencesService.saveThemeColor(picked);
        if (context.mounted) showToast(context, "새 테마 색이 적용됐어요 🎨");
      },
      onUnavailable: () {
        if (context.mounted) {
          showToast(context, "지금은 광고를 불러올 수 없어요. 잠시 후 다시 시도해주세요.");
        }
      },
    );
  }
}

class _ColorPickerItem extends StatelessWidget {
  final Color color;
  final bool isSelected;
  const _ColorPickerItem({required this.color, required this.isSelected});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      themeColor.value = color;
      PreferencesService.saveThemeColor(color);
    },
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // 펄 그라데이션 + 위에 겹치는 반사광. 저장되는 값은 여전히 단색
        // [color] 하나이고, 여기서는 보여주기만 한다.
        gradient: KnuePearl.swatchGradient(color),
        shape: BoxShape.circle,
        border: isSelected ? Border.all(width: 3, color: Colors.white) : null,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: isSelected ? 10 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: KnuePearl.sheen(),
        ),
      ),
    ),
  );
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
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
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
  final VoidCallback? onShare;

  const _MealDetailCard({
    super.key,
    required this.status,
    required this.type,
    required this.source,
    required this.items,
    required this.isToday,
    required this.date,
    this.onShare,
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

  /// 별점 평가 가능 시간인지 확인
  /// 운영 시작 시간부터 운영 종료 후 30분까지 평가 가능
  bool _isRatingAllowed() {
    if (!widget.isToday) return false;

    final now = DateTime.now();

    // 각 식당과MealType별 운영 시간 설정
    int startHour, startMinute, endHour, endMinute;

    if (widget.source == MealSource.a) {
      // 사도교육원 식당
      switch (widget.type) {
        case MealType.breakfast:
          startHour = 7;
          startMinute = 30;
          endHour = 9;
          endMinute = 0;
          break;
        case MealType.lunch:
          startHour = 11;
          startMinute = 30;
          endHour = 13;
          endMinute = 30;
          break;
        case MealType.dinner:
          startHour = 17;
          startMinute = 30;
          endHour = 19;
          endMinute = 0;
          break;
      }
    } else {
      // 교직원 식당 (조식은 운영 안함)
      if (widget.type == MealType.breakfast) return false;

      switch (widget.type) {
        case MealType.lunch:
          startHour = 11;
          startMinute = 0;
          endHour = 14;
          endMinute = 0;
          break;
        case MealType.dinner:
          startHour = 17;
          startMinute = 0;
          endHour = 18;
          endMinute = 30;
          break;
        default:
          return false;
      }
    }

    final startTime = DateTime(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    );
    // 종료 후 1시간까지 허용 (사용자 요청)
    final endTime = DateTime(
      now.year,
      now.month,
      now.day,
      endHour,
      endMinute,
    ).add(const Duration(hours: 1));

    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// 별점 평가 가능 시간에 대한 사용자 안내 메시지
  String _getRatingTimeMessage() {
    if (!widget.isToday) return "오늘만 평가할 수 있습니다";

    if (widget.source == MealSource.b && widget.type == MealType.breakfast) {
      return "${MealSource.b.shortLabel} 식당 아침은 운영하지 않습니다";
    }

    return "운영 시간에 평가해주세요";
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
    // 평가 가능 시간인지 확인
    if (!_isRatingAllowed()) {
      showToast(context, _getRatingTimeMessage());
      return;
    }

    double currentRating = 4.0;
    ServingStyle? currentStyle;
    bool showBreakdown = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              "식단은 어떠셨나요?",
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
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
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
                        // 다시 누르면 선택 해제 — "잘 모르겠다"를 따로 두지 않고
                        // 고르지 않은 상태로 되돌릴 수 있게 한다.
                        onSelected: (_) => setDialogState(
                          () => currentStyle = selected ? null : style,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("취소", style: TextStyle(color: Colors.grey)),
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
              ? Border.all(color: primary.withOpacity(0.5), width: 2)
              : Border.all(color: Colors.transparent))
        : Border.all(
            color: widget.isToday
                ? primary.withOpacity(0.5)
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
            ? const Color(0xFF1E1E22).withOpacity(0.85)
            : Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        border: boxBorder,
        boxShadow: [
          BoxShadow(
            color: widget.isToday
                ? primary.withOpacity(isDark ? 0.1 : 0.05)
                : Colors.black.withOpacity(isDark ? 0.05 : 0.015),
            blurRadius: widget.isToday ? 32 : 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.1 : 0.01),
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
                  ? primary.withOpacity(0.03)
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
                    stream: FirebaseFirestore.instance
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
                                color: statusColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: statusColor.withOpacity(0.1),
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
                                      color: Colors.amber.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.amber.withOpacity(0.2),
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
                                        : primary.withOpacity(0.4),
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
                    ? Colors.white.withOpacity(0.02)
                    : primary.withOpacity(0.015),
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
                        color: aiTextColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: aiTextColor.withOpacity(0.3)),
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
          color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: activeColor.withOpacity(0.1),
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
