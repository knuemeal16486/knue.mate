import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/analytics.dart';
import 'package:knue_mate/constants.dart';

void main() {
  test('탭마다 화면 이름이 다르고 Analytics 이름 규칙을 지킨다', () {
    final names = AppTab.values.map(analyticsScreenName).toList();
    expect(names.toSet().length, AppTab.values.length);
    // 영문자로 시작, 영문자·숫자·밑줄만, 40자 이하.
    final valid = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
    for (final name in names) {
      expect(valid.hasMatch(name), isTrue, reason: name);
    }
  });

  test('화면 이름은 고정이다 — 바꾸면 집계가 끊긴다', () {
    expect(analyticsScreenName(AppTab.home), 'tab_home');
    expect(analyticsScreenName(AppTab.meal), 'tab_meal');
    expect(analyticsScreenName(AppTab.bus), 'tab_bus');
    expect(analyticsScreenName(AppTab.run), 'tab_run');
    expect(analyticsScreenName(AppTab.map), 'tab_map');
    expect(analyticsScreenName(AppTab.settings), 'tab_settings');
  });

  test('Firebase가 안 떠 있으면 조용히 넘어간다', () async {
    await AppAnalytics.initialize();
    AppAnalytics.logTab(AppTab.meal);
  });
}
