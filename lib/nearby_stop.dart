// 내 위치에서 가장 가까운 버스 정류장과 그 정류장의 실시간 도착 정보(2026-11-12).
//
// 버스 탭의 노선 카드는 차량 위치(BusLcInfoInqireService)로 "교원대·탑연삼거리까지
// 몇 정거장"을 어림한다. 이 파일은 다른 길을 쓴다 — 국토교통부(TAGO)의
//   - 정류소정보 getCrdntPrxmtSttnList: 좌표 → 근처 정류장
//   - 도착정보   getSttnAcctoArvlPrearngeInfoList: 정류장 → 오는 버스·도착 예정(초)
// 둘 다 이미 앱에 들어 있는 BUS_API_KEY로 된다(2026-11-12 확인).
//
// 정류장은 같은 이름이 **길 양쪽에 하나씩** 있다(한국교원대정문 2107·3333). 방향이
// 다르니 정류장 번호(nodeno, 정류장 표지판의 번호)를 같이 보여 준다.
//
// ⚠️ 도시 코드는 정류장마다 다르다. 청주 터미널 같은 곳엔 세종시(citycode 12)
// 정류장이 청주 정류장과 **같은 자리·같은 번호**로 겹쳐 있고, 세종 정류장을
// 청주 코드(33010)로 물으면 빈 결과가 온다(2026-11-12 실측). 그래서 같은 번호·
// 같은 자리의 정류장은 하나로 합치고([NearbyStop.sources]) 도착 정보는 각자의
// 도시 코드로 물어 합친다.
//
// 학교 서버가 아니라 공공데이터포털로 가는 요청이다. 기기마다 부르지만 화면이
// 열려 있을 때만, 같은 정류장은 [kNearbyArrivalMinGap]보다 자주 받지 않는다.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 청주시 도시 코드(TAGO).
const int kCheongjuCityCode = 33010;

/// 이 거리 안의 정류장만 "가까운 정류장"으로 친다.
const double kNearbyStopMaxMeters = 1000;

/// 고를 수 있게 보여 줄 정류장 수.
const int kNearbyStopChoices = 4;

/// 같은 정류장 도착 정보를 다시 받는 최소 간격.
const Duration kNearbyArrivalMinGap = Duration(seconds: 20);

/// 이만큼 움직이지 않았으면 근처 정류장을 다시 찾지 않는다.
const double kNearbyRelocateMeters = 100;

/// 앱이 다루는 노선(버스 탭 노선 카드). 도착 목록에서 표시해 준다.
const Set<String> kAppBusRoutes = {
  '513', '514', '518', '913', '500', '502', '503', '509', '511', '747',
};

/// 정류장 하나를 TAGO에 물을 때 쓰는 값.
typedef StopSource = ({int cityCode, String nodeId});

class NearbyStop {
  /// 대표 정류장 id(청주 것이 있으면 그것). 고른 정류장을 기억하는 데 쓴다.
  final String nodeId;
  final String name;

  /// 같은 자리·같은 번호로 겹친 정류장들(도시가 다르다). 도착 정보는 전부 물어 합친다.
  final List<StopSource> sources;

  /// 정류장 표지판의 번호. 같은 이름의 길 건너 정류장과 구분한다.
  final String? nodeNo;
  final double latitude;
  final double longitude;

  /// 내 위치에서의 직선거리(m).
  final double distanceMeters;

  const NearbyStop({
    required this.nodeId,
    required this.name,
    required this.sources,
    required this.nodeNo,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });
}

class StopArrival {
  final String routeNo;

  /// 노선 id(CJB…). 버스 탭 노선 카드에 붙일 때 노선 번호보다 확실하다.
  final String? routeId;
  final String? routeType;

  /// 도착까지 남은 정거장 수.
  final int? stopsAway;

  /// 도착 예정까지 남은 시간(초). API가 계산한 값이다.
  final int arrivalSeconds;
  final bool lowFloor;

  const StopArrival({
    required this.routeNo,
    this.routeId,
    required this.routeType,
    required this.stopsAway,
    required this.arrivalSeconds,
    required this.lowFloor,
  });

  bool get isAppRoute => kAppBusRoutes.contains(routeNo);
}

/// 두 좌표 사이 직선거리(m, 하버사인). 순수 함수 — 테스트 대상.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// TAGO 응답의 item 목록. 결과가 하나면 배열이 아니라 객체로, 없으면 빈
/// 문자열("")로 온다. 순수 함수 — 테스트 대상.
List<Map<String, dynamic>> tagoItems(Map<String, dynamic> json) {
  final response = json['response'];
  if (response is! Map) {
    // 키 오류 등은 OpenAPI_ServiceResponse로 온다.
    throw TagoApiException(_tagoErrorMessage(json) ?? '알 수 없는 응답');
  }
  final header = response['header'];
  if (header is Map && header['resultCode'] != '00') {
    throw TagoApiException('${header['resultCode']} ${header['resultMsg']}');
  }
  final items = (response['body'] as Map?)?['items'];
  if (items is! Map) return const [];
  final item = items['item'];
  if (item is Map) return [item.cast<String, dynamic>()];
  if (item is List) {
    return [for (final e in item) if (e is Map) e.cast<String, dynamic>()];
  }
  return const [];
}

String? _tagoErrorMessage(Map<String, dynamic> json) {
  final r = json['OpenAPI_ServiceResponse'];
  if (r is! Map) return null;
  final h = r['cmmMsgHeader'];
  if (h is! Map) return null;
  return '${h['returnAuthMsg'] ?? h['errMsg']}';
}

class TagoApiException implements Exception {
  final String message;
  TagoApiException(this.message);
  @override
  String toString() => 'TagoApiException: $message';
}

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

/// 같은 정류장으로 합칠 거리. 길 건너 정류장(약 30m 이상, 번호도 다르다)과
/// 섞이지 않게 번호가 같을 때만 합친다.
const double _kSameStopMeters = 40;

/// 근처 정류장 응답 → 가까운 순. [kNearbyStopMaxMeters]보다 먼 것은 빼고,
/// 같은 번호·같은 자리로 겹친 다른 도시 정류장은 하나로 합친다(청주 이름을
/// 쓴다). 순수 함수 — 테스트 대상.
List<NearbyStop> parseNearbyStops(
  Map<String, dynamic> json, {
  required double userLat,
  required double userLng,
}) {
  final raw = <(NearbyStop, int)>[];
  for (final e in tagoItems(json)) {
    final lat = _num(e['gpslati']);
    final lng = _num(e['gpslong']);
    final id = e['nodeid']?.toString();
    final name = e['nodenm']?.toString().trim();
    if (lat == null || lng == null || id == null || name == null || name.isEmpty) {
      continue;
    }
    final d = distanceMeters(userLat, userLng, lat, lng);
    if (d > kNearbyStopMaxMeters) continue;
    final city = _num(e['citycode'])?.round() ?? kCheongjuCityCode;
    raw.add((
      NearbyStop(
        nodeId: id,
        name: name,
        sources: [(cityCode: city, nodeId: id)],
        nodeNo: e['nodeno']?.toString(),
        latitude: lat,
        longitude: lng,
        distanceMeters: d,
      ),
      city,
    ));
  }
  // 청주 정류장을 먼저 두어 합칠 때 대표가 되게 한다.
  raw.sort((a, b) {
    final ac = a.$2 == kCheongjuCityCode ? 0 : 1;
    final bc = b.$2 == kCheongjuCityCode ? 0 : 1;
    if (ac != bc) return ac - bc;
    return a.$1.distanceMeters.compareTo(b.$1.distanceMeters);
  });

  final out = <NearbyStop>[];
  for (final (stop, _) in raw) {
    final i = out.indexWhere((o) =>
        stop.nodeNo != null &&
        o.nodeNo == stop.nodeNo &&
        distanceMeters(o.latitude, o.longitude, stop.latitude, stop.longitude) < _kSameStopMeters);
    if (i < 0) {
      out.add(stop);
      continue;
    }
    final o = out[i];
    out[i] = NearbyStop(
      nodeId: o.nodeId,
      name: o.name,
      sources: [...o.sources, ...stop.sources],
      nodeNo: o.nodeNo,
      latitude: o.latitude,
      longitude: o.longitude,
      distanceMeters: math.min(o.distanceMeters, stop.distanceMeters),
    );
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
}

/// 도착 정보 응답 → 빨리 오는 순. 같은 노선 차가 여럿이면 다 둔다.
/// 순수 함수 — 테스트 대상.
List<StopArrival> parseStopArrivals(Map<String, dynamic> json) {
  final out = <StopArrival>[];
  for (final e in tagoItems(json)) {
    final routeNo = e['routeno']?.toString().trim();
    final sec = _num(e['arrtime']);
    if (routeNo == null || routeNo.isEmpty || sec == null) continue;
    out.add(StopArrival(
      routeNo: routeNo,
      routeId: e['routeid']?.toString(),
      routeType: e['routetp']?.toString(),
      stopsAway: _num(e['arrprevstationcnt'])?.round(),
      arrivalSeconds: sec.round(),
      lowFloor: e['vehicletp']?.toString().contains('저상') ?? false,
    ));
  }
  out.sort((a, b) => a.arrivalSeconds.compareTo(b.arrivalSeconds));
  return out;
}

/// 받은 뒤 [elapsed]가 지났을 때 남은 시간 표시. 순수 함수 — 테스트 대상.
String formatArrivalIn(int arrivalSeconds, Duration elapsed) {
  final left = arrivalSeconds - elapsed.inSeconds;
  if (left < 60) return '곧 도착';
  return '${(left / 60).floor()}분 후';
}

/// 거리 표시("120m", "1.2km"). 순수 함수 — 테스트 대상.
String formatStopDistance(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

/// 근처 정류장·도착 정보를 받는다. 결과는 메모리에만 둔다.
class NearbyStopService {
  NearbyStopService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _base = 'https://apis.data.go.kr/1613000';
  static const _timeout = Duration(seconds: 6);

  final Map<String, (DateTime, List<StopArrival>)> _arrivalCache = {};
  (double, double, List<NearbyStop>)? _lastStops;

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    if (apiKey.isEmpty) throw TagoApiException('BUS_API_KEY 없음');
    final uri = Uri.parse('$_base/$path').replace(queryParameters: {
      'serviceKey': apiKey,
      '_type': 'json',
      ...query,
    });
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) throw TagoApiException('HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map) throw TagoApiException('JSON 아님');
    return body.cast<String, dynamic>();
  }

  /// 가까운 정류장들. 지난번 위치에서 [kNearbyRelocateMeters] 안이면 다시
  /// 묻지 않는다.
  Future<List<NearbyStop>> nearbyStops(double lat, double lng) async {
    final last = _lastStops;
    if (last != null &&
        distanceMeters(last.$1, last.$2, lat, lng) < kNearbyRelocateMeters) {
      return last.$3;
    }
    final json = await _get('BusSttnInfoInqireService/getCrdntPrxmtSttnList', {
      'gpsLati': '$lat',
      'gpsLong': '$lng',
      'numOfRows': '30',
    });
    final stops = parseNearbyStops(json, userLat: lat, userLng: lng);
    _lastStops = (lat, lng, stops);
    return stops;
  }

  /// 정류장에 오는 버스. 겹친 정류장([NearbyStop.sources])은 각자의 도시 코드로
  /// 물어 합친다. [force]가 아니면 [kNearbyArrivalMinGap] 안에서는 지난 값을
  /// 준다. 돌려주는 시각은 그 값을 받은 때다.
  Future<(DateTime, List<StopArrival>)> arrivals(NearbyStop stop, {bool force = false}) async {
    final cached = _arrivalCache[stop.nodeId];
    final now = DateTime.now();
    if (!force && cached != null && now.difference(cached.$1) < kNearbyArrivalMinGap) {
      return cached;
    }
    final lists = await Future.wait([
      for (final src in stop.sources)
        _get('ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList', {
          'cityCode': '${src.cityCode}',
          'nodeId': src.nodeId,
          'numOfRows': '100',
        }).then(parseStopArrivals),
    ]);
    final merged = [for (final l in lists) ...l]
      ..sort((a, b) => a.arrivalSeconds.compareTo(b.arrivalSeconds));
    final result = (now, merged);
    _arrivalCache[stop.nodeId] = result;
    return result;
  }

  void dispose() {
    try {
      _client.close();
    } catch (e) {
      debugPrint('NearbyStopService.dispose: $e');
    }
  }
}
