// 정류장 "~ 방면" 표시와 교원대 종점으로 들어오는 차 이어 붙이기(2026-11-12).
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';
import 'package:knue_mate/bus_route_snapshot.dart';

void main() {
  group('정류장 표시', () {
    test('탑연삼거리는 번호 대신 다음 정류장 방면', () {
      expect(busTargetStopShort(busTargetStop('511', BusDirection.inbound)!), '탑연삼거리(월곡초등학교 방면)');
      expect(busTargetStopShort(busTargetStop('511', BusDirection.outbound)!), '탑연삼거리(궁평3리 방면)');
    });

    test('교원대 종점은 번호 없이 "교원대"', () {
      expect(busTargetStopShort(busTargetStop('513', BusDirection.outbound)!), '교원대');
      expect(busTargetStopShort(busTargetStop('513', BusDirection.inbound)!), '교원대');
    });

    test('표에 없는 정류장은 표지판 번호', () {
      expect(stopHeadingOrNumber('CJB999', '1234'), '1234');
      expect(stopHeadingOrNumber('CJB271000402', '3333'), '월탄1리 방면');
    });

    test('표의 정류장 id가 실제 노선 데이터에 있다(오타 방지)', () {
      final ids = {for (final l in kRouteStopsSnapshot.values) for (final s in l) s.nodeId};
      for (final id in kStopHeadingLabels.keys) {
        expect(ids, contains(id), reason: id);
      }
    });
  });

  group('carryTerminalApproach', () {
    final now = DateTime(2026, 11, 12, 18, 0);
    // 513: 월탄1리(42) → 한국교원대학교(43, 종점)
    BusArrival at513(String car, int ord, {DateTime? since, BusDirection dir = BusDirection.outbound}) => BusArrival(
          remainStops: 43 - ord,
          currentStopName: ord == 42 ? '월탄1리' : '정류장$ord',
          nodeOrd: ord,
          vehicleNo: car,
          direction: dir,
          estimatedMinutes: 2.8,
          atStopSince: since,
        );

    List<BusArrival> run(String route, List<BusArrival> prev, List<BusArrival> cur, {DateTime? prevAt}) =>
        carryTerminalApproach(routeNumber: route, previous: prev, previousAt: prevAt, current: cur, now: now);

    test('같은 정류장에 그대로면 처음 보인 시각을 이어 받는다', () {
      final t0 = now.subtract(const Duration(minutes: 5));
      final out = run('511', [at513('A', 30, since: t0)], [at513('A', 30)]);
      expect(out.single.atStopSince, t0);
    });

    test('정류장을 옮겼으면 지금부터', () {
      final out = run('511', [at513('A', 30, since: now.subtract(const Duration(minutes: 5)))], [at513('A', 31)]);
      expect(out.single.atStopSince, now);
    });

    test('월탄1리에 1분째인 513은 2분 뒤 도착', () {
      final t0 = now.subtract(const Duration(minutes: 1));
      final out = run('513', [at513('A', 42, since: t0)], [at513('A', 42)]);
      expect(out.single.estimatedMinutes, closeTo(2, 1e-9));
      expect(out.single.etaFromApi, isFalse);
    });

    test('월탄1리 뒤 사라진 차: 3분까지 곧 도착으로 이어 보여 준다', () {
      final t0 = now.subtract(const Duration(minutes: 1));
      final out = run('513', [at513('A', 42, since: t0)], const []);
      expect(out, hasLength(1));
      expect(out.single.remainStops, 1);
      expect(out.single.estimatedMinutes, closeTo(2, 1e-9));
      expect(out.single.atStopSince, t0);
    });

    test('3분이 지나면 교원대 도착으로 2분 남긴다', () {
      final t0 = now.subtract(const Duration(minutes: 4));
      final out = run('513', [at513('A', 42, since: t0)], const []);
      expect(out.single.remainStops, 0);
      expect(out.single.currentStopName, '한국교원대학교');
      expect(out.single.nodeOrd, 43);
    });

    test('5분이 지나면 지운다', () {
      final t0 = now.subtract(const Duration(minutes: 6));
      expect(run('513', [at513('A', 42, since: t0)], const []), isEmpty);
    });

    test('다시 나타난 차(출발)는 이어 붙이지 않는다', () {
      final t0 = now.subtract(const Duration(minutes: 1));
      final out = run('513', [at513('A', 42, since: t0)], [at513('A', 45, dir: BusDirection.inbound)]);
      expect(out, hasLength(1));
      expect(out.single.nodeOrd, 45);
    });

    test('종점 노선이 아니면 사라진 차를 이어 붙이지 않는다', () {
      final t0 = now.subtract(const Duration(minutes: 1));
      expect(run('511', [at513('A', 42, since: t0)], const []), isEmpty);
    });

    test('처음 보인 시각이 없던 옛 문서는 문서 시각으로', () {
      final prevAt = now.subtract(const Duration(minutes: 2));
      final out = run('513', [at513('A', 42)], const [], prevAt: prevAt);
      expect(out.single.estimatedMinutes, closeTo(1, 1e-9));
    });

    test('공용 문서에 처음 보인 시각이 저장된다', () {
      final t0 = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch - 60000);
      final s = BusSummary(
        id: 513, number: '513', type: 'blue', direction: '', congestion: 'normal', isDirect: true,
        arrivals: [at513('A', 42, since: t0)],
      );
      expect(BusSummary.fromJson(s.toJson()).arrivals.single.atStopSince, t0);
    });
  });
}
