import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

/// 실제 공공데이터포털 응답(2026-09-19 확인)을 그대로 옮긴 값들.
///
/// 왕복 노선은 정류장 순서가 상행·하행을 하나로 이어 붙인 형태라 기준
/// 정류장이 목록에 두 번 나온다. 예전 구현은 상행 것 하나만 보고 "남은
/// 정거장 = 기준 - 현재"가 음수면 하행으로 치웠는데, 그 바람에 돌아오는
/// 길에 우리 정류장으로 다가오는 버스가 전부 버려졌다.
RouteStop _stop(String name, int ord, int ud) =>
    RouteStop(nodeId: 'n$ord', nodeName: name, nodeOrd: ord, upDownCd: ud);

void main() {
  group('targetOrdsFromStops — 기준 정류장 찾기', () {
    test('511번: 탑연삼거리가 상행 47 / 하행 82로 두 번 잡힌다', () {
      // 실측: 총 129개 정류장, 63번(오송역종점)에서 상행→하행 전환.
      final stops = [
        _stop('정하', 1, 0),
        _stop('탑연삼거리', 47, 0),
        _stop('오송역종점', 63, 0),
        _stop('오송역6', 64, 1),
        _stop('탑연삼거리', 82, 1),
        _stop('정하', 129, 1),
      ];
      final targets = targetOrdsFromStops(stops, '탑연삼거리');
      expect(targets, [
        const TargetStopOrd(47, BusDirection.outbound),
        const TargetStopOrd(82, BusDirection.inbound),
      ]);
    });

    test('부분일치로 엉뚱한 정류장을 잡지 않는다', () {
      // 518·913번엔 "한국교원대학교입구", "한국교원대정문"처럼 이름이
      // 비슷한 다른 정류장이 실제로 있다. 부분일치를 쓰면 도착 기준이
      // 엉뚱한 곳으로 밀린다.
      final stops = [
        _stop('한국교원대학교', 32, 0),
        _stop('한국교원대정문', 34, 0),
        _stop('한국교원대후문', 36, 0),
        _stop('한국교원대학교입구', 46, 1),
        _stop('한국교원대학교', 47, 1),
      ];
      final targets = targetOrdsFromStops(stops, '한국교원대학교');
      expect(targets, [
        const TargetStopOrd(32, BusDirection.outbound),
        const TargetStopOrd(47, BusDirection.inbound),
      ]);
    });

    test('913번처럼 같은 방향에 두 번 나오면 먼저 닿는 쪽만 쓴다', () {
      // 실측: 913번은 상행에 32·33, 하행에 47·48로 연속해서 나온다.
      final stops = [
        _stop('한국교원대학교', 32, 0),
        _stop('한국교원대학교', 33, 0),
        _stop('한국교원대학교', 47, 1),
        _stop('한국교원대학교', 48, 1),
      ];
      final targets = targetOrdsFromStops(stops, '한국교원대학교');
      expect(targets, [
        const TargetStopOrd(32, BusDirection.outbound),
        const TargetStopOrd(47, BusDirection.inbound),
      ]);
    });

    test('updowncd가 없으면 상행으로 본다', () {
      final stops = [
        RouteStop(nodeId: 'a', nodeName: '탑연삼거리', nodeOrd: 10),
      ];
      expect(
        targetOrdsFromStops(stops, '탑연삼거리'),
        [const TargetStopOrd(10, BusDirection.outbound)],
      );
    });

    test('일치하는 정류장이 없으면 빈 목록', () {
      expect(targetOrdsFromStops([_stop('오송역', 1, 0)], '탑연삼거리'), isEmpty);
    });
  });

  group('nextTargetFor — 다음에 닿을 기준 정류장', () {
    // 511번 실측값
    const targets = [
      TargetStopOrd(47, BusDirection.outbound),
      TargetStopOrd(82, BusDirection.inbound),
    ];

    test('상행 지점 앞에 있으면 상행으로 잡힌다', () {
      final t = nextTargetFor(31, targets);
      expect(t, const TargetStopOrd(47, BusDirection.outbound));
      expect(t!.ord - 31, 16); // 16정거장 남음
    });

    test('상행 지점을 지났으면 하행 지점으로 잡힌다 (예전엔 버려지던 케이스)', () {
      // 실제로 잡힌 차: nodeord 52(한국보건복지인재원).
      // 예전 계산은 47 - 52 = -5 → "이미 지나감"으로 도착시간 없음.
      // 이제는 돌아오는 길 82번 지점까지 30정거장으로 잡힌다.
      final t = nextTargetFor(52, targets);
      expect(t, const TargetStopOrd(82, BusDirection.inbound));
      expect(t!.ord - 52, 30);
    });

    test('하행 지점 바로 앞 차도 제대로 잡힌다', () {
      final t = nextTargetFor(70, targets);
      expect(t!.dir, BusDirection.inbound);
      expect(t.ord - 70, 12);
    });

    test('기준 정류장에 정확히 서 있으면 0정거장', () {
      final t = nextTargetFor(47, targets);
      expect(t, const TargetStopOrd(47, BusDirection.outbound));
      expect(t!.ord - 47, 0);
    });

    test('두 지점을 다 지나면 null — 이번 운행엔 안 온다', () {
      expect(nextTargetFor(100, targets), isNull);
    });

    test('어떤 위치에서도 남은 정거장이 음수가 되지 않는다', () {
      // 이게 이번 수정의 핵심 — 음수가 곧 "도착시간 없음"이었다.
      for (var ord = 1; ord <= 129; ord++) {
        final t = nextTargetFor(ord, targets);
        if (t == null) continue;
        expect(t.ord - ord, greaterThanOrEqualTo(0), reason: 'nodeord=$ord');
      }
    });
  });

  group('targetOrdsFromFallback', () {
    test('상행·하행 순서로 변환된다', () {
      expect(targetOrdsFromFallback([47, 82]), [
        const TargetStopOrd(47, BusDirection.outbound),
        const TargetStopOrd(82, BusDirection.inbound),
      ]);
    });

    test('하나뿐이면 상행만', () {
      expect(targetOrdsFromFallback([15]), [
        const TargetStopOrd(15, BusDirection.outbound),
      ]);
    });

    test('비었거나 null이면 빈 목록', () {
      expect(targetOrdsFromFallback(null), isEmpty);
      expect(targetOrdsFromFallback(const []), isEmpty);
    });
  });

  group('BusSummary 방향별 조회', () {
    BusArrival arr(int remain, BusDirection dir) => BusArrival(
          remainStops: remain,
          currentStopName: 's$remain',
          direction: dir,
        );

    test('방향별로 갈라서 가까운 순으로 준다', () {
      final s = BusSummary(
        id: 1,
        number: '511',
        type: 'blue',
        direction: '',
        arrivals: [
          arr(20, BusDirection.inbound),
          arr(5, BusDirection.outbound),
          arr(8, BusDirection.inbound),
        ],
        congestion: 'normal',
        isDirect: false,
      );
      expect(
        s.arrivalsTowards(BusDirection.inbound).map((a) => a.remainStops),
        [8, 20],
      );
      expect(s.nextArrivalTowards(BusDirection.outbound)!.remainStops, 5);
      // 전체 기준 가장 가까운 차는 상행 5정거장짜리
      expect(s.nextArrival!.remainStops, 5);
    });

    test('한쪽 방향만 있으면 반대쪽은 비어 있다', () {
      final s = BusSummary(
        id: 1,
        number: '747',
        type: 'red',
        direction: '',
        arrivals: [arr(3, BusDirection.outbound)],
        congestion: 'normal',
        isDirect: false,
      );
      expect(s.arrivalsTowards(BusDirection.inbound), isEmpty);
      expect(s.nextArrivalTowards(BusDirection.inbound), isNull);
    });
  });
}
