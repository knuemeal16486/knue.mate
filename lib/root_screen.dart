import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'analytics.dart';
import 'app_update.dart';
import 'main.dart' show pendingWidgetTab;
import 'constants.dart';
import 'meal_reminder.dart';
import 'meal_screen.dart';
import 'settings_screen.dart';
import 'bus_screen.dart';
import 'campus_map_screen.dart';
import 'campus_run_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'ui_utils.dart';
export 'features/root/exit_promo_sponsor_box.dart';

class RootNavigationScreen extends StatefulWidget {
  static final GlobalKey<RootNavigationScreenState> navKey =
      GlobalKey<RootNavigationScreenState>();

  const RootNavigationScreen({super.key});

  @override
  State<RootNavigationScreen> createState() => RootNavigationScreenState();

  /// 탭 전환 시 특정 서브 탭(예: 버스 탭의 실시간 위치 = 1)으로 바로 이동하기 위한 요청.
  static final ValueNotifier<({int tabIndex, int seq})?> busSubTabRequest =
      ValueNotifier(null);
  static int _subTabSeq = 0;

  /// 탭을 옮긴다. 아직 화면이 안 만들어졌거나(앱이 막 켜지는 중) 그 탭을
  /// 숨겨 뒀으면 false — 호출부가 나중에 다시 시도할지 정할 수 있게 한다.
  static bool switchTab(AppTab tab, {int? subTabIndex}) {
    final state = navKey.currentState;
    if (state == null) return false;
    final index = PreferencesService.tabOrder.value.indexOf(tab);
    if (index == -1) return false;
    if (tab == AppTab.bus && subTabIndex != null) {
      busSubTabRequest.value = (tabIndex: subTabIndex, seq: ++_subTabSeq);
    }
    state._onTabTapped(index);
    return true;
  }
}

class RootNavigationScreenState extends State<RootNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late PageController _pageController;

  /// 식사시간 종료 10분 전 "식사하셨나요?" 팝업 점검 타이머. 앱이 포그라운드에
  /// 있는 동안만 주기적으로 확인한다 — 백그라운드에서는 어차피 타이머가
  /// 멈추므로(iOS/Android 공통) 별도로 막을 필요가 없다.
  Timer? _mealReminderTimer;

  /// 탭 전환 애니메이션(400ms) 도중에는 방금 떠난 탭도 화면에 걸쳐 보인다.
  /// TickerMode(enabled: i == _currentIndex)만 쓰면 탭을 누른 그 순간
  /// _currentIndex가 바로 바뀌어서, 아직 슬라이드 중인 이전 탭의 애니메이션이
  /// (예: 홈 탭 날씨 파티클) 화면에 남아있는 채로 뚝 멈춰버린다. 애니메이션이
  /// 끝날 때까지는 이 인덱스도 같이 티커를 켜둔다.
  int? _previousIndexAnimating;

  /// 마지막으로 뒤로가기를 누른 시각. 2초 안에 다시 누르면 진짜로 종료한다.
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    // 탭 순서가 바뀌었을 때 UI를 갱신하기 위한 리스너
    PreferencesService.tabOrder.addListener(_onTabOrderChanged);

    WidgetsBinding.instance.addObserver(this);

    // 새 버전이 나왔으면 업데이트를 강제하고, 신규 설치 사용자는 15초 맞춤 설정을 안내한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppUpdateGate.check(context, force: true);
      if (pendingWidgetTab == null) {
        unawaited(KnueOnboardingSheet.maybeShow(context));
      }
    });

    // 처음 보이는 탭도 센다(탭을 누르지 않고 끄는 사람이 대부분이다).
    _logCurrentTab();

    // 앱이 꺼져 있다가 홈 위젯을 눌러 열린 경우, 그 판단은 이 화면이
    // 만들어지기 전에 끝나 있다. 남겨 둔 탭이 있으면 첫 프레임 뒤에 옮긴다.
    final pending = pendingWidgetTab;
    if (pending != null) {
      pendingWidgetTab = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) RootNavigationScreen.switchTab(pending);
      });
    }

    // 앱을 막 열었을 때도 이미 "종료 10분 전" 구간일 수 있다 — 타이머 첫
    // 주기(1분)를 기다리지 않고 바로 한 번 확인한다.
    _checkMealReminder();
    _mealReminderTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkMealReminder(),
    );
  }

  @override
  void dispose() {
    PreferencesService.tabOrder.removeListener(_onTabOrderChanged);
    WidgetsBinding.instance.removeObserver(this);
    _mealReminderTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에 있다가 막 돌아왔을 때 — 다음 1분 주기까지 기다리지 않고
    // 바로 확인한다. 마침 종료 10분 구간에 딱 돌아왔는데 59초를 더 기다리게
    // 하고 싶지 않다.
    if (state == AppLifecycleState.resumed) {
      _checkMealReminder();
      // 켜 둔 채로 며칠 지났을 수 있다(한 시간에 한 번만 확인한다).
      AppUpdateGate.check(context);
      _logCurrentTab();
    }
  }

  /// 지금 보이는 탭을 사용 통계에 적는다([AppAnalytics.logTab]).
  void _logCurrentTab() {
    final tabs = PreferencesService.tabOrder.value;
    if (_currentIndex < 0 || _currentIndex >= tabs.length) return;
    AppAnalytics.logTab(tabs[_currentIndex]);
  }

  void _checkMealReminder() {
    if (!mounted) return;
    MealReminder.maybeShow(context);
  }

  void _onTabOrderChanged() {
    if (mounted) setState(() {});
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    final leaving = _currentIndex;
    // 떨어진 탭으로 갈 때는 미끄러지지 않고 바로 넘어간다. 미끄러지면 사이에
    // 있는 탭이 전부 화면을 스쳐 가며 만들어진다 — 홈에서 설정으로 가기만 해도
    // 버스 탭이 버스 API를 부르고 지도 탭이 Firestore 읽기 약 270건을 썼다
    // (하루 읽기 한도가 찬 원인 중 하나, 2026-10-08).
    if ((index - leaving).abs() > 1) {
      setState(() {
        _previousIndexAnimating = null;
        _currentIndex = index;
      });
      _logCurrentTab();
      _pageController.jumpToPage(index);
      return;
    }
    setState(() {
      _previousIndexAnimating = leaving;
      _currentIndex = index;
    });
    _logCurrentTab();
    _pageController
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        )
        .then((_) {
          if (!mounted) return;
          setState(() => _previousIndexAnimating = null);
        });
  }

  // ── 뒤로가기 ──────────────────────────────────────────────────────────
  //
  // 다른 탭에 있으면 홈 탭으로 먼저 돌아오고, 홈에서는 2초 안에 한 번 더
  // 누르면 종료한다. 종료 순간에 광고 팝업으로 길을 막지 않고 가벼운
  // 토스트로만 안내해 마지막 인상을 깔끔하게 유지한다.
  Future<void> _handleBack() async {
    final tabs = PreferencesService.tabOrder.value;
    final homeIndex = tabs.indexOf(AppTab.home);
    if (homeIndex != -1 && _currentIndex != homeIndex) {
      _onTabTapped(homeIndex);
      return;
    }

    final now = DateTime.now();
    final isSecondPress =
        _lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2);
    if (isSecondPress) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    if (mounted) {
      showToast(context, "한 번 더 누르면 앱이 종료됩니다");
    }
  }

  Widget _getScreenForTab(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return const HomeScreen();
      case AppTab.meal:
        return const MealTabPage();
      case AppTab.bus:
        return const BusAppScreen();
      case AppTab.run:
        return const CampusRunScreen();
      case AppTab.map:
        return const CampusMapScreen();
      case AppTab.settings:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = PreferencesService.tabOrder.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          physics: const NeverScrollableScrollPhysics(),
          // PageView는 화면에서 벗어난 탭을 dispose한다(타이머·구독도 같이 끝남) —
          // 다만 wantKeepAlive인 탭(식단·지도)은 살아남는다(2026-11-25 테스트로 확인).
          // 살아남은 탭의 AnimationController가 계속 돌지 않게 TickerMode로 티커를
          // 멈춘다. Timer.periodic은 TickerMode로 안 멈추니, keepAlive 탭에 주기
          // 타이머를 넣을 땐 따로 멈춰야 한다.
          // 전환 애니메이션(400ms) 도중엔 방금 떠난 탭도 같이 켜둔다 —
          // 안 그러면 탭을 누른 순간 이전 탭 애니메이션이 화면에 남아있는
          // 채로 뚝 멈춰버린다.
          children: List.generate(
            tabs.length,
            (i) => TickerMode(
              enabled: i == _currentIndex || i == _previousIndexAnimating,
              child: _getScreenForTab(tabs[i]),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: KnueTokens.surface(isDark),
            // 카드와 같은 이중 섀도를 위로 뒤집어 쓴다 — 앱 전체 재질 통일.
            boxShadow: KnueTokens.cardShadow(isDark)
                .map(
                  (s) => BoxShadow(
                    color: s.color,
                    blurRadius: s.blurRadius,
                    offset: Offset(0, -s.offset.dy),
                  ),
                )
                .toList(),
            border: Border(
              top: BorderSide(color: KnueTokens.hairline(isDark), width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _buildNavItem(
                        tabs[i],
                        i,
                        theme.primaryColor,
                        isDark,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 5탭 상시 라벨 내비게이션 항목 — 비선택 탭도 라벨을 보여 탐색 비용을 줄이고,
  /// 선택 탭은 대비가 보정된 은은한 틴트 알약으로 또렷하게 강조한다.
  Widget _buildNavItem(AppTab tab, int index, Color color, bool isDark) {
    final isSel = index == _currentIndex;
    final accentFg = KnueTokens.accentForeground(color, isDark);
    final inactiveColor = isDark ? Colors.white54 : const Color(0xFF6E6E73);
    return Semantics(
      button: true,
      selected: isSel,
      label: '${tab.label} 탭',
      child: Tooltip(
        message: tab.label,
        child: GestureDetector(
          onTap: () => _onTabTapped(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: isSel
                  ? accentFg.withValues(alpha: isDark ? 0.18 : 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tab.icon,
                  size: 22,
                  color: isSel ? accentFg : inactiveColor,
                ),
                const SizedBox(height: 2),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSel ? accentFg : inactiveColor,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 10.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
