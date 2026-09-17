import 'package:flutter/material.dart';

import 'constants.dart';
import 'keyword_alert_service.dart';
import 'notice_screen.dart' show KeywordSheet;

/// 설정 탭 → "공지 알림" — 공지 알림을 받을지, 어떤 키워드에만 반응할지
/// 사용자가 직접 조절한다.
///
/// PreferencesService.noticeAlarmOn/saveNoticeAlarm은 예전부터 있었지만
/// 이걸 켜고 끄는 UI가 어디에도 없어서(코드 전체를 뒤져도 saveNoticeAlarm을
/// 부르는 곳이 없었다) 사용자가 앱 안에서 알림을 끌 방법이 아예 없었다.
class NoticeAlertSettingsScreen extends StatefulWidget {
  const NoticeAlertSettingsScreen({super.key});

  @override
  State<NoticeAlertSettingsScreen> createState() =>
      _NoticeAlertSettingsScreenState();
}

class _NoticeAlertSettingsScreenState
    extends State<NoticeAlertSettingsScreen> {
  Future<void> _setAlarmOn(bool on) async {
    await PreferencesService.saveNoticeAlarm(on);
    await KeywordAlertService.syncRegistration();
  }

  Future<void> _setMode(NoticeAlertMode mode) async {
    await PreferencesService.saveNoticeAlertMode(mode);
  }

  Future<void> _addHour(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: "알림 받을 시각",
    );
    if (picked == null) return;
    final hours = [...PreferencesService.noticeAlertHours.value, picked.hour];
    await PreferencesService.saveNoticeAlertHours(hours);
  }

  Future<void> _removeHour(int hour) async {
    final hours = PreferencesService.noticeAlertHours.value
        .where((h) => h != hour)
        .toList();
    if (hours.isEmpty) return; // 최소 1개는 남겨둔다 — 0개면 영영 안 보내진다
    await PreferencesService.saveNoticeAlertHours(hours);
  }

  @override
  Widget build(BuildContext context) {
    final color = themeColor.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("공지 알림"),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: PreferencesService.noticeAlarmOn,
              builder: (context, on, _) => SwitchListTile(
                title: const Text("새 공지 알림 받기"),
                subtitle: const Text("꺼두면 학교 공지 관련 푸시 알림이 전혀 오지 않아요."),
                value: on,
                activeThumbColor: color,
                onChanged: _setAlarmOn,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<bool>(
            valueListenable: PreferencesService.noticeAlarmOn,
            builder: (context, on, _) => AnimatedOpacity(
              opacity: on ? 1 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !on,
                child: Column(
                  children: [
                    _buildTimingSection(context, color, isDark),
                    const SizedBox(height: 20),
                    _buildKeywordSection(context, color, isDark),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingSection(BuildContext context, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "알림 도착 시점",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            "새 공지를 발견할 때마다 바로 받을지, 하루 중 정해둔 시각에 모아서 "
            "받을지 고를 수 있어요.",
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<NoticeAlertMode>(
            valueListenable: PreferencesService.noticeAlertMode,
            builder: (context, mode, _) => RadioGroup<NoticeAlertMode>(
              groupValue: mode,
              onChanged: (v) => _setMode(v!),
              child: Column(
                children: [
                  RadioListTile<NoticeAlertMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text("올라오는 즉시"),
                    value: NoticeAlertMode.instant,
                    activeColor: color,
                  ),
                  RadioListTile<NoticeAlertMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text("하루 중 지정한 시각에 모아서"),
                    value: NoticeAlertMode.scheduled,
                    activeColor: color,
                  ),
                  if (mode == NoticeAlertMode.scheduled)
                    _buildHoursEditor(context, color, isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoursEditor(BuildContext context, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "정확히 그 시각은 아니고, 지정 시각 이후 다음 점검 때(최대 몇 시간 "
            "이내) 모아서 알려드려요 — 특히 iOS는 백그라운드 점검 시각을 시스템이 "
            "정해서 앱이 정확한 시각을 보장할 수 없어요.",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white38 : Colors.black38,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<List<int>>(
            valueListenable: PreferencesService.noticeAlertHours,
            builder: (context, hours, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in hours)
                  Chip(
                    label: Text(
                      TimeOfDay(hour: h, minute: 0).format(context),
                    ),
                    onDeleted:
                        hours.length > 1 ? () => _removeHour(h) : null,
                    backgroundColor: color.withValues(alpha: 0.12),
                    labelStyle: TextStyle(color: color),
                    deleteIconColor: color,
                  ),
                ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 16, color: color),
                  label: const Text("시각 추가"),
                  onPressed: () => _addHour(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordSection(BuildContext context, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "알림 키워드",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            "등록한 키워드가 제목에 포함된 새 공지만 알려드려요. 알림이 너무 잦다면 "
            "여기서 키워드를 구체적으로 좁혀보세요 — 키워드가 하나도 없으면 "
            "즐겨찾기한 게시판의 모든 새 글을 알려드려서 알림이 많아질 수 있어요.",
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<List<String>>(
            valueListenable: PreferencesService.noticeKeywords,
            builder: (context, keywords, _) {
              if (keywords.isEmpty) {
                return Text(
                  "등록된 키워드 없음 — 즐겨찾기 게시판 전체 알림",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords
                    .map(
                      (kw) => Chip(
                        label: Text(kw),
                        backgroundColor: color.withValues(alpha: 0.12),
                        labelStyle: TextStyle(color: color),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (sheetContext) => KeywordSheet(color: color),
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text("키워드 관리"),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "즐겨찾기 게시판은 청람공지 탭에서 게시판 이름 옆 ☆ 아이콘으로 관리할 수 있어요.",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
