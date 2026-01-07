import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bus_model.dart';

class BusService {
  static const String _serviceKey =
      "30cd0a0964f70dcbb2c274ae4bb9c44ba1d7ba81515c3c9d68f0e708664da513";
  static const String _baseUrl =
      "https://apis.data.go.kr/1613000/BusLcInfoInqireService/getRouteAcctoBusLcList";

  static const List<BusRouteConfig> _kRoutes = [
    // 1. 교원대 직행/순환
    BusRouteConfig(routeNumber: 513, routeId: "CJB270008000", isDirect: true),
    BusRouteConfig(routeNumber: 514, routeId: "CJB270008300", isDirect: true),
    BusRouteConfig(routeNumber: 518, routeId: "CJB270024700", isDirect: true),
    BusRouteConfig(routeNumber: 913, routeId: "CJB270014300", isDirect: true),

    // 2. 탑연삼거리 경유
    BusRouteConfig(routeNumber: 500, routeId: "CJB270005500", isDirect: false),
    BusRouteConfig(routeNumber: 502, routeId: "CJB270005700", isDirect: false),
    BusRouteConfig(routeNumber: 503, routeId: "CJB270005800", isDirect: false),
    BusRouteConfig(routeNumber: 509, routeId: "CJB270006400", isDirect: false),
    BusRouteConfig(routeNumber: 511, routeId: "CJB270006600", isDirect: false),
    BusRouteConfig(routeNumber: 747, routeId: "CJB270016400", isDirect: false),
  ];

  static const Map<int, int> _kTargetNodeOrdByRoute = {
    513: 43,
    514: 46,
    518: 34,
    500: 40,
    502: 42,
    503: 42,
    509: 38,
    511: 45,
    747: 15,
  };

  Future<List<BusSummary>> fetchAllBuses() async {
    try {
      final results = await Future.wait(_kRoutes.map(_fetchRouteRemaining));

      final summaries = results.map((r) {
        final config = _kRoutes.firstWhere(
          (e) => e.routeNumber == r.routeNumber,
        );
        final meta = _getRouteMeta(r.routeNumber, config.isDirect);

        final sorted = [...r.arrivals]..sort((a, b) => a.compareTo(b));

        return BusSummary(
          id: r.routeNumber,
          number: r.routeNumber.toString(),
          type: meta['type']!,
          direction: meta['direction']!,
          arrivals: sorted,
          congestion: 'normal',
          isDirect: config.isDirect,
        );
      }).toList();

      return summaries;
    } catch (e) {
      throw Exception("버스 정보 로드 실패: $e");
    }
  }

  Future<RouteRemaining> _fetchRouteRemaining(BusRouteConfig cfg) async {
    final uri = Uri.parse(
      "$_baseUrl?serviceKey=$_serviceKey&pageNo=1&numOfRows=100&_type=json&cityCode=33010&routeId=${cfg.routeId}",
    );

    try {
      final res = await http.get(uri, headers: {"Accept": "application/json"});
      if (res.statusCode != 200)
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final items = decoded["response"]?["body"]?["items"]?["item"];
      final List<dynamic> list = (items is List)
          ? items
          : (items != null ? [items] : []);

      final buses = list
          .whereType<Map>()
          .map((e) => BusLocation.fromJson(e.cast<String, dynamic>()))
          .toList();

      final List<BusArrival> arrivals = [];

      for (final b in buses) {
        int? remaining;

        if (cfg.routeNumber == 913) {
          if (b.nodeOrd <= 31) {
            remaining = 31 - b.nodeOrd;
          } else if (b.nodeOrd <= 46) {
            remaining = 46 - b.nodeOrd;
          }
        } else {
          final target = _kTargetNodeOrdByRoute[cfg.routeNumber] ?? 40;
          if (b.nodeOrd <= target) {
            remaining = target - b.nodeOrd;
          }
        }

        if (remaining != null) {
          arrivals.add(
            BusArrival(remainStops: remaining, currentStopName: b.nodeNm),
          );
        }
      }

      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: arrivals);
    } catch (e) {
      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
    }
  }

  Map<String, String> _getRouteMeta(int routeNumber, bool isDirect) {
    if (routeNumber == 747)
      return {'type': 'red', 'direction': isDirect ? '교원대행' : '오송/조치원'};
    // [수정] 509번 빨간색 처리
    if (routeNumber == 509) return {'type': 'red', 'direction': '조치원/오송'};
    if (routeNumber == 913) return {'type': 'green', 'direction': '교내 순환'};
    if (isDirect) return {'type': 'blue', 'direction': '교원대 정문행'};
    return {'type': 'blue', 'direction': '탑연삼거리 경유'};
  }
}