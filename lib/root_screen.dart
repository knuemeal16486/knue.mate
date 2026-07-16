import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'bus_screen.dart';
import 'campus_map_screen.dart';
import 'campus_run_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'dart:ui';

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
      case AppTab.more:
        return const MoreScreen();
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
          color: theme.scaffoldBackgroundColor.withOpacity(0.8),
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              width: 0.5,
            ),
          ),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: theme.primaryColor,
              unselectedItemColor: isDark ? Colors.white54 : Colors.black45,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              items: tabs.map((tab) {
                return BottomNavigationBarItem(
                  icon: Icon(tab.icon),
                  activeIcon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tab.icon),
                  ),
                  label: tab.label,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
