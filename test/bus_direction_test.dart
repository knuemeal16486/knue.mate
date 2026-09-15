// 실시간 버스 상행/하행 판정 회귀 테스트.
//
// 예전에는 직전 폴링 때의 nodeOrd와 비교해 "늘었으면 상행"으로 추정했다.
// 왕복 노선의 nodeOrd는 상행·하행을 합쳐 하나로 이어진 순번이라, 버스가
// 전진하는 한 nodeOrd는 방향에 상관없이 거의 항상 늘어난다 — 그래서 사실상
// 늘 "상행"으로만 판정됐고, 처음 보는 차량(과거 기록 없음)은 걸러내지도
// 못해 상행 탭에 하행 버스가 같이 찍혔다. 왕복 노선(502 등)은 상행·하행이
// 같은 정류장 이름을 쓰기 때문에 이름 매칭만으로는 둘을 못 가른다.
//
// 지금은 bus_service.dart가 이미 계산해 둔 remainStops(기준 정류장 nodeOrd -
// 현재 nodeOrd)의 부호만으로 상태 기록 없이 매 순간 정확하게 가른다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

void main() {
  group('busDirectionLabel', () {
    test('기준 정류장에 아직 도달 전(양수)이면 상행', () {
      expect(busDirectionLabel(37), '상행');
      expect(busDirectionLabel(4), '상행');
      expect(busDirectionLabel(0), '상행'); // 도착 직전도 상행 취급
    });

    test('기준 정류장을 이미 지났으면(음수) 하행', () {
      expect(busDirectionLabel(-1), '하행');
      expect(busDirectionLabel(-20), '하행');
      expect(busDirectionLabel(-77), '하행');
    });

    test('직전 폴링 기록이 없어도(첫 관측) 정확하다', () {
      // 예전 트렌드 기반 판정은 과거 기록이 없으면 null을 반환해 필터링이
      // 무력화됐다. 이 함수는 상태가 아예 없으므로 항상 답을 낸다.
      expect(busDirectionLabel(37), isNotNull);
      expect(busDirectionLabel(-20), isNotNull);
    });

    test('같은 차량의 nodeOrd가 계속 늘어나도(정상 전진) 하행으로 정확히 잡힌다', () {
      // 예전 버그의 핵심 사례: 하행 leg에서도 버스가 전진하면 nodeOrd는
      // 계속 늘어난다. "늘었으면 상행" 규칙이면 이 버스는 영원히 상행으로
      // 오판된다. remainStops는 기준 정류장과의 거리이므로 흔들리지 않는다.
      final progressingDownbound = [-5, -12, -20, -34, -39];
      for (final r in progressingDownbound) {
        expect(busDirectionLabel(r), '하행',
            reason: 'remainStops=$r인데 하행으로 안 잡힘');
      }
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
