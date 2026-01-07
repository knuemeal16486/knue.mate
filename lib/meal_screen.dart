import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'bus_screen.dart';
import 'campus_run_screen.dart';
import 'gemini_service.dart';

// =============================================================================
// 1. 메인 스크린 (탭 관리)
// =============================================================================
class MealMainScreen extends StatefulWidget {
  const MealMainScreen({super.key});
  @override
  State<MealMainScreen> createState() => _MealMainScreenState();
}

class _MealMainScreenState extends State<MealMainScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    NotificationService().init();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: const NeverScrollableScrollPhysics(), // 탭으로만 이동
            children: const [
              TodayMealPage(),
              MonthlyMealPage(),
              SettingsPage(),
            ],
          ),
          bottomNavigationBar: _BottomNavBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
          ),
        );
      },
    );
  }
}

// =============================================================================
// 2. 오늘 식단 페이지
// =============================================================================
class TodayMealPage extends StatefulWidget {
  const TodayMealPage({super.key});
  @override
  State<TodayMealPage> createState() => _TodayMealPageState();
}

class _TodayMealPageState extends State<TodayMealPage> {
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

  Future<void> _handleAlarmToggle() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      showToast(context, "모바일에서만 가능합니다.");
      return;
    }
    final newState = !_alarmOn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_enabled', newState);
    setState(() => _alarmOn = newState);

    if (newState) {
      await NotificationService().requestPermissions();
      final now = DateTime.now();
      await NotificationService().scheduleAlarm(
        id: 1,
        title: "점심 시간! 🍚",
        body: "맛있는 점심 드시고 힘내세요!",
        scheduledTime: DateTime(now.year, now.month, now.day, 11, 30),
      );
      await NotificationService().scheduleAlarm(
        id: 2,
        title: "저녁 시간! 🍖",
        body: "오늘 하루도 고생하셨습니다.",
        scheduledTime: DateTime(now.year, now.month, now.day, 17, 30),
      );
      showToast(context, "매일 11:30, 17:30 알림 설정됨");
    } else {
      await NotificationService().cancelAll();
      showToast(context, "알림 해제됨");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    return _CommonMealLayout(
      header: _Header(
        alarmOn: _alarmOn,
        onToggleAlarm: _handleAlarmToggle,
        date: _date,
        isToday: isToday,
        onPrev: _loading ? null : () => _changeDate(-1),
        onNext: _loading ? null : () => _changeDate(1),
        source: _source,
        onSourceChanged: _loading
            ? null
            : (s) async {
                setState(() => _source = s);
                PreferencesService.saveMealSource(s);
                await fetchMeals();
              },
      ),
      content: Column(
        children: [
          const SizedBox(height: 16),
          _MealTabs(
            selected: _selected,
            onSelect: (t) => setState(() => _selected = t),
          ),
          const SizedBox(height: 16),
          if (_loading)
            SizedBox(
              height: 300,
              child: Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            )
          else if (_error != null)
            _ErrorCard(message: _error!)
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _MealDetailCard(
                key: ValueKey("$_date-$_selected-$_source"),
                status: statusFor(_selected, DateTime.now(), _date),
                type: _selected,
                items: _meals[_selected.stdKey] ?? [],
                isToday: isToday,
                onShare: () => shareMenu(
                  context,
                  _date,
                  _source,
                  _selected,
                  _meals[_selected.stdKey],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// 3. 월간 식단 페이지 (식당 선택 버튼 + 요일 표시)
// =============================================================================
class MonthlyMealPage extends StatefulWidget {
  const MonthlyMealPage({super.key});
  @override
  State<MonthlyMealPage> createState() => _MonthlyMealPageState();
}

class _MonthlyMealPageState extends State<MonthlyMealPage> {
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
            "breakfast": asStringList(meals["조식"] ?? meals["아침"]),
            "lunch": asStringList(meals["중식"] ?? meals["점심"]),
            "dinner": asStringList(meals["석식"] ?? meals["저녁"]),
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
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, primaryColor, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              "월간 식단",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
              ),
            ),

            // [복구됨] 식당 전환 버튼
            actions: [
              GestureDetector(
                onTap: () {
                  final nextSource = _source == MealSource.a
                      ? MealSource.b
                      : MealSource.a;
                  setState(() => _source = nextSource);
                  _fetchForSelectedDate();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _source == MealSource.a ? "기숙사 식당" : "학생회관 식당",
                        style: const TextStyle(
                          fontSize: 14,
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
                      // [유지됨] 요일 표시
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
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLegendItem(
                            context,
                            isToday: true,
                            isSelected: false,
                            label: "오늘",
                            color: primaryColor,
                          ),
                          const SizedBox(width: 20),
                          _buildLegendItem(
                            context,
                            isToday: false,
                            isSelected: true,
                            label: "선택됨",
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _MealTabs(
                  selected: _selectedType,
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
                    ),
                    type: _selectedType,
                    items: _meals[_selectedType.stdKey] ?? [],
                    isToday: DateUtils.isSameDay(_selectedDate, DateTime.now()),
                    onShare: () => shareMenu(
                      context,
                      _selectedDate,
                      _source,
                      _selectedType,
                      _meals[_selectedType.stdKey],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
// 4. 설정 페이지 (기능 완벽 복구 - 테마/색상/위젯/라이선스 포함)
// =============================================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _localTransparency = 0.0;

  @override
  void initState() {
    super.initState();
    _localTransparency = widgetTransparency.value;
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
      await HomeWidget.updateWidget(name: 'MealWidgetProvider');
      if (mounted) showToast(context, "위젯 업데이트 완료!");
    } catch (e) {
      showToast(context, "업데이트 실패");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBorder = isDark ? null : Border.all(color: Colors.grey.shade300);

    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (ctx, currentColor, child) {
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: currentColor,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    "설정",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
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
                        // [1] 앱 테마
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

                        // [2] 테마 색상 (복구됨)
                        _buildSectionTitle("테마 색상"),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: boxBorder,
                          ),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: kColorPalette
                                .map(
                                  (c) => _ColorPickerItem(
                                    color: c,
                                    isSelected: c.value == currentColor.value,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // [3] 위젯 설정 (복구됨)
                        const Text(
                          "미리보기 (투명도/테마 확인)",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // [위젯 미리보기 컨테이너]
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: widgetTheme,
                          builder: (context, mode, _) {
                            // 미리보기 위젯의 다크모드 여부 결정
                            final bool wIsDark =
                                mode == ThemeMode.dark ||
                                (mode == ThemeMode.system &&
                                    Theme.of(context).brightness ==
                                        Brightness.dark);

                            return ValueListenableBuilder<MealSource>(
                              valueListenable: widgetSource,
                              builder: (context, src, _) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    // [핵심] 로컬 투명도 변수(_localTransparency)를 사용하여 슬라이더 움직임에 즉시 반응
                                    color:
                                        (wIsDark
                                                ? const Color(0xFF1E1E1E)
                                                : Colors.white)
                                            .withOpacity(
                                              (1.0 - _localTransparency).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                            ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            src == MealSource.a
                                                ? "기숙사 식당"
                                                : "학생회관",
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
                                            "오늘 점심",
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
                                        "· 쌀밥\n· 돈육김치찌개\n· 계란말이\n· 깍두기", // 예시 메뉴
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: wIsDark
                                              ? Colors.white
                                              : Colors.black87,
                                          height: 1.5,
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
                              // 미리보기 UI 생략 없이 간단히 표현 (공간 절약상 텍스트로 대체하지만 기능은 유지)
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
                                      label: "기숙사",
                                      isSelected: src == MealSource.a,
                                      onTap: () {
                                        widgetSource.value = MealSource.a;
                                        PreferencesService.saveWidgetSettings(
                                          widgetTransparency.value,
                                          widgetTheme.value,
                                          MealSource.a,
                                        );
                                        _forceUpdateWidget(context);
                                      },
                                    ),
                                    const SizedBox(width: 10),
                                    _WidgetOption(
                                      label: "학생회관",
                                      isSelected: src == MealSource.b,
                                      onTap: () {
                                        widgetSource.value = MealSource.b;
                                        PreferencesService.saveWidgetSettings(
                                          widgetTransparency.value,
                                          widgetTheme.value,
                                          MealSource.b,
                                        );
                                        _forceUpdateWidget(context);
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
                              Slider(
                                value: _localTransparency,
                                min: 0.0,
                                max: 0.8,
                                activeColor: currentColor,
                                onChanged: (v) =>
                                    setState(() => _localTransparency = v),
                                onChangeEnd: (v) {
                                  widgetTransparency.value = v;
                                  PreferencesService.saveWidgetSettings(
                                    v,
                                    widgetTheme.value,
                                    widgetSource.value,
                                  );
                                  _forceUpdateWidget(context);
                                },
                              ),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  onPressed: () => _forceUpdateWidget(context),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("위젯 데이터 즉시 업데이트"),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // [4] 앱 정보 (오픈소스 라이선스 포함 복구)
                        _buildSectionTitle("앱 정보"),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: boxBorder,
                          ),
                          child: Column(
                            children: [
                              _buildSettingTile(
                                ctx,
                                icon: Icons.face,
                                title: "개발자 정보",
                                subtitle: "만든 사람 소개",
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const DeveloperInfoPage(),
                                  ),
                                ),
                              ),
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              _buildSettingTile(
                                ctx,
                                icon: Icons.description_outlined,
                                title: "오픈소스 라이선스",
                                subtitle: "사용된 라이브러리 정보",
                                onTap: () => showLicensePage(
                                  context: context,
                                  applicationName: "KNUE All-in-One",
                                  applicationVersion: "5.8.0",
                                ),
                              ),
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              _buildSettingTile(
                                ctx,
                                icon: Icons.info_outline,
                                title: "버전 정보",
                                subtitle: "5.8.0 (Final)",
                                onTap: () {},
                              ),
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              _buildSettingTile(
                                ctx,
                                icon: Icons.refresh_rounded,
                                title: "설정 초기화",
                                iconColor: Colors.redAccent,
                                titleColor: Colors.redAccent,
                                onTap: () async {
                                  await PreferencesService.clearAll();
                                  setState(() => _localTransparency = 0.0);
                                  showToast(ctx, "초기화되었습니다.");
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
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

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              (iconColor ??
                      (Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Theme.of(context).primaryColor.withOpacity(0.1)))
                  .withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color:
              iconColor ??
              (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Theme.of(context).primaryColor),
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color:
              titleColor ??
              (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}

// -----------------------------------------------------------------------------
// UI 컴포넌트들
// -----------------------------------------------------------------------------

// [헤더 클래스]
class _Header extends StatelessWidget {
  final bool alarmOn;
  final VoidCallback onToggleAlarm;
  final DateTime date;
  final bool isToday;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final MealSource source;
  final ValueChanged<MealSource>? onSourceChanged;
  const _Header({
    super.key,
    required this.alarmOn,
    required this.onToggleAlarm,
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.source,
    required this.onSourceChanged,
  });

  void _showCafeteriaInfo(BuildContext context) {
    final isDorm = source == MealSource.a;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
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
              _buildInfoRow(Icons.place, "위치", isDorm ? "관리동 1층" : "학생회관 1층"),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.attach_money,
                "가격",
                isDorm ? "의무입사생 무료" : "5,000원 (일반)",
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.access_time,
                "운영",
                isDorm ? "연중무휴" : "주말/공휴일 휴무",
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

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).primaryColor;
    const wd = ["", "월", "화", "수", "목", "금", "토", "일"];

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 10,
        20,
        24,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _showAppSwitch(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.menu, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      "KNUE 청람밥상",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
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
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleAlarm,
                icon: Icon(
                  alarmOn
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildSegmentBtn("기숙사 식당", MealSource.a),
                _buildSegmentBtn("학생회관 식당", MealSource.b),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Column(
                children: [
                  if (isToday)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
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
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
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
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAppSwitch(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "앱 바로가기",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _AppSwitchOption(
                icon: Icons.restaurant_menu,
                label: "청람밥상",
                isSelected: true,
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 12),
              _AppSwitchOption(
                icon: Icons.directions_bus,
                label: "청람버스",
                isSelected: false,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const BusAppScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _AppSwitchOption(
                icon: Icons.directions_run,
                label: "캠퍼스런",
                isSelected: false,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const CampusRunScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(String title, MealSource val) {
    final isSel = source == val;
    return Expanded(
      child: GestureDetector(
        onTap: onSourceChanged == null ? null : () => onSourceChanged!(val),
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
}

class _MealDetailCard extends StatefulWidget {
  final ServeStatus status;
  final MealType type;
  final List<String> items;
  final bool isToday;
  final VoidCallback onShare;
  const _MealDetailCard({
    super.key,
    required this.status,
    required this.type,
    required this.items,
    required this.isToday,
    required this.onShare,
  });
  @override
  State<_MealDetailCard> createState() => _MealDetailCardState();
}

class _MealDetailCardState extends State<_MealDetailCard> {
  String? _caloriesInfo;
  bool _isCalorieLoading = false;
  Future<void> _fetchCalories() async {
    if (widget.items.isEmpty) return;
    if (mounted) setState(() => _isCalorieLoading = true);
    try {
      String result = await GeminiService.estimateCalories(widget.items);
      if (mounted)
        setState(() {
          _caloriesInfo = result;
          _isCalorieLoading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _caloriesInfo = "측정 실패";
          _isCalorieLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
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
    Color statusColor = const Color(0xFF2E7D32);
    String statusText = "운영 중";
    IconData statusIcon = Icons.soup_kitchen;
    switch (widget.status) {
      case ServeStatus.open:
        statusColor = const Color(0xFF2E7D32);
        statusText = "식당 운영 중";
        break;
      case ServeStatus.waiting:
        statusColor = const Color(0xFF1976D2);
        statusText = "식사 준비 중";
        statusIcon = Icons.access_time;
        break;
      case ServeStatus.closed:
        statusColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
        statusText = "운영 종료";
        statusIcon = Icons.block;
        break;
      case ServeStatus.notToday:
        statusColor = isDark ? Colors.grey.shade600 : Colors.grey.shade500;
        statusText = "식당 운영시간 아님";
        statusIcon = Icons.calendar_today_rounded;
        break;
    }
    final timeLeft = _getTimeLeft();
    final bool unavailable =
        widget.items.isEmpty ||
        widget.items.first.contains("없음") ||
        widget.items.first.contains("미운영");

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: boxBorder,
        boxShadow: [
          BoxShadow(
            color: widget.isToday
                ? primary.withOpacity(0.15)
                : Colors.black.withOpacity(0.05),
            blurRadius: widget.isToday ? 20 : 10,
            offset: const Offset(0, 4),
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
                  ? primary.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.status == ServeStatus.open &&
                    timeLeft.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeLeft,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.isToday)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "TODAY",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                Text(
                  widget.type.timeRange,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: unavailable
                ? const Center(
                    child: Column(
                      children: [
                        Icon(Icons.no_meals, size: 40, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(
                          "메뉴 정보가 없습니다.",
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.items
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 7),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    e,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (!unavailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : const Color(0xFFF8F9FA),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
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
                    onPressed: widget.onShare,
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
    final now = DateTime.now();
    final times = widget.type.timeRange.split("~")[1].trim().split(":");
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
  }
}

class DeveloperInfoPage extends StatelessWidget {
  const DeveloperInfoPage({super.key});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          "개발자 정보",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
              "Physics & Elementary Education 23",
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
                    _buildInfoRow(context, Icons.school, "소속", "한국교원대학교 물리교육과"),
                    const Divider(),
                    _buildInfoRow(
                      context,
                      Icons.code,
                      "관심 분야",
                      "Physical Computing, Embedded System , AI",
                    ),
                    const Divider(),
                    _buildInfoRow(
                      context,
                      Icons.email,
                      "이메일",
                      "knuemeal16486@gmail.com",
                    ),
                    const Divider(),
                    _buildInfoRow(
                      context,
                      Icons.money,
                      "후원",
                      "고생한 개발자를 위해 커피 사주기\n신한 110-334-965296",
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "© 2026 KNUE All-in-One",
              style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String content,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).primaryColor),
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
              Text(content, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNavBar({required this.currentIndex, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(context, 0, Icons.restaurant, "오늘의 식단", primary),
              _item(context, 1, Icons.calendar_month, "월간 식단표", primary),
              _item(context, 2, Icons.settings, "환경설정", primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData icon,
    String label,
    Color primary,
  ) {
    final isSel = index == currentIndex;
    return InkWell(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSel ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSel ? Colors.white : Colors.grey),
            if (isSel) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final Color primaryColor;
  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDateSelected,
    required this.primaryColor,
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
        final isSel = DateUtils.isSameDay(date, selectedDate);
        final isToday = DateUtils.isSameDay(date, DateTime.now());
        Color textColor = isSel
            ? Colors.white
            : (date.weekday == DateTime.sunday
                  ? Colors.redAccent
                  : (date.weekday == DateTime.saturday
                        ? Colors.blueAccent
                        : (isDark ? Colors.white : Colors.black87)));
        return GestureDetector(
          onTap: () => onDateSelected(date),
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
        color: color,
        shape: BoxShape.circle,
        border: isSelected ? Border.all(width: 3, color: Colors.white) : null,
      ),
    ),
  );
}

class _AppSwitchOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _AppSwitchOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? (isDark ? Colors.white : Theme.of(context).primaryColor)
        : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? Colors.white24
                    : Theme.of(context).primaryColor.withOpacity(0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white54 : Theme.of(context).primaryColor)
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
                color: color,
              ),
            ),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}

class _MealTabs extends StatelessWidget {
  final MealType selected;
  final ValueChanged<MealType> onSelect;
  const _MealTabs({required this.selected, required this.onSelect});
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
          children: MealType.values.map((t) {
            final isSel = t == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
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
          }).toList(),
        ),
      ),
    );
  }
}

class _CommonMealLayout extends StatelessWidget {
  final Widget header;
  final Widget content;
  const _CommonMealLayout({required this.header, required this.content});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        header,
        Expanded(child: content),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: Colors.red)),
  );
}
