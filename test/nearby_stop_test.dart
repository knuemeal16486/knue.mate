// 가까운 정류장·정류장 도착 정보(2026-11-12). 응답 예시는 그날 실제 응답이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/nearby_stop.dart';

Map<String, dynamic> _ok(dynamic items) => {
      'response': {
        'header': {'resultCode': '00', 'resultMsg': 'NORMAL SERVICE.'},
        'body': {'items': items, 'numOfRows': 30, 'pageNo': 1, 'totalCount': 0},
      },
    };

void main() {
  group('tagoItems', () {
    test('결과가 없으면 items가 빈 문자열로 온다', () {
      expect(tagoItems(_ok('')), isEmpty);
    });
    test('결과가 하나면 배열이 아니라 객체로 온다', () {
      expect(tagoItems(_ok({'item': {'routeno': 913}})), hasLength(1));
    });
    test('여럿이면 배열', () {
      expect(tagoItems(_ok({'item': [{'a': 1}, {'a': 2}]})), hasLength(2));
    });
    test('키가 등록되지 않으면 예외', () {
      expect(
        () => tagoItems({
          'OpenAPI_ServiceResponse': {
            'cmmMsgHeader': {'errMsg': 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR', 'returnAuthMsg': '등록되지 않은 서비스키'},
          },
        }),
        throwsA(isA<TagoApiException>()),
      );
    });
    test('결과 코드가 00이 아니면 예외', () {
      expect(
        () => tagoItems({'response': {'header': {'resultCode': '22', 'resultMsg': 'LIMITED'}}}),
        throwsA(isA<TagoApiException>()),
      );
    });
  });

  group('parseNearbyStops', () {
    // 교원대 정문 앞에서 받은 응답 일부.
    final json = _ok({
      'item': [
        {'gpslati': 36.60817908, 'gpslong': 127.35814249, 'nodeid': 'CJB271000392', 'nodenm': '한국교원대학교', 'nodeno': 3334},
        {'gpslati': 36.60602179, 'gpslong': 127.35402937, 'nodeid': 'CJB271000424', 'nodenm': '한국교원대정문', 'nodeno': 2107},
        {'gpslati': 36.60698452, 'gpslong': 127.35358464, 'nodeid': 'CJB271000402', 'nodenm': '한국교원대정문', 'nodeno': 3333},
        {'gpslati': 36.70, 'gpslong': 127.40, 'nodeid': 'FAR', 'nodenm': '먼 정류장', 'nodeno': 1},
      ],
    });

    test('가까운 순으로, 1km 넘는 정류장은 뺀다', () {
      final stops = parseNearbyStops(json, userLat: 36.6069, userLng: 127.3536);
      expect(stops.map((s) => s.nodeId), ['CJB271000402', 'CJB271000424', 'CJB271000392']);
      expect(stops.first.distanceMeters, lessThan(30));
    });

    test('길 건너 같은 이름 정류장은 번호로 구분된다', () {
      final stops = parseNearbyStops(json, userLat: 36.6069, userLng: 127.3536);
      final gates = stops.where((s) => s.name == '한국교원대정문').map((s) => s.nodeNo).toSet();
      expect(gates, {'2107', '3333'});
    });
  });

  group('다른 도시 정류장이 겹친 곳(청주 터미널)', () {
    // 2026-11-12 실제 응답. 세종(12) 정류장이 청주(33010)와 같은 자리·같은 번호다.
    final json = _ok({
      'item': [
        {'citycode': 12, 'gpslati': 36.62611, 'gpslong': 127.43215, 'nodeid': 'SJB971007250', 'nodenm': '고속.시외터미널', 'nodeno': 2056},
        {'citycode': 33010, 'gpslati': 36.62603173, 'gpslong': 127.43217695, 'nodeid': 'CJB271000050', 'nodenm': '고속.시외버스터미널', 'nodeno': 2056},
        {'citycode': 33010, 'gpslati': 36.62557898, 'gpslong': 127.43152905, 'nodeid': 'CJB271000042', 'nodenm': '시외버스터미널', 'nodeno': 2055},
        {'citycode': 12, 'gpslati': 36.62553, 'gpslong': 127.43159, 'nodeid': 'SJB270050631', 'nodenm': '시외버스터미널', 'nodeno': 2055},
      ],
    });
    final stops = parseNearbyStops(json, userLat: 36.6265, userLng: 127.4317);

    test('같은 번호·같은 자리는 하나로, 대표는 청주 정류장', () {
      expect(stops, hasLength(2));
      final t = stops.firstWhere((s) => s.nodeNo == '2056');
      expect(t.nodeId, 'CJB271000050');
      expect(t.name, '고속.시외버스터미널');
    });

    test('도착 정보는 각자의 도시 코드로 묻는다', () {
      final t = stops.firstWhere((s) => s.nodeNo == '2056');
      expect(t.sources, [
        (cityCode: 33010, nodeId: 'CJB271000050'),
        (cityCode: 12, nodeId: 'SJB971007250'),
      ]);
    });

    test('번호가 다르면 가까워도 합치지 않는다(길 건너 정류장)', () {
      final s2 = parseNearbyStops(
        _ok({
          'item': [
            {'citycode': 33010, 'gpslati': 36.60602179, 'gpslong': 127.35402937, 'nodeid': 'A', 'nodenm': '한국교원대정문', 'nodeno': 2107},
            {'citycode': 33010, 'gpslati': 36.60612, 'gpslong': 127.35400, 'nodeid': 'B', 'nodenm': '한국교원대정문', 'nodeno': 3333},
          ],
        }),
        userLat: 36.606,
        userLng: 127.354,
      );
      expect(s2, hasLength(2));
    });
  });

  group('parseStopArrivals', () {
    test('빨리 오는 순, 남은 정거장·저상 여부', () {
      final list = parseStopArrivals(_ok({
        'item': [
          {'arrprevstationcnt': 8, 'arrtime': 593, 'routeno': 518, 'routetp': '지선버스', 'vehicletp': '저상버스'},
          {'arrprevstationcnt': 1, 'arrtime': 72, 'routeno': 913, 'routetp': '지선버스', 'vehicletp': '일반차량'},
          {'arrprevstationcnt': 12, 'arrtime': 900, 'routeno': '831-1', 'routetp': '간선버스'},
        ],
      }));
      expect(list.map((a) => a.routeNo), ['913', '518', '831-1']);
      expect(list.first.stopsAway, 1);
      expect(list.first.lowFloor, isFalse);
      expect(list[1].lowFloor, isTrue);
      expect(list[1].isAppRoute, isTrue);
      expect(list[2].isAppRoute, isFalse);
    });

    test('도착 시간이 없는 항목은 버린다', () {
      expect(parseStopArrivals(_ok({'item': {'routeno': 513}})), isEmpty);
    });
  });

  group('표시', () {
    test('받은 뒤 지난 시간을 빼고 센다', () {
      expect(formatArrivalIn(593, Duration.zero), '9분 후');
      expect(formatArrivalIn(593, const Duration(seconds: 120)), '7분 후');
      expect(formatArrivalIn(72, Duration.zero), '1분 후');
      expect(formatArrivalIn(72, const Duration(seconds: 20)), '곧 도착');
      expect(formatArrivalIn(30, const Duration(seconds: 60)), '곧 도착');
    });
    test('거리', () {
      expect(formatStopDistance(24), '20m');
      expect(formatStopDistance(126), '130m');
      expect(formatStopDistance(1240), '1.2km');
    });
    test('하버사인 거리 — 위도 0.001도는 약 111m', () {
      expect(distanceMeters(36.6, 127.35, 36.601, 127.35), closeTo(111, 1));
    });
  });
}
