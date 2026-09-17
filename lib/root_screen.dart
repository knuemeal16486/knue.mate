import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
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

  /// 마지막으로 뒤로가기를 누른 시각. 2초 안에 다시 누르면 진짜로 종료한다.
  DateTime? _lastBackPress;

  /// 광고주 문의 연락처. 종료 팝업 하단에 항상 노출된다.
  static const _sponsorPhone = "010-8032-8088";

  /// 무료 프로모션 종료 시점. 이 날짜까지는 무료, 이후로는 주당 과금.
  /// 값을 여기 한 곳만 고치면 팝업 문구가 자동으로 맞춰진다 — 9월 30일이
  /// 지났는데도 "무료"라고 잘못 보여주는 일이 없게, 문구 자체를 날짜로
  /// 판단한다(사람이 그날 기억했다가 따로 문구를 바꿔줄 필요가 없다).
  static final _freePromoEnds = DateTime(2026, 9, 30, 23, 59, 59);

  /// 광고 단가 문구. 프로모션 기간이면 무료 안내를, 지났으면 주당 단가를 보여준다.
  String get _sponsorPriceText {
    if (DateTime.now().isBefore(_freePromoEnds)) {
      return "9월 30일까지 무료 · 이후 주당 10,000원";
    }
    return "주당 10,000원";
  }

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
  // 홈에서 뒤로가기를 누르면 그대로 앱이 꺼졌다. 그 한 번을 빌려 동아리·학과
  // 행사를 알리고, 광고주(행사 주최 측)를 모집하는 문구를 보여준다 — 이
  // 팝업은 오직 그 용도로만 쓴다(다른 스폰서·애드몹 광고는 안 섞는다).
  // 매번 뜨긴 하지만 "한 번 더 누르면 종료"를 팝업 안에 같이 적어 두므로,
  // 종료 자체를 막지는 않는다: 2초 안에 다시 누르면 그대로 꺼진다.
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
    await _showExitPromo();
  }

  /// 지금 진행중인 동아리·학과 행사 중 하나. 캐시를 먼저 돌려주므로
  /// 뒤로가기가 네트워크를 기다리지 않는다. 실패해도 팝업 자체는 뜬다 —
  /// 행사 소개가 빠질 뿐, 광고주 모집 문구와 종료 안내는 항상 나와야 한다.
  Future<ClubEvent?> _currentOngoingEvent(DateTime now) async {
    try {
      final events = await ClubEventService.fetchAll();
      final ongoing = events.where((e) => e.isOngoing(now)).toList()
        ..sort((a, b) => ClubEvent.compareForList(a, b, now));
      return ongoing.isEmpty ? null : ongoing.first;
    } catch (_) {
      return null;
    }
  }

  /// 광고주 모집 문구의 연락처를 눌렀을 때 전화 앱을 연다.
  /// 광고주 모집 문구의 연락처를 눌렀을 때 문자 앱을 연다(전화 걸기 아님).
  Future<void> _messageSponsorContact(BuildContext context) async {
    final uri = Uri(
      scheme: 'sms',
      path: _sponsorPhone.replaceAll('-', ''),
      queryParameters: {
        'body': '[KNUE Mate 광고 문의] 행사/제휴 광고 게재 문의드립니다. ',
      },
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (context.mounted) {
        showToast(context, "문자 앱을 열 수 없습니다. $_sponsorPhone로 연락해 주세요");
      }
    } catch (_) {
      if (context.mounted) {
        showToast(context, "문자 앱을 열 수 없습니다. $_sponsorPhone로 연락해 주세요");
      }
    }
  }

  Future<void> _showExitPromo() async {
    final now = DateTime.now();
    final event = await _currentOngoingEvent(now);
    if (!mounted) return;

    final color = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.white60 : Colors.black54;

    String when(ClubEvent e) {
      final s = e.startDate;
      final end = e.endDate;
      final start = "${s.month}월 ${s.day}일";
      if (end == null || DateUtils.isSameDay(s, end)) return start;
      return "$start ~ ${end.month}월 ${end.day}일";
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
            if (event != null &&
                event.posterUrl != null &&
                event.posterUrl!.isNotEmpty)
              Image.network(
                event.posterUrl!,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event != null) ...[
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
                          ? when(event)
                          : "${when(event)} · ${event.location}",
                      style: TextStyle(fontSize: 13, color: sub),
                    ),
                  ] else ...[
                    Text(
                      "지금 진행중인 동아리·학과 행사",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: sub,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "아직 등록된 행사가 없어요",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: sub),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "뒤로 한 번 더 누르면 종료됩니다",
                          style: TextStyle(fontSize: 12.5, color: sub),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 광고주(행사 주최 측) 모집 — 이 팝업이 존재하는 진짜
                  // 이유다. 연락처를 누르면 문자 앱으로 연결한다(전화 아님).
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _messageSponsorContact(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text("📣", style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "우리 동아리·학과 행사도 여기 올리고 싶다면?",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _sponsorPriceText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: sub,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "광고 문의 · $_sponsorPhone (문자)",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.sms_rounded, size: 16, color: color),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "KNUE Mate가 오늘의 캠퍼스 소식을 전해드려요",
              style: TextStyle(
                fontSize: 10.5,
                color: sub.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 18),
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
          // PageView는 모든 탭을 한꺼번에 마운트해두고 안 보이는 탭도 계속
          // 살아있다 — 홈 탭의 날씨 파티클 애니메이션처럼 AnimationController를
          // 쓰는 화면은 다른 탭을 보고 있어도 계속 돌아 배터리를 먹는다.
          // TickerMode(enabled: false)를 씌우면 안 보이는 탭의 티커를
          // 자동으로 멈춰준다(위젯마다 직접 가시성을 체크할 필요 없음).
          children: List.generate(
            tabs.length,
            (i) => TickerMode(
              enabled: i == _currentIndex,
              child: _getScreenForTab(tabs[i]),
            ),
          ),
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
