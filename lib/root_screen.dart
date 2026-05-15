import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'bus_screen.dart';
import 'campus_map_screen.dart';
import 'campus_run_screen.dart';

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
      if (index != -1) state._onTabTapped(index);
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
    if (index == _currentIndex) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _getScreenForTab(AppTab tab) {
    switch (tab) {
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
      key: RootNavigationScreen.navKey,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (index != _currentIndex) setState(() => _currentIndex = index);
        },
        physics: const NeverScrollableScrollPhysics(),
        children: tabs.map((t) => _getScreenForTab(t)).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onTabTapped,
        selectedIndex: _currentIndex,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.08),
        elevation: 0,
        indicatorColor: theme.primaryColor.withOpacity(isDark ? 0.2 : 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 300),
        destinations: tabs.map((tab) {
          return NavigationDestination(
            icon: Icon(
              tab.icon,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(tab.icon, color: theme.primaryColor),
            label: tab.label,
            tooltip: tab.label,
          );
        }).toList(),
      ),
    );
  }
}
