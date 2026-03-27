import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bus_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_sync_service.dart';

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

        final summary = BusSummary(
          id: r.routeNumber,
          number: r.routeNumber.toString(),
          type: meta['type']!,
          direction: meta['direction']!,
          arrivals: r.arrivals,
          congestion: _calculateCongestion(now, r.routeNumber),
          isDirect: config.isDirect,
        );
        totalArrivals += r.arrivals.length;
        summariesJson.add(summary.toJson());
      }

      final summaryList = summariesJson
          .map((e) => BusSummary.fromJson(e))
          .toList();

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

      final arrivals = list.whereType<Map>().map((e) {
        final b = BusLocation.fromJson(e.cast<String, dynamic>());
        // 남은 정거장 계산 (타겟 정류장 기준)
        final target = _kTargetNodeOrdByRoute[cfg.routeNumber] ?? 40;
        final int remaining = target - b.nodeOrd;

        return BusArrival(
          remainStops: remaining,
          currentStopName: b.nodeNm,
          estimatedMinutes: remaining >= 0
              ? _calculateEstimatedMinutes(
                  cfg.routeNumber,
                  remaining,
                  DateTime.now(),
                  busCongestion: b.congestion,
                )
              : 0.0,
          latitude: b.latitude,
          longitude: b.longitude,
          vehicleNo: b.vehicleno,
          nodeOrd: b.nodeOrd,
          congestion: b.congestion,
        );
      }).toList();

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
    _routeStopsCache.clear();
  }

  /// 노선별 경유 정류장 목록 조회 (API: getRouteAcctoThrghSttnList)
  /// 세션 내 캐시하여 중복 호출 방지
  static Future<List<RouteStop>> fetchRouteStops(String routeId) async {
    // 1. 캐시 확인
    if (_routeStopsCache.containsKey(routeId)) {
      return _routeStopsCache[routeId]!;
    }

    // 2. API 호출
    final key = _serviceKey;
    if (key.isEmpty) {
      debugPrint("BusService: API 키 누락으로 정류장 조회를 건너뜁니다 ($routeId)");
      return [];
    }

    final uri = Uri.parse(
      "https://apis.data.go.kr/1613000/BusRouteInfoInqireService/getRouteAcctoThrghSttnList"
      "?serviceKey=$key&pageNo=1&numOfRows=200&_type=json&cityCode=33010&routeId=$routeId",
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

  /// 노선별 현재 혼잡도 반환
  static String estimateCongestion(DateTime now, int routeNumber) {
    final h = now.hour;
    // 교원대 노선 특성: 아침 등교 시간이 가장 혼잡
    if (h >= 8 && h <= 9) {
      if ([513, 514, 913].contains(routeNumber)) return "crowded";
      return "normal";
    }
    // 저녁 퇴근
    if (h >= 17 && h <= 18) {
      if ([513, 514].contains(routeNumber)) return "crowded";
      return "normal";
    }
    // 심야
    if (h >= 21) return "empty";
    return "normal";
  }

  // ==================== Firebase 연동 시간표 메서드 ====================

  /// 시간표 캐시
  static final Map<String, List<BusTimetable>> _timetableCache = {};
  static DateTime? _lastTimetableFetchTime;

  /// [Firebase] 시간표 가져오기 (Firebase 우선, 실패 시 로컬 반환)
  static Future<Map<String, List<BusTimetable>>>
  fetchTimetablesFromFirebase() async {
    final now = DateTime.now();

    // 캐시 확인 (5분 유효)
    if (_timetableCache.isNotEmpty &&
        _lastTimetableFetchTime != null &&
        now.difference(_lastTimetableFetchTime!) < const Duration(minutes: 5)) {
      return _timetableCache;
    }

    try {
      final timetables = await FirebaseSyncService.fetchAllBusTimetables();

      if (timetables.isNotEmpty) {
        _timetableCache.clear();
        _timetableCache.addAll(timetables);
        _lastTimetableFetchTime = now;
        debugPrint(
          'BusService: Firebase에서 시간표 로드 완료 (${timetables.length}개 노선)',
        );
        return timetables;
      }
    } catch (e) {
      debugPrint('BusService: Firebase 시간표 로드 실패: $e');
    }

    // Firebase가 비어있으면 빈 맵 반환
    return {};
  }

  /// [Firebase] 특정 노선 시간표 가져오기
  static Future<BusTimetable?> fetchTimetable(
    String routeNumber, {
    bool isOutgoing = true,
    bool isWeekday = true,
  }) async {
    try {
      final timetable = await FirebaseSyncService.fetchBusTimetable(
        routeNumber,
        isOutgoing: isOutgoing,
        isWeekday: isWeekday,
      );
      return timetable;
    } catch (e) {
      debugPrint('BusService: 시간표 가져오기 실패 ($routeNumber): $e');
      return null;
    }
  }

  /// 다음 버스 시간 조회 (Firebase 또는 로컬)
  static Future<String?> getNextBusTime(
    String routeNumber, {
    bool isOutgoing = true,
    bool isWeekday = true,
  }) async {
    // 먼저 Firebase 시도
    final firebaseTimetable = await fetchTimetable(
      routeNumber,
      isOutgoing: isOutgoing,
      isWeekday: isWeekday,
    );

    if (firebaseTimetable != null) {
      return firebaseTimetable.getNextBusTime();
    }

    // Firebase가 실패하면 null 반환 (UI에서 로컬 데이터 사용)
    return null;
  }

  /// 다가오는 버스 시간 목록 조회
  static Future<List<String>> getUpcomingBusTimes(
    String routeNumber, {
    bool isOutgoing = true,
    bool isWeekday = true,
    int hours = 2,
  }) async {
    final firebaseTimetable = await fetchTimetable(
      routeNumber,
      isOutgoing: isOutgoing,
      isWeekday: isWeekday,
    );

    if (firebaseTimetable != null) {
      return firebaseTimetable.getUpcomingBuses(hours: hours);
    }

    return [];
  }

  /// 기본 시간표 데이터 (초기 Firebase 업로드용)
  static Map<String, Map<String, Map<String, List<String>>>>
  getDefaultTimetables() {
    return {
      "513": {
        "outgoing": {
          "weekday": [
            "06:20",
            "07:15",
            "07:30",
            "08:50",
            "10:05",
            "10:50",
            "11:45",
            "12:39",
            "13:33",
            "14:27",
            "15:35",
            "16:30",
            "17:23",
            "18:16",
            "19:34",
            "20:27",
            "21:07",
            "22:00",
            "22:40",
          ],
          "holiday": [
            "06:20",
            "07:15",
            "07:30",
            "08:50",
            "10:05",
            "10:50",
            "11:45",
            "12:39",
            "13:33",
            "14:27",
            "15:35",
            "16:30",
            "17:23",
            "18:16",
            "19:34",
            "20:27",
            "21:07",
            "22:00",
            "22:40",
          ],
        },
        "incoming": {
          "weekday": [
            "06:05",
            "07:00",
            "08:10",
            "09:20",
            "10:15",
            "11:09",
            "12:03",
            "12:57",
            "14:05",
            "15:00",
            "15:53",
            "16:46",
            "17:39",
            "18:32",
            "19:37",
            "20:30",
            "21:20",
            "22:10",
          ],
          "holiday": [
            "06:05",
            "07:00",
            "08:10",
            "09:20",
            "10:15",
            "11:09",
            "12:03",
            "12:57",
            "14:05",
            "15:00",
            "15:53",
            "16:46",
            "17:39",
            "18:32",
            "19:37",
            "20:30",
            "21:20",
            "22:10",
          ],
        },
      },
      "514": {
        "outgoing": {
          "weekday": [
            "05:30",
            "06:10",
            "06:55",
            "07:50",
            "09:25",
            "10:30",
            "11:17",
            "12:12",
            "13:06",
            "14:00",
            "15:02",
            "16:03",
            "16:56",
            "17:49",
            "19:07",
            "20:00",
            "20:40",
            "21:34",
            "22:27",
          ],
          "holiday": [
            "05:30",
            "06:10",
            "06:55",
            "07:50",
            "09:25",
            "10:30",
            "11:17",
            "12:12",
            "13:06",
            "14:00",
            "15:02",
            "16:03",
            "16:56",
            "17:49",
            "19:07",
            "20:00",
            "20:40",
            "21:34",
            "22:27",
          ],
        },
        "incoming": {
          "weekday": [
            "05:30",
            "06:25",
            "07:35",
            "08:35",
            "09:47",
            "10:42",
            "11:36",
            "12:30",
            "13:32",
            "14:33",
            "15:26",
            "16:19",
            "17:12",
            "18:00",
            "19:10",
            "20:04",
            "20:57",
            "21:50",
            "22:30",
          ],
          "holiday": [
            "05:30",
            "06:25",
            "07:35",
            "08:35",
            "09:47",
            "10:42",
            "11:36",
            "12:30",
            "13:32",
            "14:33",
            "15:26",
            "16:19",
            "17:12",
            "18:00",
            "19:10",
            "20:04",
            "20:57",
            "21:50",
            "22:30",
          ],
        },
      },
      "518": {
        "outgoing": {
          "weekday": [
            "05:40",
            "06:30",
            "07:05",
            "08:05",
            "08:55",
            "09:55",
            "11:25",
            "12:15",
            "12:55",
            "13:45",
            "14:25",
            "15:15",
            "16:25",
            "17:15",
            "18:00",
            "19:05",
            "19:50",
            "20:35",
            "21:20",
            "22:05",
            "22:50",
          ],
          "holiday": [
            "05:40",
            "06:30",
            "07:05",
            "08:05",
            "08:55",
            "09:55",
            "11:25",
            "12:15",
            "12:55",
            "13:45",
            "14:25",
            "15:15",
            "16:25",
            "17:15",
            "18:00",
            "19:05",
            "19:50",
            "20:35",
            "21:20",
            "22:05",
            "22:50",
          ],
        },
        "incoming": {
          "weekday": [
            "05:40",
            "06:15",
            "07:05",
            "07:50",
            "08:50",
            "09:40",
            "10:30",
            "12:00",
            "12:50",
            "13:30",
            "14:20",
            "15:00",
            "15:50",
            "17:00",
            "18:00",
            "18:45",
            "19:40",
            "20:25",
            "21:10",
            "21:55",
            "22:40",
          ],
          "holiday": [
            "05:40",
            "06:15",
            "07:05",
            "07:50",
            "08:50",
            "09:40",
            "10:30",
            "12:00",
            "12:50",
            "13:30",
            "14:20",
            "15:00",
            "15:50",
            "17:00",
            "18:00",
            "18:45",
            "19:40",
            "20:25",
            "21:10",
            "21:55",
            "22:40",
          ],
        },
      },
    };
  }

  /// [초기 설정용] 기본 시간표를 Firebase에 업로드
  static Future<void> uploadDefaultTimetablesToFirebase() async {
    final timetables = getDefaultTimetables();
    await FirebaseSyncService.uploadAllBusTimetables(timetables);
    debugPrint('BusService: 기본 시간표 Firebase 업로드 완료');
  }
}
