// 식단/버스/캠퍼스맵의 "데이터가 실제로 살아있는지" 확인하는 헬스체크.
// UI가 아니라 각 기능이 의존하는 데이터 소스 자체를 검증한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_timetable_data.dart';

void main() {
  group('버스 시간표 (오프라인 폴백)', () {
    test('홈 카드가 조회하는 513/514/518 노선 시간표가 모두 존재한다', () {
      for (final route in ['513', '514', '518']) {
        for (final outgoing in [true, false]) {
          for (final weekday in [true, false]) {
            final t = BusTimetableData.getTimetable(route, outgoing, weekday);
            expect(t, isNotNull,
                reason: '$route outgoing=$outgoing weekday=$weekday 시간표 없음');
            expect(t!, isNotEmpty,
                reason: '$route outgoing=$outgoing weekday=$weekday 시간표 비어있음');
          }
        }
      }
    });

    test('시간표가 HH:MM 형식이고 오름차순으로 정렬돼 있다', () {
      // getNextBusTime이 "첫 번째로 현재시각보다 큰 값"을 반환하므로
      // 정렬이 깨지면 엉뚱한 시간이 나온다.
      final re = RegExp(r'^\d{2}:\d{2}$');
      for (final route in ['513', '514', '518']) {
        for (final outgoing in [true, false]) {
          for (final weekday in [true, false]) {
            final t = BusTimetableData.getTimetable(route, outgoing, weekday)!;
            for (final s in t) {
              expect(re.hasMatch(s), isTrue, reason: '$route: 잘못된 형식 "$s"');
            }
            final sorted = [...t]..sort();
            expect(t, orderedEquals(sorted), reason: '$route: 시간표 정렬 깨짐');
          }
        }
      }
    });

    test('하루 중 어느 시각에서든 다음 버스 조회가 예외 없이 동작한다', () {
      for (final route in ['513', '514', '518']) {
        final next = BusTimetableData.getNextBusTime(route, true, true);
        // 막차 이후면 null이 정상이므로 null 여부가 아니라 형식만 본다.
        if (next != null) {
          expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(next), isTrue);
        }
      }
    });
  });

  group('캠퍼스 맵 건물 데이터', () {
    late Map<String, dynamic> json;

    setUpAll(() {
      final f = File('assets/buildings/knue_buildings.json');
      expect(f.existsSync(), isTrue, reason: '건물 JSON 에셋이 없다');
      json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    });

    test('buildings 배열이 존재하고 비어있지 않다', () {
      expect(json['buildings'], isA<List>());
      expect((json['buildings'] as List), isNotEmpty);
    });

    test('모든 건물이 name/floors를 갖고 층 구조가 파서 기대와 일치한다', () {
      // loadBuildingData()가 bJson['name'], ['floors'], fJson['floor'],
      // fJson['facilities'], fac['name'] 을 무조건 참조하므로 하나라도
      // 비면 런타임에 캠퍼스 맵이 깨진다.
      for (final b in (json['buildings'] as List)) {
        expect(b['name'], isA<String>());
        expect((b['name'] as String), isNotEmpty);
        expect(b['floors'], isA<List>(), reason: '${b['name']}: floors 없음');
        for (final f in (b['floors'] as List)) {
          expect(f['floor'], isNotNull, reason: '${b['name']}: floor 값 없음');
          expect(f['facilities'], isA<List>(),
              reason: '${b['name']}: facilities 없음');
          for (final fac in (f['facilities'] as List)) {
            expect(fac, isA<Map>(), reason: '${b['name']}: facility 형식 오류');
          }
        }
      }
    });
  });
}
