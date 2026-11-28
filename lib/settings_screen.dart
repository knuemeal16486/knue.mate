// 설정 탭(SettingsPage)과 그 화면에서만 쓰는 것들 — lib/meal_screen.dart에서 옮겼다(2026-11-25).
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';
import 'firebase_sync_service.dart';
import 'meal_widget.dart' show clearMealWidgetSourceOverride;
import 'package:flutter/foundation.dart';
import 'tab_edit_screen.dart';
import 'notice_alert_settings_screen.dart';
import 'interstitial_ad_service.dart';
import 'ui_utils.dart';
import 'club_event_admin_screen.dart';
import 'housing_admin_screen.dart';
import 'sponsor_admin_screen.dart';
import 'native_ad_card.dart';
import 'widget_settings_screen.dart';

// =============================================================================
// 4. 설정 페이지
// =============================================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _versionTapCount = 0;

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
            // 개발용 — 위젯에 가짜 "테스트 식당" 글을 넣는다(예전엔 설정 화면에 모두에게 보였다).
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text("위젯에 테스트 데이터 넣기"),
              onTap: () {
                Navigator.pop(sheetContext);
                testBasicWidgetFunction();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text("건물 정보 Firestore 동기화"),
              subtitle: const Text("로컬 건물 JSON을 서버에 반영 (관리자 전용)"),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseSyncService.uploadBuildingsToFirestore();
                if (mounted) {
                  showToast(context, "건물 정보 동기화를 완료했습니다.");
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 설정 초기화 — 확인을 받고 설정 키만 지운다(개인 일정·D-day·캐시는 남긴다).
  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("설정 초기화"),
        content: const Text(
          "테마·탭 순서·공지 알림·위젯 설정을 기본값으로 되돌릴까요?\n"
          "개인 일정과 D-day는 그대로 둡니다.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소")),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text("초기화"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PreferencesService.resetSettings();
    // 위젯도 기본 모양·기본 식당으로.
    await clearMealWidgetSourceOverride();
    await applyWidgetAppearance();
    unawaited(refreshMealWidgetNow());
    if (!context.mounted) return;
    showToast(context, "초기화되었습니다.");
  }

  Widget _buildGroupedRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = destructive ? Colors.redAccent : iconColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          KnueHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: destructive
                            ? Colors.redAccent
                            : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: KnueTokens.caption(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsetGroup(bool isDark, List<Widget> children) {
    return KnueCard(
      isDark: isDark,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KnueTokens.radiusCard),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 60,
                  color: KnueTokens.hairline(isDark),
                ),
              children[i],
            ],
          ],
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
    final onBrand = KnueTokens.onAccent(currentColor);

    return Scaffold(
      backgroundColor: KnueTokens.bg(isDark),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: Stack(
              fit: StackFit.expand,
              children: [
                AppleAppBarFlexibleSpace(
                  themeColor: currentColor,
                  isDark: isDark,
                ),
                FlexibleSpaceBar(
                  // FlexibleSpaceBar는 제목 정렬을 자기가 따로 정한다 —
                  // SliverAppBar.centerTitle도, AppBarTheme.centerTitle도 안 보고
                  // theme.platform만 본다. iOS면 무조건 가운데로 가기 때문에
                  // 여기서 직접 꺼야 다른 탭처럼 왼쪽에 붙는다.
                  centerTitle: false,
                  title: Text(
                    "설정",
                    style: TextStyle(
                      fontWeight: (!kIsWeb && Platform.isIOS)
                          ? FontWeight.w800
                          : FontWeight.bold,
                      color: onBrand,
                      shadows: KnueTokens.headerShadows(currentColor),
                    ),
                  ),
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                ),
              ],
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KnueSectionHeader(title: "맞춤 설정"),
                    _buildInsetGroup(isDark, [
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.swap_calls_rounded,
                        title: "하단 탭 순서 및 시작화면",
                        subtitle: "내비게이션 탭의 순서를 변경하거나 시작 화면 설정",
                        iconColor: KnueTokens.inkAt(6, isDark),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const TabEditScreen(),
                          ),
                        ),
                      ),
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.notifications_active_rounded,
                        title: "공지 알림",
                        subtitle: "알림 켜고 끄기, 알림 받을 키워드 관리",
                        iconColor: KnueTokens.inkAt(2, isDark),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const NoticeAlertSettingsScreen(),
                          ),
                        ),
                      ),
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.widgets_rounded,
                        title: "홈 위젯",
                        subtitle: "식단·버스·공지 위젯 모양과 표시할 식당",
                        iconColor: KnueTokens.inkAt(1, isDark),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const WidgetSettingsScreen(),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    const KnueSectionHeader(title: "앱 테마"),
                    KnueCard(
                      isDark: isDark,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeNotifier,
                        builder: (context, mode, _) => Row(
                          children: [
                            SettingsThemeOption(
                              label: "라이트",
                              icon: Icons.light_mode_rounded,
                              selected: mode == ThemeMode.light,
                              onTap: () {
                                themeModeNotifier.value = ThemeMode.light;
                                PreferencesService.saveThemeMode(
                                  ThemeMode.light,
                                );
                              },
                            ),
                            SettingsThemeOption(
                              label: "다크",
                              icon: Icons.dark_mode_rounded,
                              selected: mode == ThemeMode.dark,
                              onTap: () {
                                themeModeNotifier.value = ThemeMode.dark;
                                PreferencesService.saveThemeMode(
                                  ThemeMode.dark,
                                );
                              },
                            ),
                            SettingsThemeOption(
                              label: "시스템",
                              icon: Icons.settings_brightness_rounded,
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
                    const SizedBox(height: 20),
                    const KnueSectionHeader(title: "테마 색상"),
                    KnueCard(
                      isDark: isDark,
                      padding: const EdgeInsets.all(16),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: rainbowModeNotifier,
                        builder: (context, rainbowOn, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 실시간 테마 헤더 미리보기 — 펄 광택과 글씨 대비를 즉각 확인.
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                gradient: KnuePearl.headerGradient(
                                  currentColor,
                                  isDark,
                                ),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    rainbowOn ? "오늘의 무지개 테마" : "현재 선택된 테마 미리보기",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: onBrand,
                                      shadows: KnueTokens.headerShadows(currentColor),
                                    ),
                                  ),
                                  Icon(
                                    Icons.palette_rounded,
                                    size: 16,
                                    color: onBrand,
                                    shadows: KnueTokens.headerShadows(currentColor),
                                  ),
                                ],
                              ),
                            ),
                            // 무지개 모드가 켜져 있으면 색을 직접 고를 수 없다는
                            // 걸 흐리게 해서 보여준다(탭은 아래에서 막는다).
                            Opacity(
                              opacity: rainbowOn ? 0.4 : 1.0,
                              child: IgnorePointer(
                                ignoring: rainbowOn,
                                // Wrap은 한 줄에 몇 개가 들어가는지가 스와치
                                // 폭(고정 40)으로만 정해져서, 5개를 채우고 남는
                                // 오밀조밀하고 콤팩트한 중앙 정렬 Wrap 레이아웃
                                child: Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final c in kColorPalette)
                                        _ColorPickerItem(
                                          color: c,
                                          isSelected: !rainbowOn &&
                                              c.toARGB32() == currentColor.toARGB32(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Divider(height: 0.5, color: KnueTokens.hairline(isDark)),
                            const SizedBox(height: 10),
                            _RainbowModeTile(isOn: rainbowOn),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const KnueSectionHeader(title: "앱 정보"),
                    _buildInsetGroup(isDark, [
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.face_rounded,
                        title: "개발자 정보",
                        subtitle: "만든 사람 소개",
                        iconColor: KnueTokens.inkAt(0, isDark),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DeveloperInfoPage(),
                          ),
                        ),
                      ),
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.feedback_outlined,
                        title: "사용자 의견 보내기",
                        subtitle: "버그 제보 및 기능 제안",
                        iconColor: KnueTokens.inkAt(5, isDark),
                        onTap: () => _showFeedbackDialog(context),
                      ),
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.description_outlined,
                        title: "오픈소스 라이선스",
                        subtitle: "사용된 라이브러리 정보",
                        iconColor: KnueTokens.inkAt(3, isDark),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: "KNUE Mate",
                          applicationVersion: appVersionLabel.value,
                        ),
                      ),
                      _buildGroupedRow(
                        context: context,
                        icon: Icons.refresh_rounded,
                        title: "설정 초기화",
                        subtitle: "앱 설정을 기본값으로 되돌리기",
                        iconColor: Colors.redAccent,
                        destructive: true,
                        onTap: () => _confirmReset(context),
                      ),
                    ]),

                    const SizedBox(height: 20),
                    const KnueSectionHeader(title: "스폰서 & 제휴"),
                    const KnueNativeAdCard(isCompact: true, placement: 'settings'),
                    const SizedBox(height: 18),

                    Center(
                      child: GestureDetector(
                        onTap: _onVersionTap,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ValueListenableBuilder<String>(
                            valueListenable: appVersionLabel,
                            builder: (context, version, _) => Text(
                              version.isEmpty ? "버전 정보" : "버전 $version",
                              style: TextStyle(
                                color: KnueTokens.caption(isDark),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
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
    final onBrand = KnueTokens.onAccent(primary);
    return Scaffold(
      backgroundColor: KnueTokens.bg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: AppleAppBarFlexibleSpace(
          themeColor: primary,
          isDark: isDark,
        ),
        title: Text(
          "개발자 정보",
          style: TextStyle(
            fontWeight: (!kIsWeb && Platform.isIOS) ? FontWeight.w800 : FontWeight.bold,
            color: onBrand,
            shadows: KnueTokens.headerShadows(primary),
          ),
        ),
        iconTheme: IconThemeData(color: onBrand),
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
                color: primary.withValues(alpha: 0.1),
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
                      color: Colors.black.withValues(alpha: 0.05),
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
                      color: Colors.black.withValues(alpha: 0.05),
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
            color: color.withValues(alpha: 0.1),
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


class SettingsThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const SettingsThemeOption({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentFg = KnueTokens.accentForeground(
      Theme.of(context).primaryColor,
      isDark,
    );
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            KnueHaptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: selected
                  ? accentFg.withValues(alpha: isDark ? 0.18 : 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? accentFg : KnueTokens.caption(isDark),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? accentFg
                        : (isDark ? Colors.white70 : Colors.black87),
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

class SettingsChoiceOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const SettingsChoiceOption({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBrand = KnueTokens.onAccent(primary);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            KnueHaptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? primary : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: isSelected ? primary : KnueTokens.hairline(isDark),
                width: isSelected ? 1.2 : 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? onBrand : KnueTokens.caption(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

  /// 끄는 건 바로 처리하지만, 켜려면 광고를 한 번 거친다.
  ///
  /// 예전엔 보상형 광고라 30초를 끝까지 봐야 했다. 테마 색이 매일 바뀌는
  /// 것치고는 너무 길어서 전면 광고로 바꿨다 — 몇 초 뒤 닫을 수 있다.
  ///
  /// 광고를 못 띄우면 **그냥 켜준다.** 색이 바뀌는 기능일 뿐인데 광고가 안
  /// 불러와졌다는 이유로 스위치가 안 먹으면 사용자 눈에는 고장으로 보인다.
  Future<void> _handleToggle(BuildContext context, bool wantsOn) async {
    if (!wantsOn) {
      await PreferencesService.setRainbowMode(false);
      return;
    }
    if (!InterstitialAdService.isConfigured) {
      await PreferencesService.setRainbowMode(true);
      return;
    }
    showToast(context, "광고를 닫으면 무지개 모드가 켜져요 🌈");
    await InterstitialAdService.show(
      onClosed: () => PreferencesService.setRainbowMode(true),
      onUnavailable: () => PreferencesService.setRainbowMode(true),
    );
  }
}

/// 광고를 끝까지 보면 테마 색을 무작위로 하나 뽑아 적용한다.
/// 팔레트를 훑어보기 귀찮은 사람을 위한 "아무거나 골라줘" 버튼.
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
    child: SizedBox(
      width: 34,
      height: 34,
      child: _swatch(),
    ),
  );

  Widget _swatch() => AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: KnuePearl.swatchGradient(color),
        shape: BoxShape.circle,
        border: isSelected
            ? Border.all(width: 2.5, color: Colors.white)
            : Border.all(width: 1.0, color: Colors.black.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isSelected ? 0.45 : 0.20),
            blurRadius: isSelected ? 8 : 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: KnuePearl.sheen(),
        ),
      ),
    );
}
