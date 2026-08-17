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

  const BusArrival({
    required this.remainStops,
    required this.currentStopName,
    this.estimatedMinutes = 0.0,
    this.latitude,
    this.longitude,
    this.vehicleNo,
    this.nodeOrd,
    this.congestion,
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
        other.congestion == congestion;
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
      congestion.hashCode;

  // 유틸리티 메서드
  bool get isApproaching => remainStops <= 3;
  bool get isFarAway => remainStops > 10;

  String get statusText {
    if (remainStops == 0) return "도착";
    if (remainStops < 0) return "현재 위치: $currentStopName";
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

  const BusSummary({
    required this.id,
    required this.number,
    required this.type,
    required this.direction,
    required this.arrivals,
    required this.congestion,
    required this.isDirect,
  });

  // 가장 빨리 도착하는 버스 정보
  BusArrival? get nextArrival {
    if (arrivals.isEmpty) return null;
    final upboundArrivals = arrivals.where((a) => a.remainStops >= 0).toList();
    if (upboundArrivals.isNotEmpty) {
      return upboundArrivals.reduce(
        (a, b) => a.remainStops <= b.remainStops ? a : b,
      );
    }
    return arrivals.reduce(
      (a, b) => a.remainStops.abs() < b.remainStops.abs() ? a : b,
    );
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
        other.isDirect == isDirect;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      number.hashCode ^
      type.hashCode ^
      direction.hashCode ^
      arrivals.hashCode ^
      congestion.hashCode ^
      isDirect.hashCode;
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

  const RouteStop({
    required this.nodeId,
    required this.nodeName,
    this.nodeNo,
    required this.nodeOrd,
    this.latitude,
    this.longitude,
    this.traffic,
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
