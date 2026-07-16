import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';

const String kClubEventCheckTask = 'knue_club_event_check_task';

/// 녹출(featured) 신규 행사 로컬 알림. keyword_alert_service.dart 패턴 이식.
class ClubEventAlertService {
  static const _notifiedKey = 'club_notified_ids';
  static const _seededKey = 'club_alert_seeded';

  /// 녹출이면서 아직 안 알린 행사 선별. 순수 함수 — 테스트 대상.
  static List<ClubEvent> filterNewFeatured({
    required List<ClubEvent> events,
    required Set<String> notifiedIds,
  }) {
    return events
        .where((e) => e.isFeatured && !notifiedIds.contains(e.id))
        .toList();
  }

  /// 백그라운드 task 본체.
  ///
  /// 최초 실행(시딩) 처리: syncRegistration()이 앱 시작 시 항상 등록되므로,
  /// 이 기능이 배포된 직후 첫 폴링 시점엔 `club_notified_ids`가 비어 있다.
  /// 시딩 없이 바로 diff를 돌리면 그 시점에 이미 녹출로 등록된 모든 행사가
  /// "신규"로 오인되어 전 사용자에게 알림 폭탄이 발송된다. 이를 막기 위해
  /// `club_alert_seeded` 플래그로 최초 1회는 현재 녹출 목록을 조용히
  /// notifiedIds에 기록만 하고 알림은 보내지 않는다. 이후 폴링부터는 기존
  /// diff+notify 로직이 정상 동작한다.
  static Future<void> checkAndNotify() async {
    final events = await ClubEventService.fetchAll(forceRefresh: true);
    if (events.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final notified = prefs.getStringList(_notifiedKey) ?? [];

    final seeded = prefs.getBool(_seededKey) ?? false;
    if (!seeded) {
      final featuredIds = events.where((e) => e.isFeatured).map((e) => e.id);
      final merged = {...notified, ...featuredIds}.toList();
      final trimmed =
          merged.length > 200 ? merged.sublist(merged.length - 200) : merged;
      await prefs.setStringList(_notifiedKey, trimmed);
      await prefs.setBool(_seededKey, true);
      return;
    }

    final newItems = filterNewFeatured(
      events: events,
      notifiedIds: notified.toSet(),
    );

    // 스캔한 모든 녹출 항목을 알림 완료로 기록 (반복 알림 방지)
    final featuredIds = events.where((e) => e.isFeatured).map((e) => e.id);
    final merged = {...notified, ...featuredIds}.toList();
    final trimmed =
        merged.length > 200 ? merged.sublist(merged.length - 200) : merged;
    await prefs.setStringList(_notifiedKey, trimmed);

    if (newItems.isEmpty) return;

    final ns = NotificationService();
    await ns.init();
    if (newItems.length == 1) {
      await ns.showNotification(
        newItems[0].id.hashCode,
        '[${newItems[0].clubName}] 새 공연·행사',
        newItems[0].title,
      );
    } else {
      await ns.showNotification(
        newItems[0].id.hashCode,
        '새 공연·행사 ${newItems.length}건',
        '[${newItems[0].clubName}] ${newItems[0].title} 외 ${newItems.length - 1}건',
      );
    }
  }

  /// periodic task 등록 (앱 시작 시 항상 등록 — 녹출 행사는 관리자가 언제든 올릴 수 있음).
  static Future<void> syncRegistration() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerPeriodicTask(
        kClubEventCheckTask,
        kClubEventCheckTask,
        frequency: const Duration(hours: 2),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('club event alert registration error: $e');
    }
  }
}
