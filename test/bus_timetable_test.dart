// 시간표가 공식 시간표 사진과 어긋나지 않는지 지킨다.
//
// 사진을 사람이 옮겨 적은 값이라 오타가 나면 학생이 버스를 놓친다.
// 여기서는 "형태가 성립하는가"를 본다 — 개수, 정렬, 시각 형식, 방향 의미.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_route_data.dart';
import 'package:knue_mate/bus_timetable_data.dart';

void main() {
  group('시간표 형태', () {
    test('시각이 HH:MM이고 이른 순으로 정렬돼 있다', () {
      BusTimetableData.schedules.forEach((route, dirs) {
        dirs.forEach((dir, days) {
          days.forEach((day, times) {
            expect(times, isNotEmpty, reason: '$route $dir $day');
            for (final t in times) {
              expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(t), isTrue,
                  reason: '$route $dir $day: $t');
            }
            final sorted = [...times]..sort();
            expect(times, sorted, reason: '$route $dir $day 정렬 안 됨');
          });
        });
      });
    });

    test('평일과 주말이 같다 (513·514·518 공식표가 그렇다)', () {
      for (final route in ['513', '514', '518']) {
        for (final dir in ['outgoing', 'incoming']) {
          expect(BusTimetableData.schedules[route]![dir]!['weekday'],
              BusTimetableData.schedules[route]![dir]!['holiday'],
              reason: '$route $dir');
        }
      }
    });

    test('노선별 운행 횟수가 공식표와 맞는다', () {
      // 2026-03-14(513·514), 2023-12-30(518) 개정판 사진에서 센 값.
      const expected = {
        '513': {'outgoing': 19, 'incoming': 18},
        '514': {'outgoing': 19, 'incoming': 19},
        '518': {'outgoing': 21, 'incoming': 21},
      };
      expected.forEach((route, dirs) {
        dirs.forEach((dir, n) {
          expect(BusTimetableData.schedules[route]![dir]!['weekday']!.length, n,
              reason: '$route $dir');
        });
      });
    });

    test('첫차·막차가 공식표와 맞는다', () {
      const first = {
        '513': {'outgoing': '06:20', 'incoming': '06:05'},
        '514': {'outgoing': '05:30', 'incoming': '05:30'},
        '518': {'outgoing': '05:40', 'incoming': '05:40'},
      };
      const last = {
        '513': {'outgoing': '22:40', 'incoming': '22:10'},
        '514': {'outgoing': '22:27', 'incoming': '22:30'},
        '518': {'outgoing': '22:50', 'incoming': '22:40'},
      };
      first.forEach((route, dirs) {
        dirs.forEach((dir, t) {
          final list = BusTimetableData.schedules[route]![dir]!['weekday']!;
          expect(list.first, t, reason: '$route $dir 첫차');
          expect(list.last, last[route]![dir], reason: '$route $dir 막차');
        });
      });
    });
  });

  group('913번', () {
    test('종점 기준 시간표가 사진대로 들어 있다', () {
      final a = BusTimetableData.route913Terminal['평동→미호종점']!;
      final b = BusTimetableData.route913Terminal['미호종점→평동']!;
      expect(a.length, 12);
      expect(b.length, 13);
      expect(a.first, ['05:40', '06:45']);
      expect(a.last, ['21:25', '22:30']);
      expect(b.first, ['05:30', '06:35']);
      expect(b.last, ['22:30', '23:30']);
    });

    test('출발보다 도착이 늦다', () {
      BusTimetableData.route913Terminal.forEach((dir, runs) {
        for (final r in runs) {
          expect(r[1].compareTo(r[0]) > 0, isTrue, reason: '$dir $r');
        }
      });
    });

    test('노선이 평동↔미호종점이고 교원대를 지난다', () {
      // 개정 전 데이터는 정북동↔교원대였다. 공식 노선도에 그 정류장들이
      // 하나도 없어 통째로 갈아끼웠다.
      final up = BusRouteData.routeStops['913']!['상행'] as List;
      final down = BusRouteData.routeStops['913']!['하행'] as List;
      expect(up.first, '평동');
      expect(up.last, '미호종점');
      expect(down.first, '미호종점');
      expect(down.last, '평동');
      expect(up.contains('한국교원대학교'), isTrue);
      expect(down.contains('한국교원대학교'), isTrue);
      expect(up.contains('정북동'), isFalse, reason: '옛 노선이 되살아났다');
    });

    test('정류장 표기가 다른 노선과 같다', () {
      // 같은 정류장을 노선마다 다르게 적으면 실시간 도착정보가 안 붙는다.
      final r518 = ((BusRouteData.routeStops['518']!['상행'] as List)
          .cast<String>()).toSet();
      final r913 = (BusRouteData.routeStops['913']!['상행'] as List).cast<String>();
      for (final shared in ['한국교원대학교', '한국교원대정문', '한국교원대후문',
        '월탄1리', '강내면행정복지센터', '탑연삼거리']) {
        expect(r913.contains(shared), isTrue, reason: '913에 $shared 없음');
        expect(r518.contains(shared), isTrue, reason: '518에 $shared 없음');
      }
    });

    test('시간표가 종점 원본과 어긋나지 않는다', () {
      // schedules의 913은 route913Terminal에서 출발 시각만 뽑은 것이다.
      // 둘이 어긋나면 화면과 원본이 달라진다.
      final up = BusTimetableData.route913Terminal['평동→미호종점']!
          .map((r) => r[0])
          .toList();
      final down = BusTimetableData.route913Terminal['미호종점→평동']!
          .map((r) => r[0])
          .toList();
      expect(BusTimetableData.schedules['913']!['incoming']!['weekday'], up,
          reason: 'incoming은 평동 출발이어야 한다');
      expect(BusTimetableData.schedules['913']!['outgoing']!['weekday'], down,
          reason: 'outgoing은 미호종점 출발이어야 한다');
    });

    test('승차 정류장 보정값은 비워 둔다', () {
      // 종점에서 교원대까지 몇 분인지 아직 모른다. 추측한 값을 넣으면
      // 학생이 그만큼 어긋난 시각을 보고 버스를 놓친다.
      expect(BusTimetableData.boardingStops['913'], isEmpty);
    });

    test('913번 상세 운행 데이터(교원대 경유, 종점 도착)가 올바르다', () {
      final upTrips = BusTimetableData.route913PyeongdongToMiho;
      final downTrips = BusTimetableData.route913MihoToPyeongdong;

      expect(upTrips.length, 12);
      expect(downTrips.length, 13);

      for (final trip in upTrips) {
        expect(trip.originName, '평동');
        expect(trip.destinationName, '미호종점');
        // 출발 < 교원대 경유 < 종점 도착
        expect(trip.knueTime.compareTo(trip.originTime) > 0, isTrue);
        expect(trip.destinationTime.compareTo(trip.knueTime) > 0, isTrue);
      }

      for (final trip in downTrips) {
        expect(trip.originName, '미호종점');
        expect(trip.destinationName, '평동');
        // 출발 < 교원대 경유 < 종점 도착
        expect(trip.knueTime.compareTo(trip.originTime) > 0, isTrue);
        expect(trip.destinationTime.compareTo(trip.knueTime) > 0, isTrue);
      }
    });
  });
}
