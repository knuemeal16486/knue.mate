import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bus_route_snapshot.dart';

/// 실시간 차량 혼잡도(1~4)를 [BusSummary.congestion]/[CongestionIndicator]가 쓰는
/// 문자열 등급으로 변환한다. 값이 없으면(API 미제공) null을 반환해 호출부가
/// 시간대 추정치로 폴백할 수 있게 한다.
String? congestionLevelLabel(int? level) {
  switch (level) {
    case 1:
      return 'empty';
    case 2:
      return 'normal';
    case 3:
      return 'crowded';
    case 4:
      return 'full';
    default:
      return null;
  }
}

/// 기준 정류장(교원대/탑연삼거리)을 어느 쪽 방향으로 지나가는 차인지.
///
/// 왕복 노선은 API가 상행·하행을 하나로 이어 붙인 정류장 순서(nodeOrd)를
/// 돌려준다. 그래서 기준 정류장이 그 순서 안에 **두 번** 나온다 — 나갈 때
/// 한 번, 돌아올 때 한 번. 어느 쪽 차인지는 그 차가 다음에 도착할 기준
/// 정류장이 둘 중 어느 것이냐로 정해진다([BusService]가 판정해 넣어준다).
enum BusDirection {
  /// 첫 번째 기준 정류장을 향해 가는 중 (교원대 기준 오송·조치원 방면).
  outbound('상행'),

  /// 돌아오는 길의 기준 정류장을 향해 가는 중 (청주 방면).
  inbound('하행');

  final String label;
  const BusDirection(this.label);
}

/// 홈 화면 "다음 버스" 타일에 띄울 노선 하나를 고른다.
///
/// 즐겨찾기(고정)한 노선 중 **지금 실제로 오고 있는 차가 있는** 것만 후보로
/// 두고, 그중 가장 빨리 도착하는 노선을 고른다. 고정해둔 노선이 전부 운행
/// 전/후라면 null — 호출부가 시간표 기반 안내로 넘어간다.
///
/// 순수 함수 — 테스트 대상.
BusSummary? pickHomeBusSummary(
  List<BusSummary> all,
  Set<String> favorites,
) {
  final candidates = all
      .where((b) => favorites.contains(b.number) && b.arrivals.isNotEmpty)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final an = a.nextArrival?.remainStops ?? 1 << 30;
    final bn = b.nextArrival?.remainStops ?? 1 << 30;
    return an.compareTo(bn);
  });
  return candidates.first;
}

/// 노선 정류장 순서 안에서 "우리 정류장"이 나오는 한 지점.
@immutable
class TargetStopOrd {
  final int ord;
  final BusDirection dir;

  /// 그 지점의 정류장 id. 정류장 도착 정보 API를 물을 때 쓴다. 폴백 표에서
  /// 만든 값엔 없다.
  final String? nodeId;
  const TargetStopOrd(this.ord, this.dir, [this.nodeId]);

  @override
  bool operator ==(Object other) =>
      other is TargetStopOrd && other.ord == ord && other.dir == dir;

  @override
  int get hashCode => ord.hashCode ^ dir.hashCode;

  @override
  String toString() => 'TargetStopOrd($ord, ${dir.name})';
}

/// 노선 정류장 목록에서 기준 정류장이 나오는 지점을 방향별로 하나씩 뽑는다.
///
/// - 이름은 **정확히** 일치해야 한다. "한국교원대학교"를 찾는데 부분일치를
///   쓰면 "한국교원대정문"·"한국교원대학교입구" 같은 다른 정류장이 걸려
///   엉뚱한 지점을 도착지로 잡는다(518·913번에 실제로 그런 정류장이 있다).
/// - 같은 방향에 같은 이름이 연달아 나오는 노선이 있다(913번은 상행에
///   32·33 두 번). 먼저 닿는 쪽만 남긴다.
///
/// 순수 함수 — 테스트 대상.
List<TargetStopOrd> targetOrdsFromStops(
  List<RouteStop> stops,
  String targetName,
) {
  final matched = stops.where((s) => s.nodeName == targetName).toList()
    ..sort((a, b) => a.nodeOrd.compareTo(b.nodeOrd));
  final seenDirections = <int>{};
  final result = <TargetStopOrd>[];
  for (final s in matched) {
    final ud = s.upDownCd ?? 0;
    if (!seenDirections.add(ud)) continue;
    result.add(
      TargetStopOrd(
        s.nodeOrd,
        ud == 1 ? BusDirection.inbound : BusDirection.outbound,
        s.nodeId,
      ),
    );
  }
  result.sort((a, b) => a.ord.compareTo(b.ord));
  return result;
}

/// 폴백 표([BusService]의 하드코딩 값)를 같은 모양으로 바꾼다.
/// 첫 번째가 상행, 두 번째가 하행.
List<TargetStopOrd> targetOrdsFromFallback(List<int>? ords) {
  if (ords == null || ords.isEmpty) return const [];
  return [
    TargetStopOrd(ords.first, BusDirection.outbound),
    if (ords.length > 1) TargetStopOrd(ords[1], BusDirection.inbound),
  ];
}

/// [nodeOrd]에 있는 차가 다음에 닿을 기준 정류장.
///
/// 상행 지점을 이미 지났어도 돌아오는 길의 하행 지점이 남아 있으면 그걸
/// 돌려준다 — 이게 "하행 버스도 도착 시간이 나오는" 핵심이다. 이번 운행에서
/// 기준 정류장을 전부 지났으면 null(= 이 차는 우리 정류장에 안 온다).
///
/// 순수 함수 — 테스트 대상.
TargetStopOrd? nextTargetFor(int nodeOrd, List<TargetStopOrd> targets) {
  TargetStopOrd? best;
  for (final t in targets) {
    if (t.ord < nodeOrd) continue;
    if (best == null || t.ord < best.ord) best = t;
  }
  return best;
}

class BusRouteConfig {
  final int routeNumber;
  final String routeId;
  final bool isDirect;

  const BusRouteConfig({
    required this.routeNumber,
    required this.routeId,
    required this.isDirect,
  });
}

@immutable
class BusArrival {
  final int remainStops;
  final String currentStopName;
  final double estimatedMinutes;
  final double? latitude;
  final double? longitude;
  final String? vehicleNo;
  final int? nodeOrd;
  final int? congestion; // 1: 여유, 2: 보통, 3: 혼잡, 4: 매우혼잡

  /// 이 차가 기준 정류장에 어느 방향으로 들어오는지.
  ///
  /// 예전에는 remainStops 부호로 추측했는데, 왕복 노선에서 돌아오는 차를
  /// 전부 "이미 지나간 차"로 잘못 처리해 도착 시간을 못 보여줬다. 이제는
  /// 다음에 도착할 기준 정류장이 상행 쪽이냐 하행 쪽이냐로 정확히 가른다.
  final BusDirection direction;

  /// [estimatedMinutes]가 정류장 도착 정보 API가 계산한 값인지. 아니면 그
  /// 노선의 실제 속도로 보정한 어림값이거나 시간대 가중치 어림값이다.
  final bool etaFromApi;

  /// 이 차가 지금 정류장([nodeOrd])에 처음 보인 시각. 공용 문서를 새로 쓸 때
  /// 지난 문서에서 이어 받는다. 종점 직전에 위치가 끊기는 차를 이어서 보여 줄
  /// 때 쓴다([carryTerminalApproach]).
  final DateTime? atStopSince;

  const BusArrival({
    required this.remainStops,
    required this.currentStopName,
    this.estimatedMinutes = 0.0,
    this.latitude,
    this.longitude,
    this.vehicleNo,
    this.nodeOrd,
    this.congestion,
    this.direction = BusDirection.outbound,
    this.etaFromApi = false,
    this.atStopSince,
  });

  BusArrival withEta(double minutes, {required bool fromApi}) =>
      copyWith(estimatedMinutes: minutes, etaFromApi: fromApi);

  BusArrival copyWith({
    int? remainStops,
    String? currentStopName,
    double? estimatedMinutes,
    int? nodeOrd,
    bool? etaFromApi,
    DateTime? atStopSince,
  }) =>
      BusArrival(
        remainStops: remainStops ?? this.remainStops,
        currentStopName: currentStopName ?? this.currentStopName,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        latitude: latitude,
        longitude: longitude,
        vehicleNo: vehicleNo,
        nodeOrd: nodeOrd ?? this.nodeOrd,
        congestion: congestion,
        direction: direction,
        etaFromApi: etaFromApi ?? this.etaFromApi,
        atStopSince: atStopSince ?? this.atStopSince,
      );

  int compareTo(BusArrival other) => remainStops.compareTo(other.remainStops);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusArrival &&
        other.remainStops == remainStops &&
        other.currentStopName == currentStopName &&
        other.estimatedMinutes == estimatedMinutes &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.vehicleNo == vehicleNo &&
        other.nodeOrd == nodeOrd &&
        other.congestion == congestion &&
        other.direction == direction &&
        other.etaFromApi == etaFromApi &&
        other.atStopSince == atStopSince;
  }

  @override
  int get hashCode =>
      remainStops.hashCode ^
      currentStopName.hashCode ^
      estimatedMinutes.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      vehicleNo.hashCode ^
      nodeOrd.hashCode ^
      congestion.hashCode ^
      direction.hashCode ^
      etaFromApi.hashCode ^
      atStopSince.hashCode;

  // 유틸리티 메서드
  bool get isApproaching => remainStops <= 3;
  bool get isFarAway => remainStops > 10;

  String get statusText {
    if (remainStops <= 0) return "도착";
    if (remainStops <= 3) return "곧 도착";
    return "$remainStops정거장 전";
  }

  String get formattedCongestion {
    switch (congestion) {
      case 1:
        return "여유";
      case 2:
        return "보통";
      case 3:
        return "혼잡";
      case 4:
        return "매우혼잡";
      default:
        return "보통";
    }
  }

  // 예상 도착 시간 포맷팅
  String get formattedEstimatedTime {
    if (estimatedMinutes <= 0) return "정보 없음";

    if (estimatedMinutes < 1) {
      return "곧 도착";
    } else if (estimatedMinutes < 60) {
      final mins = estimatedMinutes.round();
      return "$mins분 후";
    } else {
      final hours = (estimatedMinutes / 60).floor();
      final mins = (estimatedMinutes % 60).round();
      return "${hours}시간 ${mins}분 후";
    }
  }

  String get detailedInfo {
    return "$currentStopName ($remainStops정거장 전)";
  }
}

@immutable
class BusSummary {
  final int id;
  final String number;
  final String type;
  final String direction;
  final List<BusArrival> arrivals;
  final String congestion;
  final bool isDirect;

  /// [congestion]이 실제 차량 센서값이 아니라 시간대 기준 추정치인지.
  ///
  /// 국토교통부 버스위치정보 API(getRouteAcctoBusLcList)는 혼잡도 필드를
  /// 아예 응답에 포함하지 않는다 — 청주 노선뿐 아니라 이 API 자체가 그렇다.
  /// 그래서 지금은 사실상 항상 true다. 그래도 필드를 남겨두는 이유는, 나중에
  /// 다른 API나 노선에서 실제 값이 들어오면(`BusArrival.congestion`이 채워지면)
  /// 코드를 다시 안 고쳐도 자동으로 false가 되게 하기 위해서다.
  final bool isCongestionEstimated;

  const BusSummary({
    required this.id,
    required this.number,
    required this.type,
    required this.direction,
    required this.arrivals,
    required this.congestion,
    required this.isDirect,
    this.isCongestionEstimated = true,
  });

  // 가장 빨리 도착하는 버스 정보. remainStops가 항상 0 이상(다음에 닿을
  // 기준 정류장까지의 거리)이라 제일 가까운 차를 그대로 고르면 된다.
  BusArrival? get nextArrival {
    if (arrivals.isEmpty) return null;
    return arrivals.reduce((a, b) => a.remainStops <= b.remainStops ? a : b);
  }

  /// 방향별로 나눠 본 도착 목록. 화면이 상행/하행 구역을 따로 그릴 때 쓴다.
  List<BusArrival> arrivalsTowards(BusDirection dir) {
    final list = arrivals.where((a) => a.direction == dir).toList()
      ..sort((a, b) => a.remainStops.compareTo(b.remainStops));
    return list;
  }

  /// 해당 방향에서 가장 빨리 오는 차.
  BusArrival? nextArrivalTowards(BusDirection dir) {
    final list = arrivalsTowards(dir);
    return list.isEmpty ? null : list.first;
  }

  int get arrivingBusCount => arrivals.length;
  int get closestRemainingStops => nextArrival?.remainStops ?? -1;

  String get estimatedArrivalTime {
    final arrival = nextArrival;
    return (arrival == null || arrival.estimatedMinutes <= 0)
        ? "정보 없음"
        : arrival.formattedEstimatedTime;
  }

  Color get color {
    switch (type) {
      case 'red':
        return Colors.redAccent;
      case 'blue':
        return Colors.blueAccent;
      case 'green':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color get congestionColor {
    switch (congestion) {
      case 'empty':
        return Colors.green;
      case 'normal':
        return Colors.blue;
      case 'crowded':
        return Colors.orange;
      case 'full':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  int get congestionLevel {
    switch (congestion) {
      case 'empty':
        return 1;
      case 'normal':
        return 2;
      case 'crowded':
        return 3;
      case 'full':
        return 4;
      default:
        return 0;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'type': type,
      'direction': direction,
      'arrivals': arrivals
          .map(
            (a) => <String, dynamic>{
              'remainStops': a.remainStops,
              'currentStopName': a.currentStopName,
              'estimatedMinutes': a.estimatedMinutes,
              'latitude': a.latitude,
              'longitude': a.longitude,
              'vehicleNo': a.vehicleNo,
              'nodeOrd': a.nodeOrd,
              'congestion': a.congestion,
              // 예전엔 방향을 안 적어서, 공용 문서로 받은 기기에선 모든 차가
              // "상행"(기본값)이 됐다.
              'direction': a.direction.name,
              'etaFromApi': a.etaFromApi,
              if (a.atStopSince != null)
                'atStopSince': a.atStopSince!.millisecondsSinceEpoch,
            },
          )
          .toList(),
      'congestion': congestion,
      'isDirect': isDirect,
      'isCongestionEstimated': isCongestionEstimated,
    };
  }

  factory BusSummary.fromJson(Map<String, dynamic> json) {
    return BusSummary(
      id: json['id'] as int,
      number: json['number'] as String,
      type: json['type'] as String,
      direction: json['direction'] as String,
      arrivals: (json['arrivals'] as List)
          .map(
            (e) => BusArrival(
              remainStops: e['remainStops'] as int,
              currentStopName: e['currentStopName'] as String,
              estimatedMinutes: (e['estimatedMinutes'] as num).toDouble(),
              latitude: (e['latitude'] as num?)?.toDouble(),
              longitude: (e['longitude'] as num?)?.toDouble(),
              vehicleNo: e['vehicleNo'] as String?,
              nodeOrd: (e['nodeOrd'] as num?)?.toInt(),
              congestion: (e['congestion'] as num?)?.toInt(),
              direction: _directionFromJson(
                e['direction'],
                json['number'] as String,
                (e['nodeOrd'] as num?)?.toInt(),
              ),
              etaFromApi: e['etaFromApi'] == true,
              atStopSince: e['atStopSince'] is num
                  ? DateTime.fromMillisecondsSinceEpoch((e['atStopSince'] as num).toInt())
                  : null,
            ),
          )
          .toList(),
      congestion: json['congestion'] as String,
      isDirect: json['isDirect'] as bool,
      // 예전 캐시(필드 추가 전)에는 이 키가 없다 — 없으면 추정치로 본다.
      // 실제로 그때도 늘 추정치였으니 안전한 기본값이다.
      isCongestionEstimated: json['isCongestionEstimated'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusSummary &&
        other.id == id &&
        other.number == number &&
        other.type == type &&
        other.direction == direction &&
        listEquals(other.arrivals, arrivals) &&
        other.congestion == congestion &&
        other.isDirect == isDirect &&
        other.isCongestionEstimated == isCongestionEstimated;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      number.hashCode ^
      type.hashCode ^
      direction.hashCode ^
      arrivals.hashCode ^
      congestion.hashCode ^
      isDirect.hashCode ^
      isCongestionEstimated.hashCode;
}

@immutable
class BusLocation {
  final String nodeId;
  final int nodeOrd;
  final String nodeNm;
  final String vehicleno;
  final double? latitude;
  final double? longitude;
  final int? congestion;

  const BusLocation({
    required this.nodeId,
    required this.nodeOrd,
    required this.nodeNm,
    required this.vehicleno,
    this.latitude,
    this.longitude,
    this.congestion,
  });

  factory BusLocation.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double? toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    String toString(dynamic v) => v?.toString() ?? '알수없음';

    return BusLocation(
      nodeId: toString(j["nodeid"]),
      nodeOrd: toInt(j["nodeord"]),
      nodeNm: toString(j["nodenm"]),
      vehicleno: toString(j["vehicleno"]),
      latitude: toDouble(j["gpslati"] ?? j["gpslat"]),
      longitude: toDouble(j["gpslong"] ?? j["gpslon"]),
      congestion: j["congest"] != null ? toInt(j["congest"]) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeid': nodeId,
      'nodeord': nodeOrd,
      'nodenm': nodeNm,
      'vehicleno': vehicleno,
      'gpslati': latitude,
      'gpslong': longitude,
      'congest': congestion,
    };
  }
}

@immutable
class RouteRemaining {
  final int routeNumber;
  final List<BusArrival> arrivals;

  const RouteRemaining({required this.routeNumber, required this.arrivals});

  BusArrival? get closestBus {
    if (arrivals.isEmpty) return null;
    return arrivals.reduce((a, b) => a.remainStops < b.remainStops ? a : b);
  }

  double get averageWaitingMinutes {
    if (arrivals.isEmpty) return 0.0;
    return arrivals.fold(
          0.0,
          (sum, arrival) => sum + arrival.estimatedMinutes,
        ) /
        arrivals.length;
  }

  bool get isOperating => arrivals.isNotEmpty;

  int get expectedArrivalsIn10Minutes {
    return arrivals.where((a) => a.estimatedMinutes <= 10).length;
  }
}

/// 노선 경유 정류장 정보 (API: getRouteAcctoThrghSttnList)
@immutable
class RouteStop {
  final String nodeId;
  final String nodeName;
  final String? nodeNo;
  final int nodeOrd;
  final double? latitude;
  final double? longitude;
  final int? traffic; // 0: 원활, 1: 서행, 2: 정체

  /// 상행/하행 구분. API가 직접 내려주는 값이라 추측할 필요가 없다.
  /// 0 = 상행(나가는 길), 1 = 하행(돌아오는 길).
  ///
  /// 왕복 노선은 정류장 순서(nodeOrd)가 상행·하행을 하나로 이어 붙인 형태라,
  /// 기준 정류장이 이 목록에 두 번 나온다(예: 511번 탑연삼거리 = nodeOrd 47(상행),
  /// 82(하행)). 이 값으로 둘을 구분한다.
  final int? upDownCd;

  const RouteStop({
    required this.nodeId,
    required this.nodeName,
    this.nodeNo,
    required this.nodeOrd,
    this.latitude,
    this.longitude,
    this.traffic,
    this.upDownCd,
  });

  factory RouteStop.fromJson(Map<String, dynamic> j) {
    return RouteStop(
      nodeId: j['nodeid']?.toString() ?? '',
      nodeName: j['nodenm']?.toString() ?? '알수없음',
      nodeNo: j['nodeno']?.toString(),
      nodeOrd: (j['nodeord'] is num)
          ? (j['nodeord'] as num).toInt()
          : int.tryParse(j['nodeord']?.toString() ?? '0') ?? 0,
      latitude: (j['gpslati'] is num)
          ? (j['gpslati'] as num).toDouble()
          : double.tryParse(j['gpslati']?.toString() ?? ''),
      longitude: (j['gpslong'] is num)
          ? (j['gpslong'] as num).toDouble()
          : double.tryParse(j['gpslong']?.toString() ?? ''),
      traffic: (j['traffic'] is num)
          ? (j['traffic'] as num).toInt()
          : (j['traffic'] != null
                ? int.tryParse(j['traffic'].toString())
                : null),
      upDownCd: (j['updowncd'] is num)
          ? (j['updowncd'] as num).toInt()
          : (j['updowncd'] != null
                ? int.tryParse(j['updowncd'].toString())
                : null),
    );
  }

  Map<String, dynamic> toJson() => {
    'nodeid': nodeId,
    'nodenm': nodeName,
    'nodeno': nodeNo,
    'nodeord': nodeOrd,
    'gpslati': latitude,
    'gpslong': longitude,
    'traffic': traffic,
    'updowncd': upDownCd,
  };
}

/// 버스 시간표 데이터 (Firebase 연동용)
@immutable
class BusTimetable {
  final String routeNumber;
  final bool isOutgoing; // true: 교원대행, false: 학교에서下山
  final bool isWeekday;
  final List<String> departureTimes;

  const BusTimetable({
    required this.routeNumber,
    required this.isOutgoing,
    required this.isWeekday,
    required this.departureTimes,
  });

  factory BusTimetable.fromJson(Map<String, dynamic> json) {
    return BusTimetable(
      routeNumber: json['routeNumber'] as String,
      isOutgoing: json['isOutgoing'] as bool,
      isWeekday: json['isWeekday'] as bool,
      departureTimes: List<String>.from(json['departureTimes'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'routeNumber': routeNumber,
      'isOutgoing': isOutgoing,
      'isWeekday': isWeekday,
      'departureTimes': departureTimes,
    };
  }

  /// 다음 버스 시간 가져오기
  String? getNextBusTime() {
    if (departureTimes.isEmpty) return null;

    final now = DateTime.now();
    final currentTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    for (final time in departureTimes) {
      if (time.compareTo(currentTime) > 0) {
        return time;
      }
    }
    return null;
  }

  /// 시간표에서 해당 시간 이후의 버스 목록 가져오기
  List<String> getUpcomingBuses({int hours = 2}) {
    if (departureTimes.isEmpty) return [];

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final limitMinutes = currentMinutes + (hours * 60);

    return departureTimes.where((time) {
      final parts = time.split(':');
      final timeMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      return timeMinutes >= currentMinutes && timeMinutes <= limitMinutes;
    }).toList();
  }
}

/// 버스 정류장 정보 (Firebase 연동용)
@immutable
class BusStop {
  final String nodeId;
  final String nodeName;
  final String? nodeNo;
  final double latitude;
  final double longitude;
  final int nodeOrd;

  const BusStop({
    required this.nodeId,
    required this.nodeName,
    this.nodeNo,
    required this.latitude,
    required this.longitude,
    required this.nodeOrd,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      nodeId: json['nodeId'] as String? ?? json['nodeid'] as String? ?? '',
      nodeName:
          json['nodeName'] as String? ?? json['nodenm'] as String? ?? '알수없음',
      nodeNo: json['nodeNo'] as String? ?? json['nodeno'] as String?,
      latitude:
          (json['latitude'] as num?)?.toDouble() ??
          (json['gpslati'] as num?)?.toDouble() ??
          0.0,
      longitude:
          (json['longitude'] as num?)?.toDouble() ??
          (json['gpslong'] as num?)?.toDouble() ??
          0.0,
      nodeOrd:
          (json['nodeOrd'] as num?)?.toInt() ??
          (json['nodeord'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'nodeName': nodeName,
      'nodeNo': nodeNo,
      'latitude': latitude,
      'longitude': longitude,
      'nodeOrd': nodeOrd,
    };
  }
}

/// 네트워크가 안 될 때 보여 줄 실시간 버스 값 — 후보(값, 받은 시각) 가운데
/// 가장 최근 것. 값이 null인 후보는 건너뛰고, 시각을 모르는 값은 맨 뒤로
/// 미룬다. 순수 함수 — 테스트 대상.
List<BusSummary>? newestBusSnapshot(
  List<(List<BusSummary>?, DateTime?)> candidates,
) {
  List<BusSummary>? best;
  DateTime? bestAt;
  for (final (value, at) in candidates) {
    if (value == null) continue;
    if (best == null || (at != null && (bestAt == null || at.isAfter(bestAt)))) {
      best = value;
      bestAt = at;
    }
  }
  return best;
}

/// 시간표 목록에서 광고를 끼울 자리(목록 행 번호).
///
/// 방금 지나간 버스와 다음 버스 사이, 즉 다음 버스 카드 바로 위다. 지나간
/// 버스가 없으면 맨 위, 오늘 버스가 모두 지났으면([nextBusIndex] == -1) 맨 끝.
/// 순수 함수 — 테스트 대상.
int busTimetableAdSlot(int nextBusIndex, int count) =>
    nextBusIndex < 0 || nextBusIndex > count ? count : nextBusIndex;


// ── 노선·방향 (2026-11-12) ─────────────────────────────────────────────

/// 앱이 다루는 노선. ⚠️ routeId는 getRouteNoList(cityCode=33010) 응답과 대조하고
/// 넣는다 — 2026-09-19 전수조사에서 10개 중 5개가 엉뚱한 노선이었다.
/// tool/fetch_bus_route_stops.dart의 목록도 같이 고친다.
const List<BusRouteConfig> kBusRoutes = [
  // 교원대 직행/순환
  BusRouteConfig(routeNumber: 513, routeId: "CJB270008000", isDirect: true),
  BusRouteConfig(routeNumber: 514, routeId: "CJB270008300", isDirect: true),
  BusRouteConfig(routeNumber: 518, routeId: "CJB270024700", isDirect: true),
  BusRouteConfig(routeNumber: 913, routeId: "CJB270014300", isDirect: true),
  // 탑연삼거리 경유
  BusRouteConfig(routeNumber: 500, routeId: "CJB270007100", isDirect: false),
  BusRouteConfig(routeNumber: 502, routeId: "CJB270007300", isDirect: false),
  BusRouteConfig(routeNumber: 503, routeId: "CJB270026400", isDirect: false),
  BusRouteConfig(routeNumber: 509, routeId: "CJB270026500", isDirect: false),
  BusRouteConfig(routeNumber: 511, routeId: "CJB270007500", isDirect: false),
  BusRouteConfig(routeNumber: 747, routeId: "CJB270011200", isDirect: false),
];

BusRouteConfig? busRouteConfig(String routeNumber) {
  for (final r in kBusRoutes) {
    if ('${r.routeNumber}' == routeNumber) return r;
  }
  return null;
}

/// 각 노선에서 "도착"의 기준이 되는 정류장 이름. 직행은 교원대 앞, 경유는
/// 탑연삼거리에서 타고 내린다.
String busTargetStopName(bool isDirect) => isDirect ? "한국교원대학교" : "탑연삼거리";

final Map<String, List<TargetStopOrd>> _snapshotTargetsCache = {};

/// 노선 스냅샷([kRouteStopsSnapshot])에서 뽑은 기준 정류장 지점(정류장 id 포함).
List<TargetStopOrd> snapshotTargetsFor(String routeNumber) {
  return _snapshotTargetsCache.putIfAbsent(routeNumber, () {
    final cfg = busRouteConfig(routeNumber);
    final stops = cfg == null ? null : kRouteStopsSnapshot[cfg.routeId];
    if (cfg == null || stops == null) return const [];
    return targetOrdsFromStops(stops, busTargetStopName(cfg.isDirect));
  });
}

/// 기준 정류장 하나(표지판 번호를 보여 줄 때 쓴다).
RouteStop? busTargetStop(String routeNumber, BusDirection dir) {
  final cfg = busRouteConfig(routeNumber);
  final stops = cfg == null ? null : kRouteStopsSnapshot[cfg.routeId];
  if (stops == null) return null;
  for (final t in snapshotTargetsFor(routeNumber)) {
    if (t.dir != dir) continue;
    for (final s in stops) {
      if (s.nodeOrd == t.ord) return s;
    }
  }
  return null;
}

/// 공용 문서의 방향. 예전 앱(1.6.4 이하)이 쓴 문서엔 방향이 없어서, 정류장
/// 순번으로 다음 기준 정류장을 다시 찾아 정한다. 순수 함수 — 테스트 대상.
BusDirection _directionFromJson(dynamic raw, String routeNumber, int? nodeOrd) {
  for (final d in BusDirection.values) {
    if (d.name == raw) return d;
  }
  if (nodeOrd != null) {
    final t = nextTargetFor(nodeOrd, snapshotTargetsFor(routeNumber));
    if (t != null) return t.dir;
  }
  return BusDirection.outbound;
}

@visibleForTesting
BusDirection directionFromJsonForTest(dynamic raw, String routeNumber, int? nodeOrd) =>
    _directionFromJson(raw, routeNumber, nodeOrd);

/// 화면에 보일 방향 이름 — 노선마다 "상행"의 뜻이 달라서(513은 교원대로 들어오는
/// 차, 511은 오송역으로 가는 차) 행선지로 보여 준다. 2026-11-12 노선 데이터로
/// 확인했다(bus_route_snapshot_test). 순수 함수 — 테스트 대상.
const Map<String, (String, String)> kBusDirectionLabels = {
  // 교원대가 종점 — 들어오는 차(상행)는 그대로 돌아 청주로 간다.
  '513': ('교원대 종점 도착', '청주행'),
  '514': ('교원대 종점 도착', '청주행'),
  // 교원대에서 출발해 오송을 돌아 교원대로 돌아온다.
  '518': ('오송행', '교원대 도착'),
  // 평동(청주) → 교원대 → 미호종점 → 교원대 → 평동.
  '913': ('미호행', '청주행'),
  '500': ('오송역행', '청주행'),
  '502': ('조치원역행', '청주행'),
  '503': ('오송역행', '청주행'),
  '509': ('조치원역행', '청주행'),
  '511': ('오송역행', '청주행'),
  '747': ('오송역행', '청주공항행'),
};

String busDirectionLabel(String routeNumber, BusDirection dir) {
  final l = kBusDirectionLabels[routeNumber];
  if (l == null) return dir == BusDirection.outbound ? '상행' : '하행';
  return dir == BusDirection.outbound ? l.$1 : l.$2;
}

/// 기준 정류장 도착 정보(API) 한 건 — 이 노선 것만.
@immutable
class StopEta {
  final String nodeId;
  final int stopsAway;
  final int seconds;
  const StopEta({required this.nodeId, required this.stopsAway, required this.seconds});
}

/// 차량마다 도착 예정(분)을 정한다. 순수 함수 — 테스트 대상.
///
/// 정류장 도착 정보 API는 정류장마다 노선별로 **가장 먼저 올 차 하나**의 도착
/// 예정(초)과 남은 정거장 수를 준다(차량 번호는 없다). 그래서
///  1. 같은 기준 정류장으로 오는 차 중 남은 정거장이 같은(없으면 ±1) 차에 붙인다.
///  2. 나머지 차는 붙인 값에서 나온 이 노선의 실제 속도(분/정거장)로 어림한다.
///  3. 그것도 없으면 [fallback](시간대 가중치 어림).
/// 예전엔 전부 3번이었다 — 22정거장 전 차를 40분으로 봤는데 API는 28분이었다.
List<(double, bool)> resolveVehicleEtas({
  required List<(int, String?)> vehicles,
  required List<StopEta> etas,
  required double Function(int remaining) fallback,
}) {
  final result = List<(double, bool)?>.filled(vehicles.length, null);
  final paceByNode = <String, List<double>>{};

  final sorted = [...etas]..sort((a, b) => a.seconds.compareTo(b.seconds));
  for (final e in sorted) {
    int? best;
    var bestDiff = 2;
    for (var i = 0; i < vehicles.length; i++) {
      if (result[i] != null) continue;
      final (remaining, nodeId) = vehicles[i];
      if (nodeId != e.nodeId) continue;
      final diff = (remaining - e.stopsAway).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    if (best == null) continue;
    result[best] = (e.seconds / 60.0, true);
    if (e.stopsAway >= 1) {
      paceByNode.putIfAbsent(e.nodeId, () => []).add(e.seconds / 60.0 / e.stopsAway);
    }
  }

  double? avg(List<double>? xs) =>
      (xs == null || xs.isEmpty) ? null : xs.reduce((a, b) => a + b) / xs.length;
  final anyPace = avg([for (final l in paceByNode.values) ...l]);

  return [
    for (var i = 0; i < vehicles.length; i++)
      result[i] ??
          (() {
            final (remaining, nodeId) = vehicles[i];
            if (remaining <= 0) return (0.0, false);
            final pace = avg(paceByNode[nodeId]) ?? anyPace;
            return (pace != null ? remaining * pace : fallback(remaining), false);
          })(),
  ];
}

/// 버스 탭 구역 — 학생이 교원대·탑연삼거리에서 **어느 쪽으로 가려는지**로 나눈다.
/// 예전엔 "상행(오송·조치원 방면) / 하행(청주 방면)"으로 갈랐는데, 513번의
/// 상행은 청주에서 교원대로 들어오는 차라 오송 쪽 구역에 잘못 들어갔다.
enum BusHeading {
  cheongju('청주 방면', '시내·터미널·청주공항'),
  osong('오송·조치원 방면', '오송역·조치원역·미호');

  final String title;
  final String subtitle;
  const BusHeading(this.title, this.subtitle);
}

/// 노선·구역 → 그 구역에 넣을 방향들. 순수 함수 — 테스트 대상.
///
/// 교원대가 종점인 513·514는 들어오는 차가 그대로 돌아 청주로 나가고,
/// 교원대에서 출발해 돌아오는 518은 돌아온 차가 다시 오송으로 나간다. 그래서
/// 두 방향 모두 한 구역에 넣는다.
List<BusDirection> busDirectionsFor(String routeNumber, BusHeading heading) {
  switch (routeNumber) {
    case '513':
    case '514':
      return heading == BusHeading.cheongju
          ? const [BusDirection.outbound, BusDirection.inbound]
          : const [];
    case '518':
      return heading == BusHeading.osong
          ? const [BusDirection.outbound, BusDirection.inbound]
          : const [];
    default:
      return [heading == BusHeading.osong ? BusDirection.outbound : BusDirection.inbound];
  }
}

/// 두 방향을 한 카드로 보여 줄 때의 이름(513·514·518).
String busCombinedLabel(String routeNumber) {
  switch (routeNumber) {
    case '513':
    case '514':
      return '청주행 · 교원대 종점';
    case '518':
      return '오송행 · 교원대 출발';
    default:
      return '';
  }
}

/// 노선 한 줄 설명 — 기점 ↔ 반환점(노선 스냅샷의 상행 끝). 예: "정하 ↔ 오송역종점".
String busRouteSummary(String routeNumber) {
  final cfg = busRouteConfig(routeNumber);
  final stops = cfg == null ? null : kRouteStopsSnapshot[cfg.routeId];
  if (stops == null || stops.isEmpty) return '';
  final up = stops.where((s) => s.upDownCd == 0).toList();
  final turn = up.isEmpty ? stops.last : up.last;
  return '${stops.first.nodeName} ↔ ${turn.nodeName}';
}


/// 시간표 탭에서 보고 있는 시간표가 오늘 것인지 — 지나간 버스에 줄을 긋고
/// "오늘 운행이 끝났어요"를 띄울지 정한다. 평일 밤에 휴일 시간표를 열었는데
/// 전부 "출발함"이 되던 것을 막는다. 913은 요일 구분이 없다. 순수 함수 — 테스트 대상.
bool isTodaysTimetable({
  required String route,
  required bool viewingHoliday,
  required DateTime now,
}) {
  if (route == '913') return true;
  return viewingHoliday == (now.weekday >= DateTime.saturday);
}

// ── 정류장 표시 이름 (2026-11-12) ─────────────────────────────────────

/// 자주 타는 정류장은 번호 대신 "~ 방면"(다음 정류장)으로 보여 준다. 정류장
/// 번호(표지판 숫자)만으론 어느 쪽인지 알기 어렵다. 같은 이름이 길 양쪽에
/// 있어서(한국교원대정문 3333·2107, 월탄1리 3330·3331, 탑연삼거리 3308·3309)
/// 이걸로 가른다. 정류장 id로 찾는다 — 번호는 세종 정류장과 겹친다(3309).
/// 이름은 사용자가 정했다(3308 = 궁평3리 방면). 3330은 사용자가 "월탄1리 방면"이라
/// 했지만 그 정류장이 월탄1리라 다음 정류장(한국교원대학교)으로 적었다.
const Map<String, String> kStopHeadingLabels = {
  'CJB271000403': '교원대 후문 방면', // 월탄1리 3331
  'CJB271000381': '교원대 방면', // 월탄1리 3330
  'CJB271000402': '월탄1리 방면', // 한국교원대정문 3333
  'CJB271000424': '다락1리 방면', // 한국교원대정문 2107 (913)
  'CJB274000278': '한국교원대 방면', // 한국교원대학교입구 4031
  'CJB274000277': '궁평3리 방면', // 탑연삼거리 3308 (오송 쪽)
  'CJB271000389': '월곡초등학교 방면', // 탑연삼거리 3309 (청주 쪽)
  'CJB271000392': '종점 · 내리는 곳', // 한국교원대학교 3334
  'CJB274000172': '정문 방면 · 타는 곳', // 한국교원대학교 2633
};

/// 교원대 종점 두 정류장 — 버스 카드에선 번호도 방면도 없이 "교원대"로.
const Set<String> _kCampusTerminalStops = {'CJB271000392', 'CJB274000172'};

/// 정류장 곁말 — "월탄1리 방면", 없으면 표지판 번호. 순수 함수 — 테스트 대상.
String stopHeadingOrNumber(String nodeId, String? nodeNo) =>
    kStopHeadingLabels[nodeId] ?? nodeNo ?? '';

/// 버스 카드의 기준 정류장 — "교원대", "탑연삼거리(월곡초등학교 방면)".
String busTargetStopShort(RouteStop s) {
  if (_kCampusTerminalStops.contains(s.nodeId)) return '교원대';
  final heading = kStopHeadingLabels[s.nodeId];
  if (heading != null) return '${s.nodeName}($heading)';
  return s.nodeNo == null ? s.nodeName : '${s.nodeName} ${s.nodeNo}';
}

// ── 교원대 종점으로 들어오는 차 (2026-11-12) ────────────────────────────

/// 종점 직전 정류장을 지나면 위치 API에서 사라지는 노선과 방향. 513·514는
/// 월탄1리를 지나 교원대(종점)로 들어가면 위치가 끊긴다(사용자 관찰). 그래서
/// 월탄1리를 지나고 [kTerminalApproachTime] 뒤에 교원대에 닿는다고 보고 이어서
/// 보여 준다.
const Map<String, BusDirection> kTerminalApproachRoutes = {
  '513': BusDirection.outbound,
  '514': BusDirection.outbound,
};
const Duration kTerminalApproachTime = Duration(minutes: 3);

/// 교원대에 닿은 뒤 "도착"으로 남겨 두는 시간.
const Duration kTerminalArrivedHold = Duration(minutes: 2);

/// 지난 공용 문서([previous], [previousAt]에 쓴 것)와 이번 위치([current])를
/// 이어 붙인다. 순수 함수 — 테스트 대상.
///
/// 1. 같은 차(차량 번호)가 같은 정류장에 그대로 있으면 처음 보인 시각을 이어
///    받는다(새로 보이면 지금).
/// 2. 종점으로 들어오는 노선([kTerminalApproachRoutes])에서 종점 한 정거장 전
///    차는 "그 정류장에 처음 보인 뒤 3분"으로 도착 시간을 정한다.
/// 3. 지난번에 종점 한 정거장 전(또는 이미 이어 붙인 차)이었는데 이번에
///    사라진 차는 3분까지 "곧 도착", 그 뒤 2분은 "도착"으로 남긴다.
List<BusArrival> carryTerminalApproach({
  required String routeNumber,
  required List<BusArrival> previous,
  required DateTime? previousAt,
  required List<BusArrival> current,
  required DateTime now,
}) {
  BusArrival? prevOf(BusArrival a) {
    final v = a.vehicleNo?.trim() ?? '';
    if (v.isEmpty) return null;
    for (final p in previous) {
      if ((p.vehicleNo?.trim() ?? '') == v) return p;
    }
    return null;
  }

  final stamped = [
    for (final c in current)
      (() {
        final p = prevOf(c);
        final since = (p != null && p.nodeOrd == c.nodeOrd)
            ? (p.atStopSince ?? previousAt ?? now)
            : now;
        return c.copyWith(atStopSince: since);
      })(),
  ];

  final dir = kTerminalApproachRoutes[routeNumber];
  if (dir == null) return stamped;

  double minutesLeft(DateTime since) {
    final left = kTerminalApproachTime - now.difference(since);
    return left.isNegative ? 0 : left.inSeconds / 60.0;
  }

  // 2. 종점 한 정거장 전 차: 지난 뒤 3분
  final out = [
    for (final c in stamped)
      (c.direction == dir && c.remainStops == 1)
          ? c.copyWith(estimatedMinutes: minutesLeft(c.atStopSince!), etaFromApi: false)
          : c,
  ];

  // 3. 사라진 차 이어 붙이기
  final present = {
    for (final c in current)
      if ((c.vehicleNo?.trim() ?? '').isNotEmpty) c.vehicleNo!.trim(),
  };
  TargetStopOrd? terminal;
  for (final t in snapshotTargetsFor(routeNumber)) {
    if (t.dir == dir) terminal = t;
  }
  for (final p in previous) {
    final v = p.vehicleNo?.trim() ?? '';
    if (v.isEmpty || present.contains(v)) continue;
    if (p.direction != dir || p.remainStops > 1) continue;
    final since = p.atStopSince ?? previousAt;
    if (since == null) continue;
    final elapsed = now.difference(since);
    if (elapsed < kTerminalApproachTime) {
      out.add(p.copyWith(
        remainStops: 1,
        estimatedMinutes: minutesLeft(since),
        etaFromApi: false,
        atStopSince: since,
      ));
    } else if (elapsed < kTerminalApproachTime + kTerminalArrivedHold) {
      out.add(p.copyWith(
        remainStops: 0,
        currentStopName: '한국교원대학교',
        nodeOrd: terminal?.ord,
        estimatedMinutes: 0,
        etaFromApi: false,
        atStopSince: since,
      ));
    }
  }
  return out;
}
