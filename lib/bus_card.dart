import 'package:flutter/material.dart';
import 'bus_model.dart';

class BusCard extends StatelessWidget {
  final BusSummary bus;

  const BusCard({super.key, required this.bus});

  // 주요 정류장 정보 데이터
  static const Map<String, String> _busRouteInfo = {
    "500": "솔밭초등학교, 신영지웰시티, 만수공원, 오송역종점",
    "502": "고속버스터미널, 한국자산관리공사, 사창사거리, 지하상가(성안길), 만수공원, 오송역5, 조치원",
    "503": "고속버스터미널, 오송역",
    "509": "지하상가, 사창사거리, 고속버스터미널, 오송역5, 조치원역",
    "511": "청주대교, 사창사거리, 고속버스터미널, 오송119안전센터, 오송역종점",
    "747": "청주국제공항, 청주대교, 사창사거리, 고속버스터미널, 오송역종점",
  };

  Color getBusColor(String type) {
    switch (type) {
      case 'blue':
        return const Color(0xFF3B82F6);
      case 'green':
        return const Color(0xFF22C55E);
      case 'red':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  void _showRouteInfo(BuildContext context) {
    final info = _busRouteInfo[bus.number] ?? "상세 정보가 없습니다.";
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bus.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bus.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "주요 경유지",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            info.replaceAll(", ", "\n↓\n"),
            style: const TextStyle(fontSize: 15, height: 1.5),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("확인"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final arrivals = bus.arrivals;
    final BusArrival? best = bus.nextArrival;
    final bool isArrived = best != null && best.remainStops == 0;
    final bool hasInfo = best != null;

    String currentStopName = hasInfo ? best.currentStopName : "운행 정보 없음";

    String targetStation = bus.isDirect ? "한국교원대 정류장" : "탑연삼거리 정류장";
    String remainText = hasInfo
        ? "$targetStation까지 ${best.remainStops}정거장 전"
        : "-";
    if (isArrived) remainText = "$targetStation 진입 중";

    String etaText = "";
    if (hasInfo && !isArrived) {
      int estimatedMin = (best.remainStops * 1.5).ceil();
      etaText = "약 $estimatedMin분 후 도착";
    } else if (isArrived) {
      etaText = "잠시 후 도착";
    }

    String secondBusInfo = "";
    if (arrivals.length > 1) {
      secondBusInfo = "+ 뒤차 ${arrivals[1].remainStops}번째 전";
    }

    // 상세 정보가 있는 노선인지 확인 (직행이 아니면서 정보가 있는 경우)
    bool showInfoButton =
        !bus.isDirect && _busRouteInfo.containsKey(bus.number);

    return Semantics(
      label: _buildSemanticsLabel(best, targetStation),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 버스 번호 + (i) 버튼
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: bus.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        bus.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (showInfoButton) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showRouteInfo(context),
                        child: Icon(
                          Icons.info_outline,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasInfo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isArrived
                          ? Colors.red.withOpacity(0.15)
                          : (isDark
                                ? Colors.blueAccent.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_filled,
                          size: 13,
                          color: isArrived
                              ? Colors.redAccent
                              : (isDark ? Colors.blueAccent : Colors.blue),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          etaText,
                          style: TextStyle(
                            color: isArrived
                                ? Colors.redAccent
                                : (isDark ? Colors.blueAccent : Colors.blue[700]),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white70 : Colors.grey[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 24,
                      color: isDark ? Colors.white24 : Colors.grey[300],
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: bus.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "현재 버스 위치",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentStopName,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: isDark ? Colors.white12 : const Color(0xFFF3F4F6),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_bus_outlined,
                        size: 14,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          remainText,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey[700],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (secondBusInfo.isNotEmpty)
                  Text(
                    secondBusInfo,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey[400],
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSemanticsLabel(BusArrival? best, String targetStation) {
    if (best == null) {
      return "${bus.number}번 버스: 운행 정보 없음";
    }
    
    String label = "${bus.number}번 버스: ";
    label += "현재 위치 ${best.currentStopName}, ";
    label += "목적지까지 ${best.remainStops}정거장 남음";
    
    if (best.remainStops > 0) {
      final estimatedMin = (best.remainStops * 1.5).ceil();
      label += ", 예상 도착 시간 약 $estimatedMin분 후";
    } else {
      label += ", 곧 도착";
    }
    
    return label;
  }
}