import 'package:flutter/material.dart';

class BusRouteConfig {
  final int routeNumber;
  final String routeId; // API 호출용 ID (CJB...)
  final bool isDirect; // true: 교원대 직행, false: 탑연삼거리 경유

  const BusRouteConfig({
    required this.routeNumber,
    required this.routeId,
    required this.isDirect,
  });
}

class BusArrival {
  final int remainStops;
  final String currentStopName;

  const BusArrival({required this.remainStops, required this.currentStopName});

  int compareTo(BusArrival other) => remainStops.compareTo(other.remainStops);
}

class BusSummary {
  final int id;
  final String number;
  final String type;
  final String direction;
  final List<BusArrival> arrivals;
  final String congestion;
  final bool isDirect; // [New] 학교 직행 여부

  const BusSummary({
    required this.id,
    required this.number,
    required this.type,
    required this.direction,
    required this.arrivals,
    required this.congestion,
    required this.isDirect,
  });
}

class BusLocation {
  final int nodeOrd;
  final String nodeNm;

  const BusLocation({required this.nodeOrd, required this.nodeNm});

  factory BusLocation.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    return BusLocation(
      nodeOrd: toInt(j["nodeord"]),
      nodeNm: j["nodenm"]?.toString() ?? "알수없음",
    );
  }
}

class RouteRemaining {
  final int routeNumber;
  final List<BusArrival> arrivals;
  const RouteRemaining({required this.routeNumber, required this.arrivals});
}
