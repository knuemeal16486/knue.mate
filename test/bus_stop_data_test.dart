// 정류장 이름 데이터 회귀 테스트. bus_route_data.dart(노선별 정류장 목록)와
// bus_card.dart(정류장 좌표 맵)는 정류장 "이름 문자열"로 서로 연결돼 있어서,
// 한쪽만 고치면 조용히 어긋난다 — BusCard._getNearestStopName이 좌표를
// stopCoordinates[정류장이름]으로 찾기 때문에 이름이 안 맞으면 그 정류장은
// "가장 가까운 정류장" 후보에서 조용히 빠진다(에러 없이).
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_card.dart';
import 'package:knue_mate/bus_route_data.dart';

void main() {
  test('지하상가는 청년창업지원센터로 이름이 바뀌었다', () {
    // 정류장 명칭이 바뀌었는데 코드가 옛 이름을 들고 있으면 실시간 안내가
    // 실제 정류장 표지판과 달라 보인다.
    for (final route in BusRouteData.routeStops.entries) {
      for (final dir in route.value.entries) {
        expect(
          dir.value,
          isNot(contains('지하상가')),
          reason: '${route.key} ${dir.key}에 옛 이름이 남아 있다',
        );
      }
    }
    expect(BusCard.stopCoordinates.containsKey('지하상가'), isFalse);
    expect(BusCard.stopCoordinates.containsKey('청년창업지원센터'), isTrue);
  });
}
