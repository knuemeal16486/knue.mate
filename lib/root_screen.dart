import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'bus_screen.dart';
import 'campus_map_screen.dart';
import 'campus_run_screen.dart';
import 'home_screen.dart';

class RootNavigationScreen extends StatefulWidget {
  static final GlobalKey<RootNavigationScreenState> navKey = GlobalKey<RootNavigationScreenState>();
  
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

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        physics: const NeverScrollableScrollPhysics(), 
        children: tabs.map((t) => _getScreenForTab(t)).toList(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 30,
              offset: const Offset(0, -10),
            ),
          ],
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
