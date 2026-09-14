import 'dart:convert' show JsonEncoder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/club_event_model.dart';
import 'package:knue_mate/club_events_screen.dart';

void main() {
  testWidgets('ClubEventsScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: ClubEventsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    // 화면이 학과 행사까지 담게 되면서 제목이 "동아리 공연·행사" → "공연·행사"로
    // 바뀌었는데 이 테스트가 옛 문구를 그대로 찾고 있었다.
    expect(find.text("공연·행사"), findsOneWidget);
  });

  testWidgets('진행중이 위, 종류 딱지가 붙는다', (tester) async {
    // 캐시를 심어 두면 화면이 Firestore를 기다리지 않고 그걸 먼저 그린다.
    final now = DateTime.now();
    ClubEvent make(String title, DateTime start, DateTime? end,
            ClubEventCategory c) =>
        ClubEvent(
          id: title,
          title: title,
          clubName: '테스트',
          startDate: start,
          endDate: end,
          location: '대강당',
          description: '',
          category: c,
          posterUrl: null,
          externalLink: null,
          isFeatured: false,
          createdAt: now,
        );
    final events = [
      make('다음주공연', now.add(const Duration(days: 7)), null,
          ClubEventCategory.club),
      make('지금축제', now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)), ClubEventCategory.school),
      make('작년버스킹', now.subtract(const Duration(days: 400)),
          now.subtract(const Duration(days: 399)), ClubEventCategory.busking),
    ];
    SharedPreferences.setMockInitialValues({
      'clubEventCache': jsonEncode(events.map((e) => e.toJson()).toList()),
    });
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: ClubEventsScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('지금 열리는 중'), findsOneWidget);
    expect(find.text('지금축제'), findsOneWidget);
    expect(find.text('학교 행사'), findsOneWidget, reason: '종류 딱지가 붙어야 한다');
    expect(find.text('동아리 공연'), findsOneWidget);

    // 끝난 행사는 걸러진다.
    expect(find.text('작년버스킹'), findsNothing);
    expect(find.text('버스킹'), findsNothing);

    // 진행중 구획이 예정 구획보다 위에 있다.
    final ongoingY = tester.getTopLeft(find.text('지금 열리는 중')).dy;
    final laterY = tester.getTopLeft(find.text('이후 예정')).dy;
    expect(ongoingY, lessThan(laterY));

    await tester.pump(const Duration(seconds: 5));
  });
}

// 캐시는 JSON 문자열로 저장된다 (ClubEventCache).
String jsonEncode(Object? o) => const JsonEncoder().convert(o);
