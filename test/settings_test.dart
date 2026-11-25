import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/widget_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 탭(2026-11-25 개선).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 예전 "설정 초기화"는 prefs.clear()라 개인 일정·D-day·캐시·학교 요청 간격까지 지웠다.
  test('resetSettings는 설정 키만 지우고 개인 일정·D-day·캐시는 남긴다', () async {
    SharedPreferences.setMockInitialValues({
      PreferencesService.keyThemeColor: 0xFF00FF00,
      PreferencesService.keyWidgetTrans: 0.5,
      PreferencesService.keyWidgetBgStyle: 1,
      PreferencesService.keyFavBoards: ['장학'],
      PreferencesService.keyRainbowMode: true,
      PreferencesService.keyPersonalEvents: '[{"title":"시험"}]',
      PreferencesService.keyDdayItems: '[{"title":"종강"}]',
      'mealCache_2026-11-25_a': '{"meals":{}}',
      'notified_ids': ['1'],
    });
    widgetTransparency.value = 0.5;
    widgetBgStyle.value = 1;
    rainbowModeNotifier.value = true;
    await PreferencesService.resetSettings();
    final prefs = await SharedPreferences.getInstance();
    for (final k in PreferencesService.kSettingKeys) {
      expect(prefs.containsKey(k), isFalse, reason: k);
    }
    expect(prefs.getString(PreferencesService.keyPersonalEvents), '[{"title":"시험"}]');
    expect(prefs.getString(PreferencesService.keyDdayItems), '[{"title":"종강"}]');
    expect(prefs.containsKey('mealCache_2026-11-25_a'), isTrue);
    expect(prefs.getStringList('notified_ids'), ['1']);
    expect(widgetTransparency.value, 0.0);
    expect(widgetBgStyle.value, 0);
    expect(rainbowModeNotifier.value, isFalse);
    expect(PreferencesService.favoriteBoards.value, ['대학소식', '학사공지']);
  });

  testWidgets('홈 위젯 화면: 미리보기 하나와 위젯 설정이 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WidgetSettingsScreen()));
    expect(find.byKey(const Key('widget-preview')), findsOneWidget);
    for (final t in ['표시할 식당', '위젯 배경 테마', '배경 투명도', '위젯 데이터 즉시 업데이트']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('기본 위젯 테스트'), findsNothing);
    expect(find.text('위젯 바탕'), findsNothing); // Android는 투명도 슬라이더
  });

  // iOS는 위젯 뒤 배경화면이 비치지 않아 투명도가 뿌옇게만 됐다 — 바탕 스타일로 대신한다.
  testWidgets('홈 위젯 화면(iOS): 투명도 슬라이더 대신 위젯 바탕 3칸', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const MaterialApp(home: WidgetSettingsScreen()));
      expect(find.text('배경 투명도'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('위젯 바탕'), findsOneWidget);
      for (final t in ['기본', '테마색', '회색']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // SettingsPage는 광고 카드·Firebase를 물고 있어 위젯 테스트로 띄우지 않고 소스로 본다.
  test('설정 화면: 홈 위젯 줄·초기화 확인 창, 예전 미리보기·테스트 버튼은 없다', () {
    final src = File('lib/settings_screen.dart').readAsStringSync();
    expect(src, contains('const WidgetSettingsScreen()'));
    expect(src, contains('_confirmReset(context)'));
    expect(src, isNot(contains('prefs.clear()')));
    expect(src, isNot(contains('"위젯 미리보기"')));
    expect(src, isNot(contains('label: const Text("기본 위젯 테스트")')));
    expect(src, contains('applicationName: "KNUE Mate"'));
  });
}
