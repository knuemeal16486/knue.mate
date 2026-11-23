import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';

/// 사용 통계(Firebase Analytics).
///
/// 세는 건 **어느 탭을 봤는지**뿐이다 — "식단만 보고 끈다"가 감인지 숫자인지
/// 알려고 넣었다(2026-11-15). 이름·학번·위치 같은 건 보내지 않는다. 여기에
/// 이벤트를 더하면 스토어의 데이터 수집 고지와 개인정보처리방침도 같이 본다.
///
/// 통계는 앱 기능이 아니므로 어떤 실패도 화면으로 올라가면 안 된다 — 전부
/// 삼킨다. Firebase가 안 떠 있으면(테스트, 초기화 시간 초과) 아무 일도 안 한다.
class AppAnalytics {
  AppAnalytics._();

  static bool get _ready => Firebase.apps.isNotEmpty;

  /// 앱이 켜질 때 한 번. 개발 빌드는 세지 않는다 — 개발자 한 명이 하루에
  /// 여는 횟수가 학생 수십 명 몫이라 숫자가 흐려진다. 설정이 기기에 남으므로
  /// 같은 기기에 배포 빌드를 깔면 여기서 다시 켜진다.
  static Future<void> initialize() async {
    if (!_ready) return;
    try {
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(!kDebugMode);
    } catch (e) {
      debugPrint('Analytics 초기화 건너뜀: $e');
    }
  }

  /// 하단 탭 하나를 보기 시작했다. 탭을 눌러 옮겼을 때, 앱을 처음 켰을 때,
  /// 백그라운드에서 돌아왔을 때 부른다(돌아올 때는 탭을 누르지 않으므로
  /// 따로 안 세면 "식단 탭을 켜 둔 채 매일 다시 여는 사람"이 빠진다).
  static void logTab(AppTab tab) {
    if (!_ready) return;
    try {
      FirebaseAnalytics.instance
          .logScreenView(screenName: analyticsScreenName(tab))
          .catchError((Object e) => debugPrint('Analytics 기록 실패: $e'));
    } catch (e) {
      debugPrint('Analytics 기록 실패: $e');
    }
  }
}

/// 통계에 찍히는 화면 이름. 탭의 한글 이름(`label`)은 바꿀 수 있어도 이 값은
/// 바꾸지 않는다 — 바꾸면 그날부터 다른 화면으로 집계돼 추세가 끊긴다.
String analyticsScreenName(AppTab tab) {
  switch (tab) {
    case AppTab.home:
      return 'tab_home';
    case AppTab.meal:
      return 'tab_meal';
    case AppTab.bus:
      return 'tab_bus';
    case AppTab.run:
      return 'tab_run';
    case AppTab.map:
      return 'tab_map';
    case AppTab.settings:
      return 'tab_settings';
  }
}
