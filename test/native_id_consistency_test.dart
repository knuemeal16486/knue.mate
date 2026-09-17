import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/ad_service.dart';
import 'package:knue_mate/club_event_alert_service.dart' show kClubEventCheckTask;
import 'package:knue_mate/keyword_alert_service.dart' show kNoticeCheckTask;

/// iOS Info.plist / AppDelegate.swift / Android MainActivity.kt / Dart 쪽에
/// 각각 따로 타이핑된 "서로 같아야 하는" 문자열 식별자들이 실제로 일치하는지
/// 검증한다.
///
/// 이 테스트가 왜 있는지: AppDelegate.swift가 BGTaskScheduler 식별자를 두
/// 함수로 중복 등록해 앱을 켤 때마다 크래시하는 버그가 실제로 배포됐었다
/// (1.4.0/42, 실기기 크래시 리포트로 확인). flutter analyze도 컴파일러도
/// "여러 파일에 흩어진 문자열 상수가 서로 맞아야 한다"는 종류의 실수는
/// 잡아주지 못한다 — 이 테스트가 그 안전망이다.
void main() {
  late String appDelegate;
  late String infoPlist;
  late String mainActivity;

  setUpAll(() {
    appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    mainActivity = File(
      'android/app/src/main/kotlin/com/knue/knuemate/MainActivity.kt',
    ).readAsStringSync();
  });

  group('BGTaskScheduler 식별자 일관성', () {
    // lib/main.dart가 Workmanager().registerPeriodicTask()에 직접 리터럴로
    // 넘기는 식별자 — 상수로 뽑혀있지 않아 여기 그대로 적어둔다.
    const mealWidgetTaskId = 'meal_widget_update_task';
    const widgetUpdateTaskId = 'widget_update';

    final dartTaskIds = {
      mealWidgetTaskId,
      widgetUpdateTaskId,
      kNoticeCheckTask,
      kClubEventCheckTask,
    };

    test('AppDelegate.swift가 register()한 식별자 집합이 Dart 쪽과 정확히 같다', () {
      final registered = RegExp(
        r'registerPeriodicTask\(withIdentifier:\s*"([^"]+)"',
      ).allMatches(appDelegate).map((m) => m.group(1)!).toSet();

      expect(
        registered,
        equals(dartTaskIds),
        reason:
            'AppDelegate.swift의 registerPeriodicTask(withIdentifier:) 목록과 '
            'Dart 쪽에서 실제로 쓰는 식별자 집합이 어긋났습니다. 한쪽만 '
            '고치면 iOS에서 등록 안 된 식별자를 submit()하다 조용히 실패하거나, '
            '같은 식별자를 두 번 register()해서 앱이 시작 시 SIGABRT로 '
            '크래시할 수 있습니다.',
      );
    });

    test('Info.plist의 BGTaskSchedulerPermittedIdentifiers도 정확히 같다', () {
      final arrayMatch = RegExp(
        r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(infoPlist);
      expect(arrayMatch, isNotNull, reason: 'Info.plist에서 배열을 못 찾았습니다.');

      final declared = RegExp(r'<string>([^<]+)</string>')
          .allMatches(arrayMatch!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        declared,
        equals(dartTaskIds),
        reason:
            'Info.plist에 선언 안 된 식별자를 register()하면 iOS가 그 자리에서 '
            'SIGABRT로 크래시합니다.',
      );
    });
  });

  group('AdMob 네이티브 광고 팩토리 ID 일관성', () {
    final dartFactoryIds = {
      AdService.nativeAdFactoryId(false),
      AdService.nativeAdFactoryId(true),
    };

    test('iOS AppDelegate.swift의 factoryId가 Dart와 정확히 같다', () {
      final iosIds = RegExp(r'factoryId:\s*"([^"]+)"')
          .allMatches(appDelegate)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        iosIds,
        equals(dartFactoryIds),
        reason:
            'iOS의 factoryId 문자열이 lib/ad_service.dart의 '
            'nativeAdFactoryId()와 어긋났습니다 — 어긋나면 NativeAd(...)가 '
            '그 factoryId를 못 찾아 광고가 크래시 없이 조용히 항상 안 뜹니다.',
      );
    });

    test('Android MainActivity.kt의 factoryId가 Dart와 정확히 같다', () {
      final androidIds = RegExp(r'private val \w+ = "([^"]+)"')
          .allMatches(mainActivity)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        androidIds,
        equals(dartFactoryIds),
        reason:
            'Android의 factoryId 문자열이 lib/ad_service.dart의 '
            'nativeAdFactoryId()와 어긋났습니다.',
      );
    });
  });
}
