// 실시간 버스 상행/하행 판정 회귀 테스트.
//
// 판정 방식이 두 번 바뀌었다.
//  1세대: 직전 폴링의 nodeOrd와 비교해 "늘었으면 상행" — 왕복 노선은 하행에서도
//         nodeOrd가 늘기 때문에 거의 전부 상행으로 오판됐다.
//  2세대: remainStops(기준 정류장 - 현재)의 부호 — 방향은 갈렸지만, 기준 정류장을
//         하나만 잡아둔 탓에 **돌아오는 길에 우리 정류장으로 다가오는 차가 전부
//         "이미 지나간 차"로 버려져** 하행엔 도착 예정 시간이 아예 없었다.
//  3세대(현재): 노선 정류장 순서에서 기준 정류장이 나오는 두 지점을 모두 찾고,
//         차량 위치에서 "다음에 닿을 지점"을 고른다. 방향은 그 지점의 updowncd
//         (API가 직접 주는 값)로 정해지고, 남은 정거장은 항상 0 이상이 된다.
//
// 3세대 핵심 로직 자체는 bus_direction_target_test.dart가 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

void main() {
  group('BusArrival.direction', () {
    test('방향은 부호가 아니라 명시된 값으로 정해진다', () {
      // 같은 remainStops라도 방향이 다를 수 있다 — 부호로는 절대 못 가른다.
      const up = BusArrival(
        remainStops: 12,
        currentStopName: '충청대학교',
        direction: BusDirection.outbound,
      );
      const down = BusArrival(
        remainStops: 12,
        currentStopName: '오송역',
        direction: BusDirection.inbound,
      );
      expect(up.direction.label, '상행');
      expect(down.direction.label, '하행');
    });

    test('하행 차량도 도착 상태 문구가 정상적으로 나온다', () {
      // 예전엔 하행이면 remainStops가 음수라 "현재 위치: …"만 나오고
      // 도착 예정이라는 개념 자체가 없었다.
      const arrival = BusArrival(
        remainStops: 2,
        currentStopName: '월곡초등학교',
        direction: BusDirection.inbound,
        estimatedMinutes: 4.0,
      );
      expect(arrival.statusText, '곧 도착');
      expect(arrival.remainStops, greaterThanOrEqualTo(0));
    });

    test('기본값은 상행', () {
      const arrival = BusArrival(remainStops: 5, currentStopName: 'x');
      expect(arrival.direction, BusDirection.outbound);
    });
  });

  group('congestionLevelLabel', () {
    test('API가 값을 안 주면(null) 추정치로 폴백하라는 신호로 null을 준다', () {
      expect(congestionLevelLabel(null), isNull);
    });

    test('1~4는 각각 등급 문자열로 바뀐다', () {
      expect(congestionLevelLabel(1), 'empty');
      expect(congestionLevelLabel(2), 'normal');
      expect(congestionLevelLabel(3), 'crowded');
      expect(congestionLevelLabel(4), 'full');
    });
  });

  group('BusSummary.isCongestionEstimated', () {
    test('필드가 없는 예전 캐시는 추정치로 간주한다', () {
      // 필드 추가 전 캐시에는 이 키가 없다. 기본값을 실측(false)으로 두면
      // 실제로는 추정치인 값을 실측인 것처럼 보여주게 된다.
      final json = {
        'id': 513,
        'number': '513',
        'type': 'blue',
        'direction': '교원대 정문행 (직행)',
        'arrivals': [],
        'congestion': 'normal',
        'isDirect': true,
      };
      expect(BusSummary.fromJson(json).isCongestionEstimated, isTrue);
    });

    test('JSON 왕복에서 실측/추정 여부가 보존된다', () {
      const summary = BusSummary(
        id: 513,
        number: '513',
        type: 'blue',
        direction: '교원대 정문행 (직행)',
        arrivals: [],
        congestion: 'crowded',
        isDirect: true,
        isCongestionEstimated: false,
      );
      expect(
        BusSummary.fromJson(summary.toJson()).isCongestionEstimated,
        isFalse,
      );
    });
  });
}
