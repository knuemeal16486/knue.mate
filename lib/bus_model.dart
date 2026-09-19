import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// 노선 정류장 순서 안에서 "우리 정류장"이 나오는 한 지점.
@immutable
class TargetStopOrd {
  final int ord;
  final BusDirection dir;
  const TargetStopOrd(this.ord, this.dir);

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
  });

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
        other.direction == direction;
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
      direction.hashCode;

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
