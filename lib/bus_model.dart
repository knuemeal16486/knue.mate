import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  final double estimatedMinutes; // 추가: 예상 도착 시간(분)

  const BusArrival({
    required this.remainStops,
    required this.currentStopName,
    this.estimatedMinutes = 0.0,
  });

  int compareTo(BusArrival other) => remainStops.compareTo(other.remainStops);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusArrival &&
        other.remainStops == remainStops &&
        other.currentStopName == currentStopName &&
        other.estimatedMinutes == estimatedMinutes;
  }

  @override
  int get hashCode => remainStops.hashCode ^ 
      currentStopName.hashCode ^ 
      estimatedMinutes.hashCode;

  // 유틸리티 메서드
  bool get isApproaching => remainStops <= 3;
  bool get isFarAway => remainStops > 10;
  
  String get statusText {
    if (remainStops == 0) return "도착";
    if (remainStops <= 3) return "곧 도착";
    if (remainStops <= 10) return "$remainStops정거장 전";
    return "멀리 있음";
  }
  
  // 예상 도착 시간 포맷팅 (추가된 기능)
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
  
  // 상세 도착 정보 (추가된 기능)
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
    
    // estimatedMinutes를 기준으로 가장 빠른 버스 선택
    return arrivals.reduce((a, b) {
      if (a.estimatedMinutes <= 0) return b;
      if (b.estimatedMinutes <= 0) return a;
      return a.estimatedMinutes < b.estimatedMinutes ? a : b;
    });
  }

  // 도착 예정 버스 수
  int get arrivingBusCount => arrivals.length;

  // 가장 가까운 버스의 남은 정류장 수
  int get closestRemainingStops => nextArrival?.remainStops ?? -1;

  // 예상 도착 시간 (추가된 기능)
  String get estimatedArrivalTime {
    final arrival = nextArrival;
    if (arrival == null || arrival.estimatedMinutes <= 0) {
      return "정보 없음";
    }
    return arrival.formattedEstimatedTime;
  }

  // 컬러 매핑
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

  // 혼잡도 컬러 (추가된 기능)
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

  // 혼잡도 레벨
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

  // 직렬화/역직렬화 메서드
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'type': type,
      'direction': direction,
      'arrivals': arrivals.map((a) => {
        'remainStops': a.remainStops,
        'currentStopName': a.currentStopName,
        'estimatedMinutes': a.estimatedMinutes,
      }).toList(),
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
          .map((e) => BusArrival(
                remainStops: e['remainStops'] as int,
                currentStopName: e['currentStopName'] as String,
                estimatedMinutes: (e['estimatedMinutes'] as num).toDouble(),
              ))
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

  const BusLocation({
    required this.nodeId,
    required this.nodeOrd,
    required this.nodeNm,
    required this.vehicleno,
  });

  factory BusLocation.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String toString(dynamic v) => v?.toString() ?? '알수없음';

    return BusLocation(
      nodeId: toString(j["nodeid"]),
      nodeOrd: toInt(j["nodeord"]),
      nodeNm: toString(j["nodenm"]),
      vehicleno: toString(j["vehicleno"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'nodeOrd': nodeOrd,
      'nodeNm': nodeNm,
      'vehicleno': vehicleno,
    };
  }
}

@immutable
class RouteRemaining {
  final int routeNumber;
  final List<BusArrival> arrivals;

  const RouteRemaining({
    required this.routeNumber,
    required this.arrivals,
  });

  // 가장 가까운 버스 (추가된 기능)
  BusArrival? get closestBus {
    if (arrivals.isEmpty) return null;
    
    // 남은 정거장 수가 가장 적은 버스 선택
    BusArrival? closest;
    for (final arrival in arrivals) {
      if (closest == null || arrival.remainStops < closest.remainStops) {
        closest = arrival;
      }
    }
    return closest;
  }

  // 평균 대기 시간 (분 단위)
  double get averageWaitingMinutes {
    if (arrivals.isEmpty) return 0.0;
    final totalMinutes = arrivals.fold(0.0, (sum, arrival) => sum + arrival.estimatedMinutes);
    return totalMinutes / arrivals.length;
  }

  // 버스가 운행 중인지
  bool get isOperating => arrivals.isNotEmpty;

  // 예상 도착 버스 수 (10분 내 도착)
  int get expectedArrivalsIn10Minutes {
    return arrivals.where((a) => a.estimatedMinutes <= 10).length;
  }
}