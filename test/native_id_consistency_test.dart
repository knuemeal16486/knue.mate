import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/ad_service.dart';
import 'package:knue_mate/home_widgets.dart';
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

  group('공지·버스 위젯 식별자·키 일관성', () {
    String read(String p) => File(p).readAsStringSync();
    const iosDir = 'ios/MealWidget';

    test('iOS 버스 위젯 kind·키가 Dart와 같고 번들에 들어 있다', () {
      final bus = read('$iosDir/BusWidget.swift');
      expect(bus, contains('kind: String = "$kIosBusWidgetKind"'));
      expect(bus, contains('"$kWidgetBusTimetableKey"'));
      expect(read('$iosDir/MealWidget.swift'), contains('BusWidget()'));
    });

    test('iOS 버스 "곧 떠나는 차" 위젯 kind가 Dart와 같고 번들에 들어 있다', () {
      expect(read('$iosDir/BusWidget.swift'),
          contains('kind: String = "$kIosBusNextWidgetKind"'));
      expect(read('$iosDir/MealWidget.swift'), contains('BusNextWidget()'));
    });

    test('iOS 공지 위젯 kind·키가 Dart와 같고 번들에 들어 있다', () {
      final notice = read('$iosDir/NoticeWidget.swift');
      expect(notice, contains('kind: String = "$kIosNoticeWidgetKind"'));
      for (final key in [
        kWidgetNoticeRowsKey,
        kWidgetNoticeBoardsKey,
        kWidgetNoticeFeedBaseKey,
        kWidgetNoticeDirectKey,
      ]) {
        expect(notice, contains('"$key"'), reason: key);
      }
      // 수집 파일 주소는 https일 때만 받는다(학교·아무 주소로 가지 않게).
      expect(notice, contains('hasPrefix("https://")'));
      expect(read('$iosDir/MealWidget.swift'), contains('NoticeWidget()'));
    });

    // home_widget 0.8.1(iOS)은 쿼리에 homeWidget이 있는 URL만 Dart로 넘긴다
    // (HomeWidgetPlugin.isWidgetUrl). 없으면 위젯을 눌러도 탭 이동·공지 열기가
    // 조용히 안 된다.
    test('iOS 위젯 URL에는 모두 homeWidget 쿼리가 있다', () {
      for (final f in Directory(iosDir).listSync().whereType<File>()) {
        if (!f.path.endsWith('.swift')) continue;
        final urls = RegExp(r'"(knuemate://[^"]*)"')
            .allMatches(f.readAsStringSync())
            .map((m) => m.group(1)!);
        for (final u in urls) {
          expect(u, contains('homeWidget'), reason: '${f.path}: $u');
        }
      }
    });

    const ktDir = 'android/app/src/main/kotlin/com/knue/knuemate';

    test('Android 버스 위젯이 Manifest에 있고 키가 Dart와 같다', () {
      expect(androidManifest, contains('android:name=".BusWidgetProvider"'));
      expect(kAndroidBusWidget, 'com.knue.knuemate.BusWidgetProvider');
      expect(read('$ktDir/BusWidgetProvider.kt'),
          contains('"$kWidgetBusTimetableKey"'));
    });

    test('Android 버스 "곧 떠나는 차" 위젯이 Manifest에 있다', () {
      expect(androidManifest, contains('android:name=".BusNextWidgetProvider"'));
      expect(androidManifest, contains('@xml/bus_next_widget_info'));
      expect(kAndroidBusNextWidget, 'com.knue.knuemate.BusNextWidgetProvider');
      expect(read('$ktDir/BusNextWidgetProvider.kt'),
          contains('class BusNextWidgetProvider : BusWidgetProvider()'));
    });

    // 노선 막대 색 — iOS kBusRouteColorIndex와 Kotlin ROUTE_COLOR_INDEX가 같아야 한다.
    test('버스 노선 색 순서가 iOS·Android에서 같다', () {
      final swift = RegExp(r'kBusRouteColorIndex = \[([0-9, ]+)\]')
          .firstMatch(read('$iosDir/BusWidget.swift'))?[1];
      final kotlin = RegExp(r'ROUTE_COLOR_INDEX = intArrayOf\(([0-9, ]+)\)')
          .firstMatch(read('$ktDir/BusWidgetProvider.kt'))?[1];
      expect(swift, isNotNull);
      expect(kotlin?.replaceAll(' ', ''), swift?.replaceAll(' ', ''));
    });

    test('Android 공지 위젯이 Manifest에 있고 키가 Dart와 같다', () {
      expect(androidManifest, contains('android:name=".NoticeWidgetProvider"'));
      expect(kAndroidNoticeWidget, 'com.knue.knuemate.NoticeWidgetProvider');
      expect(read('$ktDir/NoticeWidgetProvider.kt'),
          contains('"$kWidgetNoticeRowsKey"'));
    });

    // 게시판 색은 Swift·Kotlin에 따로 적혀 있다 — 같은 게시판이 두 기기에서
    // 다른 색이면 안 되므로 (라이트, 다크) 쌍 목록이 같아야 한다.
    test('공지 위젯 게시판 색이 iOS·Android에서 같다', () {
      List<String> pairs(String src, RegExp re) =>
          re.allMatches(src).map((m) => '${m[1]}/${m[2]}'.toUpperCase()).toList();
      final swift = pairs(read('$iosDir/NoticeWidget.swift'),
          RegExp(r'\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)'));
      final kotlin = pairs(read('$ktDir/NoticeWidgetProvider.kt'),
          RegExp(r'0x([0-9A-Fa-f]{6}) to 0x([0-9A-Fa-f]{6})'));
      expect(swift.length, kNoticeBoardColorCount);
      expect(kotlin, swift);
      expect(swift.toSet().length, swift.length, reason: '색이 겹친다');
    });

    test('공지 위젯 최대 줄 수가 Dart·iOS·Android에서 같다', () {
      expect(read('$iosDir/NoticeWidget.swift'),
          contains('let kNoticeWidgetMaxRows = $kNoticeWidgetMaxRows'));
      final layout =
          read('android/app/src/main/res/layout/notice_widget_layout.xml');
      expect(RegExp(r'@\+id/notice_row_\d+').allMatches(layout).length,
          kNoticeWidgetMaxRows);
      expect(read('$ktDir/NoticeWidgetProvider.kt'),
          contains('"$kWidgetNoticeBoardsKey"'));
    });

    test('위젯 강조색 키를 iOS·Android가 Dart와 같은 이름으로 읽는다', () {
      for (final key in [kWidgetAccentLightKey, kWidgetAccentDarkKey]) {
        expect(read('$iosDir/WidgetShared.swift'), contains('"$key"'));
        expect(read('$ktDir/WidgetTheme.kt'), contains('"$key"'));
      }
    });
  });
}
