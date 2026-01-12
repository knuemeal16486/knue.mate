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

    // 2. 탑연삼거리 경유 (502번 등)
    BusRouteConfig(routeNumber: 500, routeId: "CJB270005500", isDirect: false),
    BusRouteConfig(routeNumber: 502, routeId: "CJB270007300", isDirect: false),
    BusRouteConfig(routeNumber: 503, routeId: "CJB270005800", isDirect: false),
    BusRouteConfig(routeNumber: 509, routeId: "CJB270006400", isDirect: false),
    BusRouteConfig(routeNumber: 511, routeId: "CJB270006600", isDirect: false),
    BusRouteConfig(routeNumber: 747, routeId: "CJB270016400", isDirect: false),
  ];

  // [수정됨] 각 노선별 '도착 기준 정류장'의 순번 (NodeOrd)
  // 직행 노선 -> '한국교원대학교' 정류장 기준
  // 경유 노선 -> '탑연삼거리' 정류장 기준
  static const Map<int, int> _kTargetNodeOrdByRoute = {
    // 교원대행 (한국교원대학교 정류장)
    513: 42,
    514: 45,
    518: 35,
    913: 31, // 교내 순환 타겟
    // 탑연삼거리 경유 (탑연삼거리 정류장)
    500: 45,
    502: 42,
    503: 51,
    509: 16,
    511: 47,
    747: 15, // 급행이라 정류장 수가 적음
  };

  // [수정됨] 노선별 예상 속도 계수 (분/정거장)
  // 도로 사정(고속화도로, 국도, 시골길)을 반영하여 오차 최소화
  static const Map<int, double> _routeSpeedFactor = {
    518: 1.6, // [매우 빠름] 오송역-교원대 직통 (고속화도로 위주)

    500: 1.8, // [빠름] 36번 국도 이용 (탑연삼거리 경유 노선들)
    502: 1.8,
    503: 1.8,
    509: 1.8,
    511: 1.8,
    747: 1.8,

    513: 2.3, // [보통] 미호동 등 마을 경유 (신호/정차 잦음)
    514: 2.3,

    913: 3.0, // [느림] 교내 순환 (서행 운전)
  };

  // 교통 혼잡도 시간대 가중치
  static const Map<int, double> _trafficTimeFactor = {
    7: 1.4, // 출근 (07-09)
    8: 1.5,
    9: 1.3,
    17: 1.3, // 퇴근 (17-19)
    18: 1.5,
    19: 1.3,
  };

  // 캐싱 변수
  static final Map<String, List<BusSummary>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 1); // 1분 캐시

  Future<List<BusSummary>> fetchAllBuses() async {
    final now = DateTime.now();
    final cacheKey = 'all_buses';

    // 캐시 유효성 체크
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && now.difference(timestamp) < _cacheDuration) {
        return _cache[cacheKey]!;
      }
    }

    try {
      // 모든 노선 병렬 요청
      final results = await Future.wait(_kRoutes.map(_fetchRouteRemaining));

      final summaries = results.map((r) {
        final config = _kRoutes.firstWhere(
          (e) => e.routeNumber == r.routeNumber,
        );
        final meta = _getRouteMeta(r.routeNumber, config.isDirect);

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

      // 결과 캐싱
      _cache[cacheKey] = summaries;
      _cacheTimestamps[cacheKey] = now;

      return summaries;
    } catch (e) {
      if (_cache.containsKey(cacheKey)) {
        print("API 실패, 캐시 데이터 반환");
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

        // 913번 교내 순환 처리
        if (cfg.routeNumber == 913) {
          if (b.nodeOrd <= 31) {
            remaining = 31 - b.nodeOrd;
          } else if (b.nodeOrd <= 46) {
            remaining = 46 - b.nodeOrd;
          }
        } else {
          // 일반 노선: 설정된 타겟 정류장(교원대 or 탑연삼거리) 기준 남은 정거장 계산
          final target = _kTargetNodeOrdByRoute[cfg.routeNumber] ?? 40;
          if (b.nodeOrd <= target) {
            remaining = target - b.nodeOrd;
          }
        }

        if (remaining != null && remaining >= 0) {
          // [개선됨] 예상 시간 계산 로직 적용
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
      print("버스 ${cfg.routeNumber} 조회 오류: $e");
      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
    }
  }

  // [핵심] 현실적인 도착 시간 계산 함수
  double _calculateEstimatedMinutes(
    int routeNumber,
    int remainStops,
    DateTime now,
  ) {
    if (remainStops <= 0) return 0.0;

    // 1. 노선별 기본 속도 적용 (고속화도로 vs 시내 vs 교내)
    double baseTimePerStop = _routeSpeedFactor[routeNumber] ?? 2.3;

    // 2. 시간대별 교통 혼잡도 반영
    double trafficFactor = _trafficTimeFactor[now.hour] ?? 1.0;

    // 3. 주말 여부 (주말엔 배차/속도 약간 느려짐)
    double dayFactor = (now.weekday >= 6) ? 1.1 : 1.0;

    // 4. 날씨/계절 (겨울/여름철 약간 지연)
    double weatherFactor = 1.0;
    if (now.month >= 12 || now.month <= 2) weatherFactor = 1.1; // 겨울
    if (now.month >= 7 && now.month <= 8) weatherFactor = 1.05; // 한여름

    // 5. [신규] 근접 보정: 정거장이 적게 남을수록 신호 대기 등으로 정거장 당 시간 증가
    double approachBuffer = 0.0;
    if (remainStops <= 3) {
      approachBuffer = 1.0; // 남은 정거장 3개 이하면 1분 추가 (신호 대기 고려)
    }

    // 최종 계산
    double estimatedMinutes =
        (remainStops *
            baseTimePerStop *
            trafficFactor *
            dayFactor *
            weatherFactor) +
        approachBuffer;

    return estimatedMinutes;
  }

  String _calculateCongestion(DateTime now, int routeNumber) {
    final h = now.hour;
    if (h >= 8 && h <= 9) return 'full'; // 아침 등교/출근 피크
    if (h >= 17 && h <= 18) return 'crowded'; // 저녁 퇴근
    if (h >= 21) return 'empty'; // 심야
    return 'normal';
  }

  Map<String, String> _getRouteMeta(int routeNumber, bool isDirect) {
    if (routeNumber == 747) return {'type': 'red', 'direction': '급행 (탑연 경유)'};
    if (routeNumber == 509) return {'type': 'red', 'direction': '조치원/오송'};
    if (routeNumber == 913) return {'type': 'green', 'direction': '교내 순환'};

    // 직행 vs 경유 표시 명확화
    if (isDirect) {
      return {'type': 'blue', 'direction': '교원대 정문행 (직행)'};
    } else {
      return {'type': 'blue', 'direction': '탑연삼거리 하차'};
    }
  }

  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
