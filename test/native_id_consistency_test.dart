import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/ad_service.dart';
import 'package:knue_mate/club_event_alert_service.dart'
    show kClubEventCheckTask;
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
  late String androidManifest;

  setUpAll(() {
    appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
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

      final declared = RegExp(
        r'<string>([^<]+)</string>',
      ).allMatches(arrayMatch!.group(1)!).map((m) => m.group(1)!).toSet();

      expect(
        declared,
        equals(dartTaskIds),
        reason:
            'Info.plist에 선언 안 된 식별자를 register()하면 iOS가 그 자리에서 '
            'SIGABRT로 크래시합니다.',
      );
    });
  });

  group('AdMob 광고 단위 ID', () {
    // 콘솔에서 손으로 복사해 오는 값이라 틀려도 컴파일은 된다. 틀리면
    // 광고가 안 나가거나(수익 0) 남의 계정으로 나간다.
    //
    // 상수가 private이라 소스를 그대로 읽는다 — 이 파일이 이미 네이티브
    // 소스를 그렇게 읽고 있다.
    late String adService;
    late String interstitialService;

    setUpAll(() {
      adService = File('lib/ad_service.dart').readAsStringSync();
      interstitialService = File(
        'lib/interstitial_ad_service.dart',
      ).readAsStringSync();
    });

    String realId(String source, String name) {
      final m = RegExp("$name\\s*=\\s*'([^']*)'").firstMatch(source);
      expect(m, isNotNull, reason: '$name 상수를 못 찾았습니다.');
      return m!.group(1)!;
    }

    /// 앱 ID에서 뽑은 게시자 번호. 광고 단위도 같은 번호여야 한다.
    String publisherOf(String id) =>
        RegExp(r'ca-app-pub-(\d+)').firstMatch(id)!.group(1)!;

    test('앱 ID는 ~, 광고 단위 ID는 / 를 쓴다', () {
      // 둘을 바꿔 붙여넣는 실수가 가장 흔하다. 모양이 다르므로 잡을 수 있다.
      expect(
        RegExp(r'ca-app-pub-\d+~\d+').hasMatch(androidManifest),
        isTrue,
        reason: 'AndroidManifest.xml의 APPLICATION_ID가 앱 ID 모양이 아닙니다.',
      );
      expect(
        RegExp(r'ca-app-pub-\d+~\d+').hasMatch(infoPlist),
        isTrue,
        reason: 'Info.plist의 GADApplicationIdentifier가 앱 ID 모양이 아닙니다.',
      );

      for (final entry in {
        'ad_service._androidRealNativeId': realId(
          adService,
          '_androidRealNativeId',
        ),
        'ad_service._iosRealNativeId': realId(adService, '_iosRealNativeId'),
        'interstitial._androidRealId': realId(
          interstitialService,
          '_androidRealId',
        ),
        'interstitial._iosRealId': realId(interstitialService, '_iosRealId'),
      }.entries) {
        expect(
          RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(entry.value),
          isTrue,
          reason:
              '${entry.key}가 광고 단위 ID 모양이 아닙니다("${entry.value}"). '
              '앱 ID(~)를 잘못 붙여넣었거나 비어 있습니다 — 비어 있으면 '
              '릴리스 빌드에서 그 광고가 아예 안 나갑니다.',
        );
      }
    });

    test('광고 단위가 전부 우리 게시자 번호다', () {
      final publisher = publisherOf(
        RegExp(r'ca-app-pub-\d+~\d+').firstMatch(infoPlist)!.group(0)!,
      );
      for (final id in [
        realId(adService, '_androidRealNativeId'),
        realId(adService, '_iosRealNativeId'),
        realId(interstitialService, '_androidRealId'),
        realId(interstitialService, '_iosRealId'),
      ]) {
        expect(
          publisherOf(id),
          publisher,
          reason: '광고 단위 $id 의 게시자 번호가 앱 ID와 다릅니다.',
        );
      }
    });

    test('구글 테스트 단위를 실제 ID 자리에 두지 않았다', () {
      // 테스트 ID로 배포하면 광고는 나가는데 수익이 0이라, 한참 뒤에야 안다.
      const googleTestPublisher = '3940256099942544';
      for (final id in [
        realId(adService, '_androidRealNativeId'),
        realId(adService, '_iosRealNativeId'),
        realId(interstitialService, '_androidRealId'),
        realId(interstitialService, '_iosRealId'),
      ]) {
        expect(id.contains(googleTestPublisher), isFalse, reason: id);
      }
    });

    test('전면 광고와 네이티브 광고가 서로 다른 단위다', () {
      expect(
        {
          realId(adService, '_androidRealNativeId'),
          realId(adService, '_iosRealNativeId'),
          realId(interstitialService, '_androidRealId'),
          realId(interstitialService, '_iosRealId'),
        }.length,
        4,
        reason:
            '광고 단위 ID 네 개 중 겹치는 것이 있습니다 — 형식이 다른 단위를 '
            '같은 ID로 요청하면 노 필로 조용히 안 뜹니다.',
      );
    });
  });

  group('AdMob 네이티브 광고 팩토리 ID 일관성', () {
    final dartFactoryIds = {
      AdService.nativeAdFactoryId(false),
      AdService.nativeAdFactoryId(true),
    };

    test('iOS AppDelegate.swift의 factoryId가 Dart와 정확히 같다', () {
      final iosIds = RegExp(
        r'factoryId:\s*"([^"]+)"',
      ).allMatches(appDelegate).map((m) => m.group(1)!).toSet();

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
      final androidIds = RegExp(
        r'private val \w+ = "([^"]+)"',
      ).allMatches(mainActivity).map((m) => m.group(1)!).toSet();

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
