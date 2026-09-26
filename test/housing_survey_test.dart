import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_detail_sheet.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:knue_mate/housing_survey.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 지도에 뜨는 이름: 에셋 이름 위에 개발자 모드에서 고친 이름(2026-09-27
/// Firestore `housing_building_overrides`에서 확인한 것)을 얹는다.
Map<String, String> mapNames() {
  final traced = jsonDecode(File('assets/housing/campus_traced.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final b in traced['buildings'] as List)
      if ((b as Map<String, dynamic>)['name'] is String) b['id'] as String: b['name'] as String,
    '4311331030100490011000001': '행운빌',
    '4371039030100490009000001': '가온빌',
    '4371039030100460021000001': '청람드림빌 D',
    'custom_1790344058946': '디저트 39',
  };
}

void main() {
  jeonseTests();
  allReportsTests();

  test('시세 조사의 건물 이름은 모두 지도에 있다', () {
    final names = mapNames();
    final matched = housingSurveyReports(names);
    final missing = <String>{
      for (final e in kHousingSurvey)
        for (final n in e.names)
          if (!names.values.any((v) => v.replaceAll(' ', '') == n.replaceAll(' ', ''))) n,
    };
    expect(missing, isEmpty);
    // 이름 하나가 엉뚱한 건물 여럿에 붙지 않는다(태암수정은 동마다 한 채).
    for (final rs in matched.values) {
      expect(rs.every((r) => r.survey), isTrue);
    }
    expect(matched.length, 28); // 24채(에셋 이름) + 4채(개발자 모드에서 붙인 이름)
  });

  test('띄어쓰기는 무시하고, 동을 안 가린 시세는 모든 동에 붙는다', () {
    final r = housingSurveyReports(
      {'a': '디저트39', 'b': '태암수정아파트 101동', 'c': '태암수정아파트 102동'},
      survey: const [
        HousingSurveyEntry(['디저트 39'], 300, 38),
        HousingSurveyEntry(['태암수정아파트 101동', '태암수정아파트 102동'], 300, 40),
      ],
    );
    expect(r.keys, containsAll(['a', 'b', 'c']));
    expect(r['b']!.single.monthlyRent, 40);
  });

  test('학생 제보와 섞여 평균에 반영되고, 출처는 따로 센다', () {
    final student = HousingReport(
      buildingId: 'x',
      deposit: 300,
      monthlyRent: 40,
      roomType: HousingRoomType.oneRoom,
      features: const ['풀옵션'],
      reportedAt: DateTime(2026, 9, 1),
    );
    final s = summarizeWithSurvey(
      {'x': [student]},
      {'x': '가온빌', 'y': '행운빌'},
      survey: const [
        HousingSurveyEntry(['가온빌'], 300, 30),
        HousingSurveyEntry(['가온빌'], 300, 32),
        HousingSurveyEntry(['행운빌'], 200, 60, roomType: HousingRoomType.twoRoom),
      ],
    );
    final x = s['x']!;
    expect(x.reportCount, 3);
    expect(x.surveyCount, 2);
    expect(x.sourceLabel, '제보 1건 · 시세 조사 2건');
    expect(x.roomPricingMap[HousingRoomType.oneRoom]?.monthlyRent, 34); // 30·32·40의 평균
    expect(x.reports.length, 3);
    expect(x.allFeatures, {'풀옵션'});

    final y = s['y']!;
    expect(y.sourceLabel, '시세 조사 1건');
    expect(y.roomPricingMap[HousingRoomType.twoRoom]?.monthlyRent, 60);
    // 관리비를 안 들었으면 모름(0) — 지어 넣지 않는다.
    expect(y.roomPricingMap[HousingRoomType.twoRoom]?.maintenanceFee, 0);
  });

  test('실제 데이터: 프라임은 원룸·투룸 시세가 따로 나온다', () {
    final s = summarizeWithSurvey(const {}, mapNames());
    final prime = s.entries.firstWhere((e) => mapNames()[e.key] == '프라임').value;
    expect(prime.roomPricingMap[HousingRoomType.oneRoom]?.monthlyRent, 37);
    expect(prime.roomPricingMap[HousingRoomType.twoRoom]?.deposit, 450); // 400·500
    expect(prime.roomPricingMap[HousingRoomType.twoRoom]?.monthlyRent, 70);

    // 조건 찾기에도 걸린다: 원룸, 관리비 빼고 월 40 이하
    final v = evaluateHousingFilter(
      prime,
      null,
      const HousingFilter(roomTypes: {HousingRoomType.oneRoom}, maxMonthly: 40, includeMaintenance: false),
    );
    expect(v.verdict, HousingFilterVerdict.match);
  });
}

void jeonseTests() {
  test('전세는 단지의 모든 동에 나오고, 이름은 모두 지도에 있다', () {
    final names = mapNames().values.map((v) => v.replaceAll(' ', '')).toSet();
    for (final e in kHousingJeonse) {
      for (final n in e.names) {
        expect(names, contains(n.replaceAll(' ', '')), reason: n);
      }
    }
    for (final dong in ['101동', '102동', '103동']) {
      expect(housingJeonseFor('태암수정아파트 $dong').length, 3, reason: dong);
    }
    expect(housingJeonseFor('서호e타운 102동').single.deposit, 2000);
    expect(housingJeonseFor('서호 e타운 상가'), isEmpty);
    expect(housingJeonseFor('가온빌'), isEmpty);
    expect(housingJeonseFor(null), isEmpty);
  });

  testWidgets('아파트를 누르면 시세·조건 카드에 전세가 보인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HousingDetailSheet(
          building: const BaseBuilding(
            id: '4371039030000900000024800',
            floors: 15,
            officialName: '태암수정아파트 102동',
            ring: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
          ),
          summary: HousingSummary.empty,
          known: null,
          edited: null,
          isDark: false,
          isFavorite: false,
          onToggleFavorite: () async {},
          onReported: () async {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('전세'), findsNWidgets(3));
    expect(find.textContaining('10층 · 관리비 7~9만원', findRichText: true), findsOneWidget);
    expect(find.textContaining('아직 시세 제보가 없어요'), findsNothing);
  });
}

void allReportsTests() {
  testWidgets('건물 창: 평균과 제보 전체 목록이 보이고, 제보 버튼은 늘 열려 있다', (tester) async {
    SharedPreferences.setMockInitialValues({'housing_reported_b': true});
    HousingReport r(int d, int m, {bool survey = false}) => HousingReport(
          buildingId: 'b',
          deposit: d,
          monthlyRent: m,
          roomType: HousingRoomType.oneRoom,
          features: const [],
          reportedAt: DateTime(2026, 9, 20),
          survey: survey,
        );
    final s = HousingSummary.from([r(300, 30), r(300, 30), r(200, 36, survey: true)]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HousingDetailSheet(
          building: const BaseBuilding(id: 'b', floors: 4, officialName: '가온빌', ring: [Offset(0, 0), Offset(10, 0), Offset(10, 10)]),
          summary: s,
          known: null,
          edited: null,
          isDark: false,
          isFavorite: false,
          onToggleFavorite: () async {},
          onReported: () async {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('방 구조별 평균 (만원)'), findsOneWidget);
    expect(find.text('보증금 267 · 월세 32'), findsOneWidget);
    expect(find.text('3건'), findsOneWidget);
    // 이미 제보한 기기여도 막지 않는다 — 다른 방 시세를 또 남길 수 있다.
    expect(find.text('다른 방 시세 알려주기'), findsOneWidget);
    expect(find.text('이미 제보함'), findsNothing);

    await tester.ensureVisible(find.text('제보 전체 보기 (3건)'));
    await tester.tap(find.text('제보 전체 보기 (3건)'));
    await tester.pumpAndSettle();
    expect(find.text('300 / 30'), findsNWidgets(2)); // 겹쳐도 둘 다 남는다
    expect(find.text('200 / 36'), findsOneWidget);
    expect(find.text('시세 조사'), findsOneWidget);
  });

  test('같은 기기의 중복 판단은 구조·금액이 모두 같을 때만', () {
    HousingReport r(int d, int m, {int? fee, HousingRoomType? t}) => HousingReport(
          buildingId: 'b',
          deposit: d,
          monthlyRent: m,
          maintenanceFee: fee,
          roomType: t,
          features: const [],
          reportedAt: DateTime(2026, 9, 20),
        );
    expect(housingReportSignature(r(300, 30)), housingReportSignature(r(300, 30)));
    expect(housingReportSignature(r(300, 30)), isNot(housingReportSignature(r(300, 32))));
    expect(housingReportSignature(r(300, 30)), isNot(housingReportSignature(r(300, 30, fee: 5))));
    expect(
      housingReportSignature(r(300, 30, t: HousingRoomType.oneRoom)),
      isNot(housingReportSignature(r(300, 30, t: HousingRoomType.twoRoom))),
    );
  });
}
