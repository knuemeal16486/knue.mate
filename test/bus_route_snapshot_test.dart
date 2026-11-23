// 버스 노선 스냅샷·방향 이름·도착 시간 맞추기(2026-11-12).
//
// 노선마다 "상행"의 뜻이 달라(513 상행 = 교원대로 들어오는 차, 511 상행 = 오송역
// 가는 차) 화면엔 행선지를 보여 준다. 그 이름이 실제 노선 데이터와 맞는지 여기서
// 확인한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';
import 'package:knue_mate/bus_route_snapshot.dart';

void main() {
  group('노선 스냅샷', () {
    test('앱의 노선 10개가 모두 들어 있다', () {
      for (final r in kBusRoutes) {
        expect(kRouteStopsSnapshot[r.routeId], isNotEmpty, reason: '${r.routeNumber}');
      }
    });

    test('생성 도구의 노선 목록이 앱과 같다', () {
      final tool = File('tool/fetch_bus_route_stops.dart').readAsStringSync();
      for (final r in kBusRoutes) {
        expect(tool, contains("${r.routeNumber}: '${r.routeId}'"), reason: '${r.routeNumber}');
      }
    });

    test('기준 정류장 지점이 검증해 둔 폴백 표(2026-09-19)와 같다', () {
      const expected = {
        '513': [43, 44], '514': [47, 48], '518': [1, 36], '913': [32, 47],
        '500': [45, 66], '502': [42, 79], '503': [51, 76], '509': [16, 23],
        '511': [47, 82], '747': [15, 18],
      };
      for (final e in expected.entries) {
        expect(snapshotTargetsFor(e.key).map((t) => t.ord), e.value, reason: e.key);
      }
    });

    test('탑연삼거리: 오송 쪽은 3308, 청주 쪽은 3309 정류장', () {
      for (final n in ['500', '502', '503', '509', '511', '747']) {
        expect(busTargetStop(n, BusDirection.outbound)?.nodeNo, '3308', reason: n);
        expect(busTargetStop(n, BusDirection.inbound)?.nodeNo, '3309', reason: n);
      }
    });
  });

  group('방향 이름', () {
    List<RouteStop> stops(String n) =>
        kRouteStopsSnapshot[busRouteConfig(n)!.routeId]!;
    String endOf(String n, int ud) => stops(n).where((s) => s.upDownCd == ud).last.nodeName;

    test('모든 노선에 이름이 있다', () {
      for (final r in kBusRoutes) {
        expect(kBusDirectionLabels.containsKey('${r.routeNumber}'), isTrue);
      }
    });

    test('이름이 실제 종점과 맞다', () {
      expect(endOf('511', 0), contains('오송역'));
      expect(endOf('500', 0), contains('오송역'));
      expect(endOf('503', 0), contains('오송역'));
      expect(endOf('747', 0), contains('오송역'));
      expect(endOf('502', 0), contains('조치원역'));
      expect(endOf('509', 0), contains('조치원역'));
      expect(endOf('747', 1), '청주국제공항');
      expect(endOf('913', 0), '미호종점');
      // 513·514는 상행 끝이 교원대(종점), 하행은 교원대에서 출발한다.
      expect(endOf('513', 0), '한국교원대학교');
      expect(stops('513').firstWhere((s) => s.upDownCd == 1).nodeName, '한국교원대학교');
      // 518은 교원대에서 출발해 교원대로 돌아온다.
      expect(stops('518').first.nodeName, '한국교원대학교');
      expect(endOf('518', 1), '한국교원대학교');
    });

    test('상행을 그대로 보여 주지 않는다', () {
      expect(busDirectionLabel('513', BusDirection.outbound), '교원대 종점 도착');
      expect(busDirectionLabel('511', BusDirection.outbound), '오송역행');
      expect(busDirectionLabel('511', BusDirection.inbound), '청주행');
      expect(busDirectionLabel('747', BusDirection.inbound), '청주공항행');
      expect(busDirectionLabel('999', BusDirection.outbound), '상행'); // 모르는 노선
    });
  });

  group('구역(청주 방면 / 오송·조치원 방면)', () {
    test('노선마다 두 방향이 정확히 한 번씩 들어간다', () {
      for (final r in kBusRoutes) {
        final n = '${r.routeNumber}';
        final all = [
          ...busDirectionsFor(n, BusHeading.cheongju),
          ...busDirectionsFor(n, BusHeading.osong),
        ];
        expect(all.toSet(), BusDirection.values.toSet(), reason: n);
        expect(all, hasLength(2), reason: n);
      }
    });

    test('513 상행(교원대로 들어오는 차)은 오송 구역이 아니라 청주 구역', () {
      expect(busDirectionsFor('513', BusHeading.cheongju), contains(BusDirection.outbound));
      expect(busDirectionsFor('513', BusHeading.osong), isEmpty);
    });

    test('518은 두 방향 다 오송 구역', () {
      expect(busDirectionsFor('518', BusHeading.osong), hasLength(2));
    });
  });

  group('공용 문서의 방향', () {
    BusSummary roundTrip(BusSummary s) => BusSummary.fromJson(s.toJson());
    const summary = BusSummary(
      id: 511,
      number: '511',
      type: 'blue',
      direction: '정하동 ↔ 오송역',
      congestion: 'normal',
      isDirect: false,
      arrivals: [
        BusArrival(remainStops: 1, currentStopName: '궁평교차로', nodeOrd: 81, direction: BusDirection.inbound, estimatedMinutes: 2.2, etaFromApi: true),
        BusArrival(remainStops: 22, currentStopName: '청주체육관', nodeOrd: 25, direction: BusDirection.outbound, estimatedMinutes: 28),
      ],
    );

    test('방향·ETA 출처가 저장되고 그대로 읽힌다', () {
      final back = roundTrip(summary);
      expect(back.arrivals.map((a) => a.direction), [BusDirection.inbound, BusDirection.outbound]);
      expect(back.arrivals.map((a) => a.etaFromApi), [true, false]);
    });

    test('방향이 없는 옛 문서는 정류장 순번으로 다시 정한다', () {
      // 1.6.4 이하가 쓴 문서 — 예전엔 이걸 읽으면 모든 차가 "상행"이 됐다.
      expect(directionFromJsonForTest(null, '511', 81), BusDirection.inbound);
      expect(directionFromJsonForTest(null, '511', 25), BusDirection.outbound);
      expect(directionFromJsonForTest(null, '511', 60), BusDirection.inbound);
      expect(directionFromJsonForTest('inbound', '511', 25), BusDirection.inbound);
    });
  });

  group('resolveVehicleEtas', () {
    double heuristic(int r) => r * 1.8;

    test('남은 정거장이 같은 차에 API 도착 예정을 붙인다', () {
      final out = resolveVehicleEtas(
        vehicles: [(22, 'A'), (1, 'B')],
        etas: const [
          StopEta(nodeId: 'A', stopsAway: 22, seconds: 1680),
          StopEta(nodeId: 'B', stopsAway: 1, seconds: 133),
        ],
        fallback: heuristic,
      );
      expect(out[0], (28.0, true));
      expect(out[1].$1, closeTo(133 / 60, 1e-9));
      expect(out[1].$2, isTrue);
    });

    test('받는 사이 한 정거장 움직였어도(±1) 붙인다', () {
      final out = resolveVehicleEtas(
        vehicles: [(23, 'A')],
        etas: const [StopEta(nodeId: 'A', stopsAway: 22, seconds: 1680)],
        fallback: heuristic,
      );
      expect(out[0].$2, isTrue);
    });

    test('다른 정류장(방향)으로 가는 차엔 붙이지 않는다', () {
      final out = resolveVehicleEtas(
        vehicles: [(22, 'B')],
        etas: const [StopEta(nodeId: 'A', stopsAway: 22, seconds: 1680)],
        fallback: heuristic,
      );
      expect(out[0].$2, isFalse);
    });

    test('API가 주지 않은 뒤차는 그 노선의 실제 속도로 어림한다', () {
      final out = resolveVehicleEtas(
        vehicles: [(10, 'A'), (20, 'A')],
        etas: const [StopEta(nodeId: 'A', stopsAway: 10, seconds: 600)], // 1분/정거장
        fallback: heuristic,
      );
      expect(out[0], (10.0, true));
      expect(out[1], (20.0, false)); // 1.8분 × 20 = 36분이 아니라
    });

    test('API 값이 하나도 없으면 예전 어림값', () {
      final out = resolveVehicleEtas(vehicles: [(10, 'A')], etas: const [], fallback: heuristic);
      expect(out[0], (18.0, false));
    });

    test('같은 정류장에 두 방향이 오는 913: 남은 정거장으로 가른다', () {
      // 913은 교원대 3334를 상행(32)·하행(47) 모두 지난다.
      final out = resolveVehicleEtas(
        vehicles: [(5, 'X'), (14, 'X')],
        etas: const [StopEta(nodeId: 'X', stopsAway: 14, seconds: 1200)],
        fallback: heuristic,
      );
      expect(out[0].$2, isFalse);
      expect(out[1], (20.0, true));
    });
  });
}
