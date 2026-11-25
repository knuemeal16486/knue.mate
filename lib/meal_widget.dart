/// 식단 홈 위젯이 **스스로 끼니를 넘기도록** 한 주치 식단을 넣는다.
///
/// 예전엔 앱이 "오늘 점심"과 메뉴 글자 한 덩어리(`widget_title`·`widget_time`·
/// `widget_menu`)만 넣어서, 점심이 끝나도 앱을 열거나 백그라운드가 돌 때까지
/// 위젯이 그대로였다(iOS 백그라운드는 거의 안 돈다). 이제 두 식당의 오늘~7일 뒤
/// 식단과 끼니 끝나는 시각을 [kMealWeekJsonKey]에 넣고, 위젯이 지금 시각으로
/// 끼니를 고른다 — 버스 위젯이 시간표로 다음 차를 고르는 것과 같다.
///
/// 규칙은 [resolveMealWidget] 하나다. Swift(`ios/MealWidget/MealWidget.swift`
/// `resolveMealWidget`)·Kotlin(`MealWidgetProvider.resolve`)이 그대로 옮겨 쓴다 —
/// 여기를 바꾸면 거기도 바꾼다(test/meal_widget_test.dart의 표가 기준).
///
/// 끼니 끝나는 시각은 [mealTimeRangeFor]에서만 온다(JSON에 실어 보낸다) —
/// 위젯 쪽에 시간을 따로 적지 않는다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'constants.dart'
    show
        MealCache,
        MealSource,
        MealType,
        kIosMealWidgetKind,
        mealTimeRangeFor,
        widgetSource;

/// 위젯 저장소 키. Swift·Kotlin 문자열과 같아야 한다(native_id_consistency_test).
const kMealWeekJsonKey = 'meal_week_json';

/// 오늘부터 며칠치를 싣는지(오늘 포함). 일주일 넘게 앱을 안 열면 위젯이
/// "앱을 열면 식단을 불러옵니다"로 바뀐다.
const kMealWidgetDays = 8;

/// 하루치 메뉴가 없을 때·운영하지 않을 때·데이터가 없을 때 문구. 위젯 세 곳이 같다.
const kMealWidgetNoMenu = '등록된 메뉴가 없습니다.';
const kMealWidgetNoData = '앱을 한 번 열면\n식단을 불러옵니다.';
String mealWidgetClosedText(bool tomorrow) =>
    '${tomorrow ? '내일' : '오늘'}은 식당을 운영하지 않아요 🥺';

/// "yyyy-MM-dd".
String mealWidgetDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// 캐시에 담긴 식단(`{'meals': {...}}`)에서 한 끼니의 메뉴. 키가 영어·한국어로
/// 섞여 들어온다(학교 API는 breakfast…, 옛 Firestore 문서는 조식·중식·석식).
List<String> mealItemsOf(Map? meals, MealType type) {
  if (meals == null) return const [];
  final v = switch (type) {
    MealType.breakfast => meals['breakfast'] ?? meals['조식'] ?? meals['아침'],
    MealType.lunch => meals['lunch'] ?? meals['중식'] ?? meals['점심'],
    MealType.dinner => meals['dinner'] ?? meals['석식'] ?? meals['저녁'],
  };
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
  ];
}

/// "11:30 ~ 13:30" → "13:30".
String? _endOf(String? range) {
  if (range == null) return null;
  final parts = range.split('~');
  return parts.length == 2 ? parts[1].trim() : null;
}

/// 위젯에 넣을 JSON. 순수 함수.
///
/// ```json
/// {"v":1,"selected":"a","sources":[
///   {"id":"a","label":"기숙사 식당",
///    "meals":[{"key":"breakfast","label":"아침","end":"09:00"}, …],   // 운영하는 끼니만, 이른 순
///    "days":{"2026-11-25":{"breakfast":[…],"lunch":[…],"dinner":[…]},
///            "2026-11-29":{"closed":true}}}]}
/// ```
///
/// [cached]는 식당마다 날짜 → 캐시 값(`{'meals': {...}}`, 없으면 null).
/// 캐시가 없는 날은 싣지 않는다(위젯이 "앱을 열면 불러옵니다"). 메뉴가 하나도 없는
/// 토·일은 `closed`(운영 안 함), 메뉴가 없는 평일은 빈 목록(등록된 메뉴 없음).
String mealWidgetPayloadJson({
  required MealSource selected,
  required Map<MealSource, Map<DateTime, Map<String, dynamic>?>> cached,
}) {
  final sources = <Map<String, dynamic>>[];
  for (final s in MealSource.values) {
    final served = [
      for (final t in MealType.values)
        if (_endOf(mealTimeRangeFor(t, s)) != null) t,
    ];
    final days = <String, dynamic>{};
    final byDate = cached[s] ?? const {};
    final dates = byDate.keys.toList()..sort();
    for (final d in dates) {
      final entry = byDate[d];
      if (entry == null) continue;
      final raw = entry['meals'];
      final meals = raw is Map ? raw : null;
      final lists = {for (final t in served) t.stdKey: mealItemsOf(meals, t)};
      final empty = lists.values.every((l) => l.isEmpty);
      final weekend =
          d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      days[mealWidgetDayKey(d)] =
          empty && weekend ? {'closed': true} : lists;
    }
    sources.add({
      'id': s.name,
      'label': s.label,
      'meals': [
        for (final t in served)
          {
            'key': t.stdKey,
            'label': t.label,
            'end': _endOf(mealTimeRangeFor(t, s)),
          },
      ],
      'days': days,
    });
  }
  return jsonEncode({'v': 1, 'selected': selected.name, 'sources': sources});
}

/// 위젯이 지금 그릴 글. 옛 키(`widget_title`·`widget_time`·`widget_menu`)와 같은 모양이라
/// 위젯 화면 코드는 그대로 쓴다.
typedef MealWidgetText = ({String title, String time, String menu});

/// [payload]([mealWidgetPayloadJson])에서 [now]에 보여 줄 끼니. 순수 함수 — 위젯의 기준.
///
/// 끼니: **지금 파는(또는 오늘 아직 안 끝난) 첫 끼니 → 다 끝났으면 내일 첫 끼니**
/// (`widgetMealSlot`과 같다. 끝나는 분 00초까지는 그 끼니). [source]가 있으면
/// 그 식당, 없으면 `selected`. JSON이 깨졌으면 null(위젯은 옛 키로 그린다).
MealWidgetText? resolveMealWidget(String payload, DateTime now,
    {String? source}) {
  try {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final sources = (root['sources'] as List).cast<Map<String, dynamic>>();
    if (sources.isEmpty) return null;
    final want = source ?? root['selected'] as String?;
    final src = sources.firstWhere((s) => s['id'] == want,
        orElse: () => sources.first);
    final title = src['label'] as String? ?? '';
    final meals = (src['meals'] as List).cast<Map<String, dynamic>>();
    if (meals.isEmpty) {
      return (title: title, time: '', menu: kMealWidgetNoData);
    }
    Map<String, dynamic>? pick;
    var tomorrow = false;
    for (final m in meals) {
      final end = _at(now, m['end'] as String);
      if (end != null && !now.isAfter(end)) {
        pick = m;
        break;
      }
    }
    if (pick == null) {
      pick = meals.first;
      tomorrow = true;
    }
    final date = DateTime(now.year, now.month, now.day + (tomorrow ? 1 : 0));
    final time = '${tomorrow ? '내일' : '오늘'} ${pick['label']}';
    final day = (src['days'] as Map?)?[mealWidgetDayKey(date)];
    if (day is! Map) return (title: title, time: time, menu: kMealWidgetNoData);
    if (day['closed'] == true) {
      return (title: title, time: time, menu: mealWidgetClosedText(tomorrow));
    }
    final items = (day[pick['key']] as List?)?.cast<String>() ?? const [];
    return (
      title: title,
      time: time,
      menu: items.isEmpty
          ? kMealWidgetNoMenu
          : items.map((e) => '· $e').join('\n'),
    );
  } catch (_) {
    return null;
  }
}

/// [now]와 같은 날 "HH:mm".
DateTime? _at(DateTime now, String hhmm) {
  final p = hhmm.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return DateTime(now.year, now.month, now.day, h, m);
}

/// 기기에 받아 둔 두 식당의 오늘~[kMealWidgetDays]일 식단을 위젯에 넣는다.
/// 학교·Firestore에 새로 묻지 않는다 — 캐시만 읽는다. [redraw]면 위젯도 다시 그린다.
Future<void> pushMealWidgetWeek({bool redraw = true}) async {
  try {
    final now = DateTime.now();
    final cached = <MealSource, Map<DateTime, Map<String, dynamic>?>>{};
    for (final s in MealSource.values) {
      final byDate = <DateTime, Map<String, dynamic>?>{};
      for (var i = 0; i < kMealWidgetDays; i++) {
        final d = DateTime(now.year, now.month, now.day + i);
        byDate[d] = await MealCache.load(d, s);
      }
      cached[s] = byDate;
    }
    await HomeWidget.saveWidgetData<String>(
      kMealWeekJsonKey,
      mealWidgetPayloadJson(selected: widgetSource.value, cached: cached),
    );
    if (redraw) {
      await HomeWidget.updateWidget(
        name: 'MealWidgetProvider',
        androidName: 'MealWidgetProvider',
        qualifiedAndroidName: 'com.knue.knuemate.MealWidgetProvider',
        iOSName: kIosMealWidgetKind,
      );
    }
  } catch (e) {
    // 테스트·웹에서는 위젯 플러그인이 없다.
    debugPrint('pushMealWidgetWeek 건너뜀: $e');
  }
}
