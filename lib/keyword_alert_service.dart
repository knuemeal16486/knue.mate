import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'constants.dart';
import 'notice_model.dart';
import 'notice_service.dart';

const String kNoticeCheckTask = 'knue_notice_check_task';

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

    if (newItems.isEmpty) return;

    final ns = NotificationService();
    await ns.init();
    if (newItems.length == 1) {
      await ns.showNotification(
        newItems[0].id,
        '[${newItems[0].category}] 새 공지사항',
        newItems[0].title,
      );
    } else {
      await ns.showNotification(
        newItems[0].id,
        '새 공지사항 ${newItems.length}건',
        '[${newItems[0].category}] ${newItems[0].title} 외 ${newItems.length - 1}건',
      );
    }
  }

  /// 설정 상태에 맞춰 periodic task 등록/해제
  static Future<void> syncRegistration() async {
    if (kIsWeb) return;
    try {
      final on = PreferencesService.noticeAlarmOn.value &&
          PreferencesService.noticeKeywords.value.isNotEmpty;
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
