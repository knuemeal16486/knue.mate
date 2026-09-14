import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'club_events_screen.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'bus_screen.dart';
import 'campus_map_screen.dart';
import 'campus_run_screen.dart';
import 'home_screen.dart';
import 'ui_utils.dart';

class RootNavigationScreen extends StatefulWidget {
  static final GlobalKey<RootNavigationScreenState> navKey =
      GlobalKey<RootNavigationScreenState>();

  const RootNavigationScreen({super.key});

  @override
  State<RootNavigationScreen> createState() => RootNavigationScreenState();

  static void switchTab(AppTab tab) {
    final state = navKey.currentState;
    if (state != null) {
      final index = PreferencesService.tabOrder.value.indexOf(tab);
      if (index != -1) {
        state._onTabTapped(index);
      }
    }
  }
}

class RootNavigationScreenState extends State<RootNavigationScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  /// 행사 홍보 팝업을 띄운 날짜(yyyy-M-d). 하루에 한 번만 띄운다.
  static const _promoKey = 'eventPromoShownDate';
  DateTime? _lastBackPress;
  bool _promoOpen = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    // 탭 순서가 바뀌었을 때 UI를 갱신하기 위한 리스너
    PreferencesService.tabOrder.addListener(_onTabOrderChanged);
  }

  @override
  void dispose() {
    PreferencesService.tabOrder.removeListener(_onTabOrderChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onTabOrderChanged() {
    if (mounted) setState(() {});
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ── 뒤로가기 ──────────────────────────────────────────────────────────
  //
  // 홈에서 뒤로가기를 누르면 그대로 앱이 꺼졌다. 그 한 번을 빌려 지금 열리고
  // 있는 행사를 알린다. 매번 띄우면 앱을 못 끄게 막는 셈이라 하루 한 번으로
  // 제한하고, 그 뒤로는 흔한 "한 번 더 누르면 종료"로 돌아간다.
  Future<void> _handleBack() async {
    final tabs = PreferencesService.tabOrder.value;
    final homeIndex = tabs.indexOf(AppTab.home);
    if (homeIndex != -1 && _currentIndex != homeIndex) {
      _onTabTapped(homeIndex);
      return;
    }
    if (await _maybeShowEventPromo()) return;

    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    if (mounted) showToast(context, "뒤로 한 번 더 누르면 종료됩니다");
  }

  /// 진행중인 행사가 있고 오늘 아직 안 띄웠으면 팝업을 띄운다.
  /// 띄웠으면 true — 이번 뒤로가기는 여기서 끝난다.
  Future<bool> _maybeShowEventPromo() async {
    if (_promoOpen) return true;
    final now = DateTime.now();
    final todayKey = "${now.year}-${now.month}-${now.day}";
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_promoKey) == todayKey) return false;

    List<ClubEvent> events;
    try {
      // 캐시를 먼저 돌려주므로 뒤로가기가 네트워크를 기다리지 않는다.
      events = await ClubEventService.fetchAll();
    } catch (_) {
      return false;
    }
    final ongoing = events.where((e) => e.isOngoing(now)).toList()
      ..sort((a, b) => ClubEvent.compareForList(a, b, now));
    if (ongoing.isEmpty || !mounted) return false;

    await prefs.setString(_promoKey, todayKey);
    _promoOpen = true;
    await _showEventPromo(ongoing.first);
    _promoOpen = false;
    return true;
  }

  Future<void> _showEventPromo(ClubEvent event) async {
    final color = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.white60 : Colors.black54;

    String when() {
      final s = event.startDate;
      final e = event.endDate;
      final start = "${s.month}월 ${s.day}일";
      if (e == null || DateUtils.isSameDay(s, e)) return start;
      return "$start ~ ${e.month}월 ${e.day}일";
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (event.posterUrl != null && event.posterUrl!.isNotEmpty)
              Image.network(
                event.posterUrl!,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.28 : 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      "지금 진행중 · ${event.category.label}",
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.location.isEmpty
                        ? when()
                        : "${when()} · ${event.location}",
                    style: TextStyle(fontSize: 13, color: sub),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text("닫기", style: TextStyle(color: sub)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ClubEventsScreen(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(backgroundColor: color),
                      child: const Text("보러 가기"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "교원대 메이트가 오늘의 캠퍼스 소식을 전해드려요",
              style: TextStyle(
                fontSize: 10.5,
                color: sub.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
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
          children: tabs.map((t) => _getScreenForTab(t)).toList(),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    _buildNavItem(tabs[i], i, theme.primaryColor, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 3월 원본 pill 스타일 항목 — 선택 탭은 컬러 알약(아이콘+라벨), 비선택은 아이콘만.
  Widget _buildNavItem(AppTab tab, int index, Color color, bool isDark) {
    final isSel = index == _currentIndex;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 22,
              color: isSel
                  ? Colors.white
                  : (isDark ? Colors.white38 : Colors.grey),
            ),
            if (isSel) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
