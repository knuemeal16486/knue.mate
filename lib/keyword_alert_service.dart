import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'constants.dart';
import 'notice_model.dart';
import 'notice_service.dart';

const String kNoticeCheckTask = 'knue_notice_check_task';

/// scheduled 모드에서 다음 지정 시각까지 쌓아두는 공지 제목들.
const String _kPendingTitlesKey = 'notice_pending_digest_titles';

/// scheduled 모드에서 마지막으로 모아 보낸 시각(ISO8601). 하루 중 어느
/// 지정 시각까지 이미 보냈는지 판단하는 기준.
const String _kLastDigestSentAtKey = 'notice_last_digest_sent_at';

/// 온디바이스 키워드 알림 (MoA notification_service.dart 로직 이식, Hive 제거)
class KeywordAlertService {
  /// 새로 알릴 공지 선별. 순수 함수 — 테스트 대상.
  /// 키워드가 비어 있으면 관심 게시판의 새 글 전부가 대상.
  static List<Notice> filterNewMatches({
    required List<Notice> notices,
    required List<String> keywords,
    required List<String> favBoards,
    required Set<String> notifiedIds,
  }) {
    final result = <Notice>[];
    for (final notice in notices.take(50)) {
      if (notifiedIds.contains(notice.id.toString())) continue;
      final inFav = favBoards.isEmpty || favBoards.contains(notice.category);
      if (!inFav) continue;
      final matches = keywords.isEmpty ||
          keywords.any(
              (kw) => notice.title.toLowerCase().contains(kw.toLowerCase()));
      if (matches) result.add(notice);
    }
    return result;
  }

  /// scheduled 모드에서 지금 모아둔 알림을 내보낼 때가 됐는지. 순수 함수 —
  /// 테스트 대상.
  ///
  /// 정확히 지정 시각(예: 9:00:00)에 맞춰 울리는 게 아니라 — 백그라운드
  /// 점검이 애초에 정확한 시각에 도는 걸 보장 못 한다(특히 iOS는 앱이
  /// 요청한 주기를 그대로 지키지 않고 시스템이 알아서 판단한다) — "오늘
  /// 지정 시각 중 이미 지난 것 중 가장 최근 것"을 계산해서, 마지막으로
  /// 보낸 시각이 그보다 이전이면 지금 보낸다. 점검이 몇 분~몇 시간 늦게
  /// 돌아도 그 다음 점검에서 놓치지 않고 한 번은 보낸다.
  static bool isDigestDue({
    required DateTime now,
    required List<int> targetHours,
    required DateTime? lastDigestSentAt,
  }) {
    DateTime? mostRecentCrossing;
    for (final h in targetHours) {
      if (h < 0 || h > 23) continue;
      final t = DateTime(now.year, now.month, now.day, h);
      if (!t.isAfter(now)) {
        if (mostRecentCrossing == null || t.isAfter(mostRecentCrossing)) {
          mostRecentCrossing = t;
        }
      }
    }
    if (mostRecentCrossing == null) return false; // 오늘 지정 시각이 아직 안 지남
    if (lastDigestSentAt == null) return true;
    return lastDigestSentAt.isBefore(mostRecentCrossing);
  }

  /// 백그라운드 task 본체. 디버그 버튼에서도 직접 호출 가능.
  static Future<void> checkAndNotify() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(PreferencesService.keyNoticeAlarm) ?? true)) return;

    final notices =
        await KnueScraper().fetchAllNotices(forceRefresh: true);
    if (notices.isEmpty) return;

    final keywords =
        prefs.getStringList(PreferencesService.keyNoticeKeywords) ?? [];
    final favBoards =
        prefs.getStringList(PreferencesService.keyFavBoards) ?? [];
    final notified = prefs.getStringList('notified_ids') ?? [];

    final newItems = filterNewMatches(
      notices: notices,
      keywords: keywords,
      favBoards: favBoards,
      notifiedIds: notified.toSet(),
    );

    // 스캔한 상위 50개는 전부 알림 완료로 기록 (반복 알림 방지)
    final allScanned = notices.take(50).map((n) => n.id.toString());
    final merged = {...notified, ...allScanned}.toList();
    final trimmed = merged.length > 200
        ? merged.sublist(merged.length - 200)
        : merged;
    await prefs.setStringList('notified_ids', trimmed);

    // 백그라운드 isolate라 PreferencesService의 ValueNotifier는 못 믿는다
    // (메인 isolate에서 로드된 값이라 여기선 비어 있을 수 있다) — 항상
    // SharedPreferences에서 직접 읽는다. 나머지 코드도 이미 이 방식.
    final modeRaw = prefs.getString(PreferencesService.keyNoticeAlertMode);
    final scheduled = modeRaw == NoticeAlertMode.scheduled.name;

    if (!scheduled) {
      // scheduled 모드였다가 방금 instant로 바꿨을 수 있다 — 그때 쌓여 있던
      // 항목을 여기서 안 비우면, instant 모드는 이 목록을 아예 안 쳐다보니
      // 영영 안 보내지고 다음에 scheduled로 되돌릴 때까지 방치된다.
      final strandedPending = prefs.getStringList(_kPendingTitlesKey) ?? [];
      final toSend = [
        ...strandedPending,
        ...newItems.map((n) => '[${n.category}] ${n.title}'),
      ];
      if (strandedPending.isNotEmpty) {
        await prefs.setStringList(_kPendingTitlesKey, []);
      }
      if (toSend.isEmpty) return;
      await _sendDigest(toSend);
      return;
    }

    // scheduled 모드 — 지정 시각이 아니면 쌓아만 두고 알림은 안 보낸다.
    final pending = prefs.getStringList(_kPendingTitlesKey) ?? [];
    if (newItems.isNotEmpty) {
      pending.addAll(newItems.map((n) => '[${n.category}] ${n.title}'));
      await prefs.setStringList(_kPendingTitlesKey, pending);
    }
    if (pending.isEmpty) return;

    final hours = (prefs.getStringList(PreferencesService.keyNoticeAlertHours) ??
            ['9', '18'])
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toList();
    final lastSentRaw = prefs.getString(_kLastDigestSentAtKey);
    final lastSent = lastSentRaw != null ? DateTime.tryParse(lastSentRaw) : null;

    if (!isDigestDue(
        now: DateTime.now(), targetHours: hours, lastDigestSentAt: lastSent)) {
      return;
    }

    await _sendDigest(pending);
    await prefs.setStringList(_kPendingTitlesKey, []);
    await prefs.setString(
        _kLastDigestSentAtKey, DateTime.now().toIso8601String());
  }

  /// "[게시판] 제목" 형태로 미리 포맷된 목록을 알림 1건으로 내보낸다.
  /// instant 모드의 방금 찾은 새 글, scheduled 모드의 그동안 쌓인 목록 둘 다 이걸 쓴다.
  static Future<void> _sendDigest(List<String> formattedTitles) async {
    if (formattedTitles.isEmpty) return;
    final ns = NotificationService();
    await ns.init();
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (formattedTitles.length == 1) {
      await ns.showNotification(id, '새 공지사항', formattedTitles.first);
    } else {
      await ns.showNotification(
        id,
        '새 공지사항 ${formattedTitles.length}건',
        '${formattedTitles.first} 외 ${formattedTitles.length - 1}건',
      );
    }
  }

  /// 설정 상태에 맞춰 periodic task 등록/해제
  static Future<void> syncRegistration() async {
    if (kIsWeb) return;
    try {
      // 키워드가 비어 있어도 filterNewMatches는 "즐겨찾기 게시판 전체 알림"으로
      // 동작하도록 설계돼 있다(문서화된 의도, notice_screen.dart의 안내 문구도
      // 같은 내용). 예전엔 여기서 keywords.isNotEmpty까지 같이 요구해서, 키워드를
      // 전부 지우면 그 의도와 반대로 백그라운드 작업 자체가 등록조차 안 돼
      // 알림이 완전히 끊겼다 — 스위치는 켜져 있는데 아무 일도 안 일어나는 상태.
      final on = PreferencesService.noticeAlarmOn.value;
      if (on) {
        await Workmanager().registerPeriodicTask(
          kNoticeCheckTask,
          kNoticeCheckTask,
          frequency: const Duration(hours: 2),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName(kNoticeCheckTask);
      }
    } catch (e) {
      debugPrint('keyword alert registration error: $e');
    }
  }
}
