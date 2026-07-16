import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'campus_run_screen.dart';
import 'constants.dart';
import 'keyword_alert_service.dart';
import 'meal_screen.dart' show SettingsPage;
import 'notice_screen.dart';
import 'staff_contacts_screen.dart';

/// 더보기 화면. 하단 탭에 배치하지 않은 기능(캠퍼스런/교직원 연락처/공지/일정)과
/// 설정으로 진입하는 허브. 디버그 빌드에서만 키워드 알림 즉시 테스트 타일을 노출한다.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _testingAlert = false;

  Future<void> _runKeywordAlertTest() async {
    if (_testingAlert) return;
    setState(() => _testingAlert = true);
    try {
      await KeywordAlertService.checkAndNotify();
      if (mounted) showToast(context, "키워드 알림 테스트를 실행했습니다.");
    } catch (e) {
      if (mounted) showToast(context, "테스트 실행 실패: $e");
    } finally {
      if (mounted) setState(() => _testingAlert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text("더보기"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _SectionHeader(title: "기능", isDark: isDark),
              const SizedBox(height: 8),
              _MoreTileGroup(
                isDark: isDark,
                children: [
                  _MoreTile(
                    icon: Icons.directions_run_rounded,
                    iconColor: Colors.green,
                    title: "캠퍼스런",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CampusRunScreen()),
                    ),
                  ),
                  _MoreTile(
                    icon: Icons.contact_phone_outlined,
                    iconColor: Colors.teal,
                    title: "교직원 연락처",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StaffContactsScreen()),
                    ),
                  ),
                  _MoreTile(
                    icon: Icons.campaign_outlined,
                    iconColor: Colors.orange,
                    title: "청람공지",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NoticeScreen()),
                    ),
                  ),
                  _MoreTile(
                    icon: Icons.event_note_outlined,
                    iconColor: Colors.deepPurple,
                    title: "청람일정",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    ),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionHeader(title: "앱", isDark: isDark),
              const SizedBox(height: 8),
              _MoreTileGroup(
                isDark: isDark,
                children: [
                  _MoreTile(
                    icon: Icons.settings_rounded,
                    iconColor: Colors.grey,
                    title: "설정",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                    showDivider: kDebugMode,
                  ),
                  if (kDebugMode)
                    _MoreTile(
                      icon: Icons.bug_report_outlined,
                      iconColor: Colors.redAccent,
                      title: "키워드 알림 즉시 테스트",
                      trailing: _testingAlert
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _runKeywordAlertTest,
                      showDivider: false,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  "버전 5.8.0 (Final)",
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
    );
  }
}

class _MoreTileGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _MoreTileGroup({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDivider;

  const _MoreTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.trailing,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white12
                : const Color(0xFFE5E7EB),
          ),
      ],
    );
  }
}
