import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bus_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BusService {
  // API 키를 .env에서 안전하게 가져오기
  static String get _serviceKey {
    final key = dotenv.env['BUS_API_KEY'];
    if (key == null || key.isEmpty) {
      print("⚠️ BUS_API_KEY가 .env 파일에 설정되지 않았습니다.");
      return "";
    }
    return key;
  }

  static const String _baseUrl =
      "https://apis.data.go.kr/1613000/BusLcInfoInqireService/getRouteAcctoBusLcList";

  static const List<BusRouteConfig> _kRoutes = [
    // 1. 교원대 직행/순환
    BusRouteConfig(routeNumber: 513, routeId: "CJB270008000", isDirect: true),
    BusRouteConfig(routeNumber: 514, routeId: "CJB270008300", isDirect: true),
    BusRouteConfig(routeNumber: 518, routeId: "CJB270024700", isDirect: true),
    BusRouteConfig(routeNumber: 913, routeId: "CJB270014300", isDirect: true),

    // 2. 탑연삼거리 경유 (502번 수정됨)
    BusRouteConfig(routeNumber: 500, routeId: "CJB270005500", isDirect: false),
    BusRouteConfig(
      routeNumber: 502,
      routeId: "CJB270007300",
      isDirect: false,
    ), // 수정됨
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
    502: 42, // 502번 타겟 정류장
    503: 42,
    509: 38,
    511: 45,
    747: 15,
    913: 31, // 913번 타겟 정류장
  };

  // 도착 시간 계산을 위한 상수 (분 단위)
  static const Map<int, double> _routeSpeedFactor = {
    513: 2.5, // 일반 도로
    514: 2.5,
    518: 1.8, // 고속도로 이용, 더 빠름
    500: 2.8, // 탑연삼거리 경유로 더 느림
    502: 2.8,
    503: 2.8,
    509: 2.8,
    511: 2.8,
    747: 2.5,
    913: 3.0, // 교내 순환, 더 느림
  };

  // 교통 혼잡도 시간대
  static const Map<int, double> _trafficTimeFactor = {
    7: 1.5, // 출근 시간 (7-9시)
    8: 1.5,
    9: 1.3,
    17: 1.5, // 퇴근 시간 (17-19시)
    18: 1.5,
    19: 1.3,
  };

  // 캐싱을 위한 변수
  static final Map<String, List<BusSummary>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 1);

  Future<List<BusSummary>> fetchAllBuses() async {
    final now = DateTime.now();
    final cacheKey = 'all_buses';

    // 캐시 확인
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && now.difference(timestamp) < _cacheDuration) {
        print("캐시된 버스 데이터 사용");
        return _cache[cacheKey]!;
      }
    }

    try {
      final results = await Future.wait(_kRoutes.map(_fetchRouteRemaining));

      final summaries = results.map((r) {
        final config = _kRoutes.firstWhere(
          (e) => e.routeNumber == r.routeNumber,
        );
        final meta = _getRouteMeta(r.routeNumber, config.isDirect);

        // 가장 가까운 버스만 선택 (추가된 기능)
        final closestBus = r.closestBus;
        final arrivals = closestBus != null ? [closestBus] : <BusArrival>[];

        return BusSummary(
          id: r.routeNumber,
          number: r.routeNumber.toString(),
          type: meta['type']!,
          direction: meta['direction']!,
          arrivals: arrivals,
          congestion: _calculateCongestion(now, r.routeNumber),
          isDirect: config.isDirect,
        );
      }).toList();

      // 캐시에 저장
      _cache[cacheKey] = summaries;
      _cacheTimestamps[cacheKey] = now;

      return summaries;
    } catch (e) {
      // 캐시된 데이터가 있으면 반환
      if (_cache.containsKey(cacheKey)) {
        print("API 실패, 캐시된 데이터 사용");
        return _cache[cacheKey]!;
      }
      print("버스 정보 로드 실패: $e");
      return [];
    }
  }

  Future<RouteRemaining> _fetchRouteRemaining(BusRouteConfig cfg) async {
    if (_serviceKey.isEmpty) {
      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
    }

    final uri = Uri.parse(
      "$_baseUrl?serviceKey=$_serviceKey&pageNo=1&numOfRows=100&_type=json&cityCode=33010&routeId=${cfg.routeId}",
    );

    try {
      final res = await http
          .get(uri, headers: {"Accept": "application/json"})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print("API 요청 실패 (${cfg.routeNumber}): ${res.statusCode}");
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final items = decoded["response"]?["body"]?["items"]?["item"];

      List<dynamic> list;
      if (items == null) {
        list = [];
      } else if (items is List) {
        list = items;
      } else {
        list = [items];
      }

      final buses = list
          .whereType<Map>()
          .map((e) => BusLocation.fromJson(e.cast<String, dynamic>()))
          .toList();

      final List<BusArrival> arrivals = [];

      for (final b in buses) {
        int? remaining;

        // 913번 버스 (교내 순환) 처리
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

        if (remaining != null && remaining >= 0) {
          // 현실적인 도착 시간 계산 (추가된 기능)
          final estimatedMinutes = _calculateEstimatedMinutes(
            cfg.routeNumber,
            remaining,
            DateTime.now(),
          );

          arrivals.add(
            BusArrival(
              remainStops: remaining,
              currentStopName: b.nodeNm,
              estimatedMinutes: estimatedMinutes,
            ),
          );
        }
      }

      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: arrivals);
    } catch (e) {
      print("버스 ${cfg.routeNumber}번 조회 실패: $e");
      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
    }
  }

  // 현실적인 도착 시간 계산 함수 (추가된 기능)
  double _calculateEstimatedMinutes(
    int routeNumber,
    int remainStops,
    DateTime now,
  ) {
    if (remainStops <= 0) return 0.0;

    // 기본 정거장 당 소요 시간
    double baseTimePerStop = _routeSpeedFactor[routeNumber] ?? 2.5;

    // 시간대별 교통 혼잡도 반영
    final hour = now.hour;
    double trafficFactor = _trafficTimeFactor[hour] ?? 1.0;

    // 주말 여부
    final weekday = now.weekday;
    double dayFactor = (weekday >= 6) ? 1.2 : 1.0; // 주말이면 20% 더 느림

    // 날씨/계절 요인 (간단한 모델)
    final month = now.month;
    double weatherFactor = 1.0;
    if (month == 12 || month == 1 || month == 2) {
      // 겨울
      weatherFactor = 1.15;
    } else if (month >= 6 && month <= 8) {
      // 여름/장마
      weatherFactor = 1.1;
    }

    // 예상 시간 계산
    double estimatedMinutes =
        remainStops *
        baseTimePerStop *
        trafficFactor *
        dayFactor *
        weatherFactor;

    // 추가 지연 시간 (신호대기, 승하차 등)
    estimatedMinutes += (remainStops * 0.5);

    return estimatedMinutes;
  }

  // 혼잡도 계산 함수 (추가된 기능)
  String _calculateCongestion(DateTime now, int routeNumber) {
    final hour = now.hour;
    final weekday = now.weekday;

    if (hour >= 7 && hour <= 9) {
      return 'crowded'; // 출근시간
    } else if (hour >= 17 && hour <= 19) {
      return 'crowded'; // 퇴근시간
    } else if (hour >= 21) {
      return 'empty'; // 심야
    } else if (weekday >= 6) {
      return 'normal'; // 주말
    } else {
      return 'normal'; // 평일 주간
    }
  }

  Map<String, String> _getRouteMeta(int routeNumber, bool isDirect) {
    if (routeNumber == 747)
      return {'type': 'red', 'direction': isDirect ? '교원대행' : '오송/조치원'};
    if (routeNumber == 509) return {'type': 'red', 'direction': '조치원/오송'};
    if (routeNumber == 913) return {'type': 'green', 'direction': '교내 순환'};
    if (isDirect) return {'type': 'blue', 'direction': '교원대 정문행'};
    return {'type': 'blue', 'direction': '탑연삼거리 경유'};
  }

  // 캐시 초기화
  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
