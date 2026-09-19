import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bus_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'offline_cache.dart';

class BusService {
  // API 키를 .env에서 안전하게 가져오기
  static String get _serviceKey {
    // 1) 빌드 타임 주입(권장): --dart-define=BUS_API_KEY=...
    const definedKey = String.fromEnvironment('BUS_API_KEY');
    final key = definedKey.isNotEmpty ? definedKey : dotenv.env['BUS_API_KEY'];
    if (key == null || key.isEmpty) {
      debugPrint("⚠️ BUS_API_KEY가 .env 파일에 설정되지 않았습니다.");
      return "";
    }
    return key;
  }

  /// 노선 정류장 목록(BusRouteInfoInqireService)용 키.
  ///
  /// 공공데이터포털은 서비스마다 따로 활용신청을 받기 때문에, 버스위치
  /// (BusLcInfoInqireService) 키와 노선정보 키가 서로 다를 수 있다. 실제로
  /// 두 키를 교차로 넣으면 "등록되지 않은 서비스키"가 떨어진다. 따로 안
  /// 넣었으면 같은 키로 폴백한다 — 한 키가 두 서비스에 모두 등록된 경우엔
  /// 그대로 동작한다.
  static String get _routeInfoKey {
    const definedKey = String.fromEnvironment('BUS_ROUTE_API_KEY');
    final key = definedKey.isNotEmpty
        ? definedKey
        : dotenv.env['BUS_ROUTE_API_KEY'];
    if (key != null && key.isNotEmpty) return key;
    return _serviceKey;
  }

  static const String _baseUrl =
      "https://apis.data.go.kr/1613000/BusLcInfoInqireService/getRouteAcctoBusLcList";

  /// ⚠️ routeId는 반드시 공공데이터포털 노선목록(getRouteNoList, cityCode=33010)에
  /// 실린 값과 대조하고 넣을 것. 2026-09-19 전수조사에서 10개 중 5개가 엉뚱한
  /// 노선을 가리키고 있었다 — 500→40-1(순환), 503→407, 509→416, 511→417,
  /// 747→872. 즉 앱이 "511번"이라고 띄우던 위치가 실제로는 417번 버스였다.
  /// 아래 값은 그때 API 응답으로 하나씩 확인해 바로잡은 것이다.
  static const List<BusRouteConfig> _kRoutes = [
    // 1. 교원대 직행/순환
    BusRouteConfig(routeNumber: 513, routeId: "CJB270008000", isDirect: true),
    BusRouteConfig(routeNumber: 514, routeId: "CJB270008300", isDirect: true),
    BusRouteConfig(routeNumber: 518, routeId: "CJB270024700", isDirect: true),
    BusRouteConfig(routeNumber: 913, routeId: "CJB270014300", isDirect: true),

    // 2. 탑연삼거리 경유
    BusRouteConfig(routeNumber: 500, routeId: "CJB270007100", isDirect: false),
    BusRouteConfig(routeNumber: 502, routeId: "CJB270007300", isDirect: false),
    BusRouteConfig(routeNumber: 503, routeId: "CJB270026400", isDirect: false),
    BusRouteConfig(routeNumber: 509, routeId: "CJB270026500", isDirect: false),
    BusRouteConfig(routeNumber: 511, routeId: "CJB270007500", isDirect: false),
    BusRouteConfig(routeNumber: 747, routeId: "CJB270011200", isDirect: false),
  ];

  /// 각 노선에서 "도착"의 기준이 되는 정류장 이름.
  /// 직행은 교원대 앞, 경유는 탑연삼거리에서 타고 내린다.
  static String _targetStopName(bool isDirect) =>
      isDirect ? "한국교원대학교" : "탑연삼거리";

  /// 이 노선에서 기준 정류장이 나오는 지점들(상행 1개 + 하행 1개).
  ///
  /// 정류장 목록 API가 응답하면 거기서 직접 뽑는다 — 노선이 개정돼도
  /// 앱이 알아서 따라가고, 하드코딩 값이 낡아서 엉뚱한 정류장을 도착지로
  /// 잡는 일이 없다. 실패하면 검증해둔 [_kTargetNodeOrdByRoute]로 폴백.
  static Future<List<TargetStopOrd>> _resolveTargetOrds(
    BusRouteConfig cfg,
  ) async {
    try {
      final stops = await fetchRouteStops(cfg.routeId);
      final derived = targetOrdsFromStops(
        stops,
        _targetStopName(cfg.isDirect),
      );
      if (derived.isNotEmpty) return derived;
    } catch (e) {
      debugPrint("BusService: ${cfg.routeNumber}번 기준 정류장 계산 실패: $e");
    }
    return targetOrdsFromFallback(_kTargetNodeOrdByRoute[cfg.routeNumber]);
  }

  /// 기준 정류장의 nodeOrd — **상행/하행 두 번 다** 적는다.
  ///
  /// 왕복 노선은 정류장 순서가 상행·하행을 하나로 이어 붙인 형태라 기준
  /// 정류장이 목록에 두 번 나온다. 예전엔 상행 것 하나만 적어두고 "남은
  /// 정거장 = 기준 - 현재"가 음수면 하행으로 간주했는데, 그러면 **돌아오는
  /// 길에 우리 정류장으로 다가오는 버스가 전부 "이미 지나간 차"로 버려졌다**
  /// (하행 카드에 도착 예정 시간이 아예 없던 이유).
  ///
  /// 이 표는 [fetchRouteStops]가 실패했을 때 쓰는 폴백이다. 정상적으로는
  /// [_resolveTargetOrds]가 매번 API에서 직접 계산하므로 노선이 개정돼도
  /// 알아서 따라간다. 값은 2026-09-19 API 응답 기준.
  static const Map<int, List<int>> _kTargetNodeOrdByRoute = {
    // 교원대행 — [상행, 하행]
    513: [43, 44],
    514: [46, 47],
    518: [1, 36], // 교원대에서 출발해 교원대로 돌아오는 셔틀
    913: [32, 47],
    // 탑연삼거리 경유 — [상행, 하행]
    500: [45, 66],
    502: [42, 79],
    503: [51, 76],
    509: [16, 23],
    511: [47, 82],
    747: [15, 18], // 급행이라 정류장 수가 적음
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
  static DateTime? _lastFirebaseUpdateTime; // 마지막 파이어베이스 업데이트 시간

  // 노선별 정류장 캐시 (세션 내 유지)
  static final Map<String, List<RouteStop>> _routeStopsCache = {};

  /// 설정 문제(예: BUS_API_KEY 누락)를 UI에서 에러로 구분하기 위한 예외
  static StateError missingApiKeyError() =>
      StateError('BUS_API_KEY가 설정되어 있지 않습니다. (--dart-define 또는 .env 설정 필요)');

  /// 노선 ID로 노선번호 매핑 (BusCard에서 사용)
  static String? getRouteId(int routeNumber) {
    try {
      return _kRoutes.firstWhere((r) => r.routeNumber == routeNumber).routeId;
    } catch (_) {
      return null;
    }
  }

  Future<List<BusSummary>> fetchAllBuses() async {
    final now = DateTime.now();
    final cacheKey = 'all_buses';
    List<BusSummary>? firebaseCached;

    // 0. 오프라인 캐시 먼저 확인
    final offline = await OfflineCache.load();
    if (offline != null) {
      debugPrint('🗂️ Offline cache 사용 (최근 5분)');
      return offline;
    }

    // 1. 로컬 메모리 캐시 먼저 확인 (가장 빠름)
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      // 메모리 캐시는 매우 짧게 유지 (15초)
      if (timestamp != null &&
          now.difference(timestamp) < const Duration(seconds: 15)) {
        return _cache[cacheKey]!;
      }
    }

    // 2. 파이어베이스 캐시 확인 (공유 데이터)
    try {
      final fbDoc = await FirebaseFirestore.instance
          .collection('realtime')
          .doc('bus_locations')
          .get(const GetOptions(source: Source.serverAndCache)) // 캐시 우선 확인
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => throw TimeoutException('Firestore get timeout'),
          );

      if (fbDoc.exists) {
        final data = fbDoc.data();
        final Timestamp? lastUpdated = data?['lastUpdated'];
        final dynamic summariesRaw = data?['summaries'];
        if (summariesRaw is List) {
          firebaseCached = summariesRaw
              .whereType<Map>()
              .map((e) => BusSummary.fromJson(e.cast<String, dynamic>()))
              .toList();
        }

        if (lastUpdated != null && firebaseCached != null) {
          final diff = now.difference(lastUpdated.toDate());

          // [개선] 캐시 유효 시간을 45초로 연장하고, 클라이언트별 지터(Random) 추가
          // 여러 사용자가 동시에 API를 호출하는 현상 방지
          final int threshold = 45 + (now.millisecond % 15);

          if (diff.inSeconds < threshold) {
            // 메모리 캐시 업데이트
            _cache[cacheKey] = firebaseCached;
            _cacheTimestamps[cacheKey] = now;

            debugPrint("BusService: 파이어베이스 캐시 히트 (${diff.inSeconds}초 전)");
            return firebaseCached;
          }
        }
      }
    } catch (e) {
      debugPrint("BusService: 파이어베이스 확인 실패: $e");
    }

    try {
      // 2.5) API 키가 없으면 빈 결과를 정상으로 취급하지 않음
      if (_serviceKey.isEmpty) {
        if (firebaseCached != null) return firebaseCached;
        throw missingApiKeyError();
      }

      // 3. API 호출 (실제 전국버스 API 사용)
      // [개선] 개별 요청 타임아웃 단축 (10s -> 5s) 및 병렬 실행
      final results = await Future.wait(
        _kRoutes.map(
          (cfg) => _fetchRouteRemaining(cfg).timeout(
            const Duration(seconds: 12), // 전체 병렬 작업에 대한 약간 긴 타임아웃
            onTimeout: () =>
                RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []),
          ),
        ),
      );

      final List<Map<String, dynamic>> summariesJson = [];
      int totalArrivals = 0;
      for (final r in results) {
        final config = _kRoutes.firstWhere(
          (e) => e.routeNumber == r.routeNumber,
        );
        final meta = _getRouteMeta(r.routeNumber, config.isDirect);
        // 다음 도착 차량의 실시간 혼잡도가 있으면 그것을 쓰고, 없을 때만 시간대 추정치로 폴백.
        // ⚠️ 국토교통부 버스위치정보 API(getRouteAcctoBusLcList)는 혼잡도 필드를
        // 응답 자체에 포함하지 않는다 — 노선을 가리지 않고 항상 그렇다. 그래서
        // realCongestion은 사실상 항상 null이고, 아래 값은 사실상 항상 추정치다.
        final realCongestion = congestionLevelLabel(
          _nextArrival(r.arrivals)?.congestion,
        );

        final summary = BusSummary(
          id: r.routeNumber,
          number: r.routeNumber.toString(),
          type: meta['type']!,
          direction: meta['direction']!,
          arrivals: r.arrivals,
          congestion: realCongestion ?? _calculateCongestion(now, r.routeNumber),
          isDirect: config.isDirect,
          isCongestionEstimated: realCongestion == null,
        );
        totalArrivals += r.arrivals.length;
        summariesJson.add(summary.toJson());
      }

      final summaryList = summariesJson
          .map((e) => BusSummary.fromJson(e))
          .toList();

      // 도착 알림 로그
      for (final summary in summaryList) {
        final next = summary.nextArrival;
        if (next != null && next.estimatedMinutes > 0 && next.estimatedMinutes <= 5) {
          final topic = 'bus_${summary.number}';
          debugPrint('🔔 알림: ${summary.number}번 버스 ${next.estimatedMinutes.round()}분 내 도착 (topic: $topic)');
        }
      }

      // 4. 결과 파이어베이스에 업데이트
      // 전 노선이 모두 0대이고 Firebase 캐시도 없으면,
      // 설정/응답 오류 가능성이 높아 '빈 값 덮어쓰기'를 방지
      final bool looksLikeFailure = totalArrivals == 0 && firebaseCached == null;
      if (!looksLikeFailure) {
        // 마지막 업데이트 후 30초 경과 시에만 업데이트 수행
        if (_lastFirebaseUpdateTime == null ||
            now.difference(_lastFirebaseUpdateTime!) >
                const Duration(seconds: 30)) {
          _lastFirebaseUpdateTime = now;
          FirebaseFirestore.instance
              .collection('realtime')
              .doc('bus_locations')
              .set({
                'lastUpdated': FieldValue.serverTimestamp(),
                'summaries': summariesJson,
              })
              .catchError(
                (e) => debugPrint("BusService: 파이어베이스 업데이트 실패: $e"),
              );
        }
      } else {
        debugPrint(
          "BusService: 전체 결과가 비어 Firestore 업데이트를 건너뜁니다(설정/응답 오류 가능).",
        );
      }

      // 5. 로컬 메모리 캐싱
      _cache[cacheKey] = summaryList;
      _cacheTimestamps[cacheKey] = now;

      // 오프라인 캐시 저장
      await OfflineCache.save(summaryList);

      return summaryList;
    } catch (e) {
      debugPrint("BusService: 전체 버스 정보 로드 실패: $e");
      return firebaseCached ?? _cache[cacheKey] ?? [];
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
          .timeout(const Duration(seconds: 10)); // 개별 API 타임아웃 연장

      if (res.statusCode != 200) {
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      
      final dynamic response = decoded["response"];
      if (response == null || response is! Map) {
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      }
      
      final dynamic bodyObj = response["body"];
      if (bodyObj == null || bodyObj is! Map) {
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      }
      
      final dynamic itemsObj = bodyObj["items"];
      if (itemsObj == null || itemsObj is! Map) {
        return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
      }
      
      final dynamic items = itemsObj["item"];

      List<dynamic> list;
      if (items == null) {
        list = [];
      } else if (items is List) {
        list = items;
      } else {
        list = [items];
      }

      final targets = await _resolveTargetOrds(cfg);

      final arrivals = list.whereType<Map>().map((e) {
        final b = BusLocation.fromJson(e.cast<String, dynamic>());
        // 이 차가 "다음에" 닿을 기준 정류장을 찾는다. 상행 지점을 이미
        // 지났어도 돌아오는 길의 하행 지점이 남아 있으면 그쪽으로 잡히므로,
        // 예전처럼 음수(=버려짐)가 나오지 않는다.
        final next = nextTargetFor(b.nodeOrd, targets);
        if (next == null) return null; // 이번 운행에선 우리 정류장을 다 지났다

        final int remaining = next.ord - b.nodeOrd;

        return BusArrival(
          remainStops: remaining,
          currentStopName: b.nodeNm,
          direction: next.dir,
          estimatedMinutes: _calculateEstimatedMinutes(
            cfg.routeNumber,
            remaining,
            DateTime.now(),
            busCongestion: b.congestion,
          ),
          latitude: b.latitude,
          longitude: b.longitude,
          vehicleNo: b.vehicleno,
          nodeOrd: b.nodeOrd,
          congestion: b.congestion,
        );
      }).whereType<BusArrival>().toList();

      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: arrivals);
    } catch (e) {
      debugPrint("BusService: 버스 ${cfg.routeNumber} 조회 오류: $e");
      return RouteRemaining(routeNumber: cfg.routeNumber, arrivals: []);
    }
  }

  // [핵심] 현실적인 도착 시간 계산 함수
  double _calculateEstimatedMinutes(
    int routeNumber,
    int remainStops,
    DateTime now, {
    int? busCongestion,
  }) {
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

    // 6. [신규] 실시간 버스 혼잡도 반영 (승하차 시간 증가)
    double busFactor = 1.0;
    if (busCongestion == 3) busFactor = 1.15; // 혼잡
    if (busCongestion == 4) busFactor = 1.3; // 매우 혼잡

    // 최종 계산
    double estimatedMinutes =
        (remainStops *
            baseTimePerStop *
            trafficFactor *
            busFactor *
            dayFactor *
            weatherFactor) +
        approachBuffer;

    return estimatedMinutes;
  }

  /// 가장 먼저 도착하는 차량. 이제 remainStops가 항상 0 이상이라
  /// (상행이든 하행이든 "다음에 닿을 기준 정류장까지의 거리") 부호를 따질
  /// 필요 없이 제일 가까운 차를 그대로 고르면 된다.
  BusArrival? _nextArrival(List<BusArrival> arrivals) {
    if (arrivals.isEmpty) return null;
    return arrivals.reduce((a, b) => a.remainStops <= b.remainStops ? a : b);
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
    // 913은 교내 셔틀이 아니다. 2024-08-10 개정으로 평동↔미호종점 노선이 됐고
    // 교원대는 그 사이를 지나는 경유지다. '교내 순환'은 잘못된 표기였다.
    if (routeNumber == 913) {
      return {'type': 'green', 'direction': '평동↔미호종점'};
    }

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
    _routeStopsCache.clear();
  }

  /// 노선별 경유 정류장 목록 조회 (API: getRouteAcctoThrghSttnList)
  /// 세션 내 캐시하여 중복 호출 방지
  static Future<List<RouteStop>> fetchRouteStops(String routeId) async {
    // 1. 캐시 확인
    if (_routeStopsCache.containsKey(routeId)) {
      return _routeStopsCache[routeId]!;
    }

    // 2. API 호출 — 이 엔드포인트는 버스위치와 다른 서비스라 키가 따로다.
    final key = _routeInfoKey;
    if (key.isEmpty) {
      debugPrint("BusService: API 키 누락으로 정류장 조회를 건너뜁니다 ($routeId)");
      return [];
    }

    // numOfRows=200은 511(129개)엔 충분하지만 여유를 둔다 — 정류장이 잘리면
    // 하행 기준 정류장이 목록에서 빠져 도착 계산이 조용히 틀어진다.
    final uri = Uri.parse(
      "https://apis.data.go.kr/1613000/BusRouteInfoInqireService/getRouteAcctoThrghSttnList"
      "?serviceKey=$key&pageNo=1&numOfRows=300&_type=json&cityCode=33010&routeId=$routeId",
    );

    try {
      final res = await http
          .get(uri, headers: {"Accept": "application/json"})
          .timeout(const Duration(seconds: 5)); // 10s -> 5s로 단축 (사용자 체감 성능 향상)

      if (res.statusCode != 200) {
        debugPrint("BusService: API 응답 오류 (${res.statusCode}) - $routeId");
        return [];
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return [];
      
      final dynamic response = decoded["response"];
      if (response == null || response is! Map) return [];
      
      final dynamic bodyObj = response["body"];
      if (bodyObj == null || bodyObj is! Map) return [];
      
      final dynamic itemsObj = bodyObj["items"];
      if (itemsObj == null || itemsObj is! Map) return [];
      
      final dynamic items = itemsObj["item"];

      List<dynamic> list;
      if (items == null) {
        list = [];
      } else if (items is List) {
        list = items;
      } else {
        list = [items];
      }

      final stops = list
          .whereType<Map>()
          .map((e) => RouteStop.fromJson(e.cast<String, dynamic>()))
          .toList();

      // 정류장 순서대로 정렬
      stops.sort((a, b) => a.nodeOrd.compareTo(b.nodeOrd));

      // 3. 캐시 저장
      _routeStopsCache[routeId] = stops;
      debugPrint("BusService: $routeId 노선 정류장 ${stops.length}개 로드 완료");

      return stops;
    } on TimeoutException {
      debugPrint("BusService: 노선 정류장 조회 타임아웃 ($routeId)");
      return [];
    } catch (e) {
      debugPrint("BusService: 노선 정류장 조회 실패 ($routeId): $e");
      return [];
    }
  }

  /// 교통 상황 추정 ("smooth", "slow", "congested")
  static String estimateTrafficCondition(DateTime now) {
    final h = now.hour;
    // 출퇴근 시간대
    if ((h >= 7 && h <= 9) || (h >= 17 && h <= 19)) return "slow";
    // 준 혈잡 시간대
    if (h >= 12 && h <= 14) return "moderate";
    // 심야 / 이른 아침
    if (h >= 22 || h < 6) return "smooth";
    return "smooth";
  }

}
