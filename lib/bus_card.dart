import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bus_model.dart';
import 'bus_service.dart';
import 'bus_route_data.dart';

class BusCard extends StatelessWidget {
  final BusSummary bus;

  const BusCard({super.key, required this.bus});

  // 정류장 좌표 정보 (가장 가까운 정류장 계산용)
  static const Map<String, List<double>> _stopCoordinates = {
    "한국교원대학교": [36.6067, 127.3564],
    "한국교원대정문": [36.6065, 127.3568],
    "한국교원대후문": [36.6081, 127.3542],
    "교수아파트": [36.6122, 127.3527],
    "인문관": [36.6106, 127.3598],
    "종합교육관": [36.6107, 127.3610],
    "학생회관": [36.6086, 127.3598],
    "정문": [36.6067, 127.3564],
    "탑연삼거리": [36.6053, 127.3516],
    "강내면행정복지센터": [36.6051, 127.3530],
    "충청대학교": [36.6074, 127.3486],
    "오송역": [36.6200, 127.3275],
    "고속버스터미널": [36.6272, 127.4332],
    "시외버스터미널": [36.6272, 127.4332],
    "사창사거리": [36.6323, 127.4623],
    "청주대학교": [36.6491, 127.4913],
    "도청": [36.6348, 127.4919],
    "육거리": [36.6264, 127.4912],
    "지하상가": [36.6361, 127.4878],
    "동부종점": [36.6247, 127.5342],
    "조치원역": [36.5983, 127.3001],
    "청주공항": [36.7218, 127.4912],
    "예비군훈련장": [36.6666, 127.5306],
    "오송역종점": [36.6190, 127.3265],
    "우진1차고지": [36.6022, 127.5278],
    "송산공원": [36.6422, 127.3105],
    "평동종점": [36.6152, 127.3976],
    "미호종점": [36.5955, 127.3092],
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

  void _showRouteDetail(BuildContext context) {
    debugPrint("BusCard: 노선 상세보기 시도 - 버스 번호: ${bus.number}");
    final routeData = BusRouteData.routeStops[bus.number];
    if (routeData == null) {
      debugPrint("BusCard Error: '${bus.number}' 노선의 정류장 데이터를 BusRouteData에서 찾을 수 없습니다.");
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RouteDetailSheet(bus: bus),
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

    // 버스 방향 추측 (양수면 학교행(상행), 음수면 종점행(하행))
    final bool isUpbound = best != null && best.remainStops >= 0;
    final String directionTag = isUpbound ? "상행" : "하행";
    final String directionSubText = isUpbound ? "학교행" : "종점행";

    String targetStation = bus.isDirect ? "한국교원대 정류장" : "탑연삼거리 정류장";
    String remainText = "-";
    if (hasInfo) {
      if (isUpbound) {
        remainText = isArrived
            ? "$targetStation 진입 중"
            : "$targetStation까지 ${best.remainStops}정거장 전";
      } else {
        // 주요 정류장을 지나쳤을 때 (하행)
        remainText = best.statusText;
      }
    }

    // ETA: BusService에서 교통/시간대/날씨를 반영하여 계산한 estimatedMinutes 사용
    String etaText = "";
    if (hasInfo && isUpbound) {
      if (isArrived) {
        etaText = "잠시 후 도착";
      } else if (best.estimatedMinutes > 0) {
        final int mins = best.estimatedMinutes.round();
        if (mins < 1) {
          etaText = "곧 도착";
        } else if (mins >= 60) {
          final h = mins ~/ 60;
          final m = mins % 60;
          etaText = "약 ${h}시간 ${m}분 후";
        } else {
          etaText = "약 ${mins}분 후 도착";
        }
      } else {
        etaText = "도착 예정";
      }
    } else if (hasInfo && !isUpbound) {
      etaText = best.statusText;
    }

    // 뒤차 정보 (상행 우선 표시)
    String secondBusInfo = "";
    if (arrivals.length > 1) {
      // 상행 버스가 2대 이상이면 상행 2번째를 표시
      final upboundBuses = arrivals.where((a) => a.remainStops >= 0).toList();
      if (upboundBuses.length >= 2) {
        final second = upboundBuses[1];
        if (second.estimatedMinutes > 0) {
          secondBusInfo = "+ 뒤차 약 ${second.estimatedMinutes.round()}분 후";
        } else {
          secondBusInfo = "+ 뒤차 ${second.remainStops}정거장 전";
        }
      } else if (upboundBuses.length == 1) {
        // 상행 1대, 나머지는 하행 → 하행 정보 표시
        final downbound = arrivals.where((a) => a.remainStops < 0).toList();
        if (downbound.isNotEmpty) {
          secondBusInfo = "+ ${downbound.length}대 종점 방면 운행 중";
        }
      } else {
        // 모두 하행
        secondBusInfo = "모든 차량 종점 방면";
      }
    }

    return Semantics(
      label: _buildSemanticsLabel(best, targetStation),
      child: GestureDetector(
        onTap: () => _showRouteDetail(context),
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
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
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
                        if (hasInfo)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (isUpbound ? Colors.green : Colors.orange)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (isUpbound ? Colors.green : Colors.orange)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              directionTag,
                              style: TextStyle(
                                color: isUpbound ? Colors.green : Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (arrivals.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${arrivals.length}대 운행",
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.grey[600],
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasInfo && etaText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: !isUpbound
                            ? (isDark
                                  ? Colors.white10
                                  : Colors.grey.withOpacity(0.1))
                            : (isArrived
                                  ? Colors.red.withOpacity(0.15)
                                  : (isDark
                                        ? Colors.blueAccent.withOpacity(0.2)
                                        : Colors.blue.withOpacity(0.1))),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !isUpbound
                                ? Icons.arrow_forward
                                : Icons.access_time_filled,
                            size: 13,
                            color: !isUpbound
                                ? Colors.grey
                                : (isArrived
                                      ? Colors.redAccent
                                      : (isDark
                                            ? Colors.blueAccent
                                            : Colors.blue)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            etaText,
                            style: TextStyle(
                              color: !isUpbound
                                  ? Colors.grey
                                  : (isArrived
                                        ? Colors.redAccent
                                        : (isDark
                                              ? Colors.blueAccent
                                              : Colors.blue[700])),
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
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
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
                          "현재 버스 위치 ($directionSubText)",
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
                    Flexible(
                      child: Text(
                        secondBusInfo,
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey[400],
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ],
          ),
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

    if (best.remainStops >= 0) {
      label += "목적지까지 ${best.remainStops}정거장 남음";
      if (best.estimatedMinutes > 0) {
        label += ", 예상 도착 시간 약 ${best.estimatedMinutes.round()}분 후";
      } else if (best.remainStops == 0) {
        label += ", 곧 도착";
      }
    } else {
      label += "종점 방면 운행 중";
    }

    return label;
  }
}

class _RouteDetailSheet extends StatefulWidget {
  final BusSummary bus;

  const _RouteDetailSheet({required this.bus});

  @override
  State<_RouteDetailSheet> createState() => _RouteDetailSheetState();
}

class _RouteDetailSheetState extends State<_RouteDetailSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _hasInitialScrolled = false;
  String _selectedDirection = "상행";
  Position? _userPosition;
  List<RouteStop>? _apiStops; // API에서 가져온 정류장 데이터
  bool _isLoadingStops = true;
  String _trafficCondition = "smooth";
  String _congestion = "normal";
  Set<String> _favStops = {}; // 즐겨찾기(주요) 정류장
  Map<String, int> _lastVehicleStopIndex = {};
  final Map<String, int> _lastVehicleNodeOrd = {};
  final Map<String, String> _lastVehicleDirection = {}; // "상행"/"하행"

  @override
  void initState() {
    super.initState();
    _determineInitialDirection();
    _getUserLocation();
    _loadApiStops();
    _loadFavStops();
    _trafficCondition = BusService.estimateTrafficCondition(DateTime.now());
    _congestion = BusService.estimateCongestion(DateTime.now(), widget.bus.id);
  }

  Future<void> _loadFavStops() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'fav_stops_${widget.bus.number}';
    final saved = prefs.getStringList(key) ?? [];
    if (mounted) setState(() => _favStops = saved.toSet());
  }

  Future<void> _toggleFavStop(String stopName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'fav_stops_${widget.bus.number}';
    setState(() {
      if (_favStops.contains(stopName)) {
        _favStops.remove(stopName);
      } else {
        _favStops.add(stopName);
      }
    });
    await prefs.setStringList(key, _favStops.toList());
  }

  /// API에서 정류장 데이터를 불러옴
  Future<void> _loadApiStops() async {
    try {
      final routeId = BusService.getRouteId(widget.bus.id);
      if (routeId != null) {
        final stops = await BusService.fetchRouteStops(routeId);
        if (mounted) {
          setState(() {
            _apiStops = stops.isNotEmpty ? stops : null;
            _isLoadingStops = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingStops = false);
      }
    } catch (e) {
      debugPrint("BusCard: 정류장 데이터 로드 예외 - $e");
      if (mounted) setState(() => _isLoadingStops = false);
    }
  }

  String _normalize(String name) {
    return name.replaceAll(RegExp(r'[^가-힣a-zA-Z0-9]'), '');
  }

  String _vehicleKey(BusArrival arrival) {
    final vehicleNo = (arrival.vehicleNo ?? '').trim();
    if (vehicleNo.isNotEmpty) return vehicleNo;
    return "${widget.bus.number}:${arrival.nodeOrd ?? -1}:${_normalize(arrival.currentStopName)}";
  }

  String? _inferDirectionFromNodeOrd(BusArrival arrival) {
    final nodeOrd = arrival.nodeOrd;
    if (nodeOrd == null) return null;
    final key = _vehicleKey(arrival);
    final prevOrd = _lastVehicleNodeOrd[key];
    _lastVehicleNodeOrd[key] = nodeOrd;

    if (prevOrd == null || prevOrd == nodeOrd) {
      return _lastVehicleDirection[key];
    }
    final dir = nodeOrd > prevOrd ? "상행" : "하행";
    _lastVehicleDirection[key] = dir;
    return dir;
  }

  void _determineInitialDirection() {
    final dynamic routeData = BusRouteData.routeStops[widget.bus.number];
    if (routeData == null) return;

    if (routeData is List) {
      _selectedDirection = "순환";
    } else if (routeData is Map) {
      final arrivals = widget.bus.arrivals;
      if (arrivals.isNotEmpty) {
        // 도착 예정 버스 중 상행(점수 >=0)이 하나라도 있으면 상행을 기본 탭으로
        final hasApproaching = arrivals.any((a) => a.remainStops >= 0);
        _selectedDirection = hasApproaching ? "상행" : "하행";
      } else {
        // 운영 정보 없을 때: 맵의 첫 번째 키(보통 '상행') 사용
        _selectedDirection = routeData.keys.first.toString();
      }
      
      // 혹시라도 설정된 방향이 맵에 없는 경우 안전하게 첫 번째 키로 교정
      if (!routeData.containsKey(_selectedDirection)) {
        _selectedDirection = routeData.keys.first.toString();
      }
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {}
  }

  String? _getNearestStopName(List<String> stops) {
    if (_userPosition == null) return null;
    String? nearest;
    double minDistance = double.infinity;
    for (final stop in stops) {
      final coords = BusCard._stopCoordinates[stop];
      if (coords != null) {
        final distance = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          coords[0],
          coords[1],
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearest = stop;
        }
      }
    }
    return nearest;
  }

  String _buildBusAtStopText(List<BusArrival> busesAtStop) {
    if (busesAtStop.isEmpty) return "";

    final info = busesAtStop
        .map((b) {
          final congestionSuffix = b.congestion != null
              ? " [${b.formattedCongestion}]"
              : "";
          if (b.remainStops == 0) return "곧 도착$congestionSuffix";
          if (b.remainStops < 0) return "진행 중$congestionSuffix";
          return "${b.remainStops}전$congestionSuffix";
        })
        .join(", ");

    if (busesAtStop.length > 2) {
      final first = busesAtStop.first;
      final congestionSuffix = first.congestion != null
          ? " [${first.formattedCongestion}]"
          : "";
      return "${first.remainStops >= 0 ? '${first.remainStops}전' : '진행 중'}$congestionSuffix 외 ${busesAtStop.length - 1}대";
    }
    return info;
  }

  void _scrollToCurrentBus(
    List<BusArrival> arrivals,
    List<String> currentStops,
  ) {
    if (arrivals.isEmpty) return;
    final relevantArrivals = arrivals.where((a) {
      final n = _normalize(a.currentStopName);
      return currentStops.any(
        (s) => _normalize(s).contains(n) || n.contains(_normalize(s)),
      );
    }).toList();
    if (relevantArrivals.isEmpty) return;

    BusArrival? targetBus;
    if (_userPosition != null) {
      double minDist = double.infinity;
      for (final bus in relevantArrivals) {
        if (bus.latitude != null && bus.longitude != null) {
          final d = Geolocator.distanceBetween(
            _userPosition!.latitude,
            _userPosition!.longitude,
            bus.latitude!,
            bus.longitude!,
          );
          if (d < minDist) {
            minDist = d;
            targetBus = bus;
          }
        }
      }
    }
    targetBus ??= relevantArrivals.first;

    final normNearest = _normalize(targetBus.currentStopName);
    final index = currentStops.indexWhere(
      (s) =>
          _normalize(s).contains(normNearest) ||
          normNearest.contains(_normalize(s)),
    );
    if (index != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          try {
            // [방어] position이 완전히 부착되어 있고 dimension이 결정되었는지 확인
            if (!_scrollController.position.hasContentDimensions) return;
            
            final offset = (index * 72.0) - 150.0;
            final maxScroll = _scrollController.position.maxScrollExtent;
            final double targetOffset = offset.clamp(0.0, maxScroll);
            
            _scrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOutCubic,
            );
          } catch (e) {
            debugPrint("Scroll error: $e");
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 교통 상황에 따른 수직선 색상
  Color _trafficColor(bool isDark) {
    switch (_trafficCondition) {
      case "slow":
        return Colors.orange;
      case "congested":
        return Colors.redAccent;
      default:
        return isDark ? Colors.green.shade700 : Colors.green.shade400;
    }
  }

  // 교통 상황 한글 텍스트
  String get _trafficText {
    switch (_trafficCondition) {
      case "slow":
        return "서행";
      case "moderate":
        return "보통";
      case "congested":
        return "정체";
      default:
        return "원활";
    }
  }

  // 혼잡도 한글 텍스트
  String get _congestionText {
    switch (_congestion) {
      case "crowded":
        return "혼잡";
      case "empty":
        return "여유";
      default:
        return "보통";
    }
  }

  Color get _congestionColor {
    switch (_congestion) {
      case "crowded":
        return Colors.redAccent;
      case "empty":
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData get _congestionIcon {
    switch (_congestion) {
      case "crowded":
        return Icons.people;
      case "empty":
        return Icons.person;
      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final routeData = BusRouteData.routeStops[widget.bus.number];
    final bool hasFallbackDirections = routeData != null;

    // API 정류장이 있으면 통합 노선으로 표시 (상행/하행 토글 없음)
    final bool useUnifiedRoute = _apiStops != null && _apiStops!.isNotEmpty;

    List<String> stops = [];
    if (useUnifiedRoute) {
      // API: 전체 노선 통합 표시 (NodeOrd 순서대로)
      stops = _apiStops!.map((s) => s.nodeName).toList();
    } else if (hasFallbackDirections) {
      // routeData는 Map<String, List<String>> 타입임
      final Map<String, List<String>> routeMap = routeData;
      final List<String>? list = routeMap[_selectedDirection];
      
      if (list != null) {
        stops = List<String>.from(list);
      } else if (routeMap.isNotEmpty) {
        // 현재 선택된 방향의 데이터가 없으면 첫 번째 가용한 방향 사용
        stops = List<String>.from(routeMap.values.first);
      }
    }

    // 방향 토글은 API 없이 fallback만 사용하고 방향 데이터가 있을 때만 표시
    final bool showDirectionToggle = !useUnifiedRoute && hasFallbackDirections;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('realtime')
          .doc('bus_locations')
          .snapshots(),
      builder: (context, snapshot) {
        List<BusArrival> currentArrivals = widget.bus.arrivals;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List<dynamic>? summaries = data['summaries'];
          if (summaries != null) {
            final match = summaries.firstWhere(
              (e) => e['number'] == widget.bus.number,
              orElse: () => null,
            );
            if (match != null) {
              currentArrivals = BusSummary.fromJson(
                match as Map<String, dynamic>,
              ).arrivals;
            }
          }
        }

        // 통합 모드: 모든 버스 표시 / 방향 모드: 해당 방향 정류장에 있는 버스만
        List<BusArrival> filteredArrivals;
        if (useUnifiedRoute) {
          // 통합 모드 — nodeOrd 범위 또는 이름 매칭으로 전체 포함
          filteredArrivals = currentArrivals.where((a) {
            if (a.nodeOrd != null) {
              return _apiStops!.any(
                (s) =>
                    s.nodeOrd == a.nodeOrd ||
                    (a.nodeOrd! >= _apiStops!.first.nodeOrd &&
                        a.nodeOrd! <= _apiStops!.last.nodeOrd),
              );
            }
            final n = _normalize(a.currentStopName);
            return _apiStops!.any(
              (s) =>
                  _normalize(s.nodeName).contains(n) ||
                  n.contains(_normalize(s.nodeName)),
            );
          }).toList();
        } else {
          // 방향 모드 — "겹치는 정류장명" 때문에 상/하행에 동시에 찍히는 문제 방지:
          // 1) 우선 정류장명 매칭으로 포함
          // 2) nodeOrd 변화로 차량 진행방향을 추정해, 선택된 방향과 다르면 제외
          filteredArrivals = currentArrivals.where((a) {
            final n = _normalize(a.currentStopName);
            final bool nameMatched = stops.any(
              (s) =>
                  _normalize(s) == n ||
                  _normalize(s).contains(n) ||
                  n.contains(_normalize(s)),
            );
            if (!nameMatched) return false;

            final inferred = _inferDirectionFromNodeOrd(a);
            if (inferred == null) return true; // 초기에 방향 추정 불가하면 일단 표시
            return inferred == _selectedDirection;
          }).toList();
        }

        // ── Exclusive assignment ──────────────────────────────────────────
        // 각 버스(BusArrival)를 stops 목록 중 가장 가까운 정류장 하나에만 배분
        // 같은 버스가 두 정류장에 동시에 표시되는 문제 방지
        final Map<int, List<BusArrival>> busStopMap = {}; // key: stops index
        final previousVehicleStopIndex = Map<String, int>.from(_lastVehicleStopIndex);
        final Map<String, int> currentVehicleStopIndex = {};
        for (final arrival in filteredArrivals) {
          int bestIdx = -1;
          if (_apiStops != null && _apiStops!.isNotEmpty && arrival.nodeOrd != null) {
            // API stops: nodeOrd로 정확히 매칭
            bestIdx = _apiStops!.indexWhere((s) => s.nodeOrd == arrival.nodeOrd);
            // 정확 매칭 없으면 가장 가까운 nodeOrd 정류장
            if (bestIdx == -1) {
              int minDiff = 9999;
              for (int i = 0; i < _apiStops!.length; i++) {
                final diff = (_apiStops![i].nodeOrd - arrival.nodeOrd!).abs();
                if (diff < minDiff) { minDiff = diff; bestIdx = i; }
              }
            }
          } else {
            // fallback stops: 이름 매칭으로 가장 긴 공통 부분 가진 정류장 선택
            final n = _normalize(arrival.currentStopName);
            int bestScore = -1;
            for (int i = 0; i < stops.length; i++) {
              final s = _normalize(stops[i]);
              if (s.contains(n) || n.contains(s)) {
                final score = s.length + n.length;
                if (score > bestScore) { bestScore = score; bestIdx = i; }
              }
            }
          }
          if (bestIdx >= 0) {
            busStopMap.putIfAbsent(bestIdx, () => []).add(arrival);
            currentVehicleStopIndex[_vehicleKey(arrival)] = bestIdx;
          }
        }
        _lastVehicleStopIndex = currentVehicleStopIndex;
        // ─────────────────────────────────────────────────────────────────

        if (!_hasInitialScrolled && filteredArrivals.isNotEmpty) {
          _hasInitialScrolled = true;
          _scrollToCurrentBus(filteredArrivals, stops);
        }

        final nearestStop = _getNearestStopName(stops);
        final upboundCount = currentArrivals
            .where((a) => a.remainStops >= 0)
            .length;
        final downboundCount = currentArrivals
            .where((a) => a.remainStops < 0)
            .length;

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              // === 카카오버스 스타일 헤더 ===
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: widget.bus.color,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: widget.bus.color.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.bus.number,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.bus.direction,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Row(
                                children: [
                                  if (_apiStops != null)
                                    Text(
                                      "${_apiStops!.length}개 정류장",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey,
                                      ),
                                    )
                                  else if (hasFallbackDirections)
                                    Text(
                                      "정류장 목록 (로컬)",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  if (snapshot.hasData) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      "실시간",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.withOpacity(0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // [개선] 로딩 조건 최적화 — 데이터가 이미 있는 경우(탭에서 클릭) 스피너를 공격적으로 노출하지 않음
                        if ((snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) ||
                            (_isLoadingStops && !hasFallbackDirections))
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else if (snapshot.connectionState == ConnectionState.waiting || _isLoadingStops)
                          // 데이터는 있지만 백그라운드 갱신 중일 때 작고 투명한 인디케이터
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                (isDark ? Colors.white : Colors.black12).withOpacity(0.3),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // === 실시간 운행 요약 (카카오버스 스타일) ===
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 교통 상황
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _trafficColor(isDark),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "교통",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      _trafficText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _trafficColor(isDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                          // 혼잡도
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _congestionIcon,
                                  size: 16,
                                  color: _congestionColor,
                                ),
                                const SizedBox(width: 4),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "혼잡도",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      _congestionText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _congestionColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                          // 운행 대수
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  Icons.directions_bus,
                                  size: 16,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "운행",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      "${currentArrivals.length}대",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: currentArrivals.isNotEmpty
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.black87)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 상/하행 토글 위젯 (API 통합 노선에서는 숨김)
              if (showDirectionToggle)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: ["상행", "하행"].map((dir) {
                        final isSelected = _selectedDirection == dir;
                        final dirCount = dir == "상행"
                            ? upboundCount
                            : downboundCount;
                        final isTapyeonVia = !widget.bus.isDirect;
                        final displayDir = !isTapyeonVia
                            ? dir
                            : (dir == "상행" ? "오송 방면" : "청주 방면");
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDirection = dir;
                                _hasInitialScrolled = false;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDark ? Colors.white12 : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayDir,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (isDark
                                                  ? Colors.white38
                                                  : Colors.grey[500]),
                                      ),
                                    ),
                                    if (dirCount > 0) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: widget.bus.color.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "$dirCount",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: widget.bus.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              Expanded(
                child: stops.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: isDark ? Colors.white24 : Colors.grey[300],
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "정류장 정보를 가져올 수 없습니다.",
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 24,
                            ),
                            itemCount: stops.length,
                            itemBuilder: (context, index) {
                              final stopName = stops[index];

                              // exclusive assignment로 미리 계산된 버스 목록 사용
                              final List<BusArrival> busesAtStop =
                                  busStopMap[index] ?? [];

                              final bool isTarget = _favStops.contains(stopName);
                              final bool isNearest = stopName == nearestStop;
                              final bool isFirst = index == 0;
                              final bool isLast = index == stops.length - 1;

                              // 교통 상황 색상 (수직 라인)
                              final lineColor = _trafficColor(isDark);

                              return InkWell(
                                onLongPress: () {
                                  _toggleFavStop(stopName);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 72),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 좌측 노선 라인 + 버스 아이콘
                                      SizedBox(
                                        width: 32,
                                        height: 56,
                                        child: Stack(
                                          alignment: Alignment.topCenter,
                                          children: [
                                            // 교통 상황 반영 수직선 부모 꽉 채움
                                            Positioned.fill(
                                              child: Container(
                                                alignment: Alignment.center,
                                                child: Container(
                                                  width: 3,
                                                  margin: EdgeInsets.only(
                                                    top: isFirst ? 28 : 0,
                                                    bottom: isLast ? 28 : 0,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: lineColor.withOpacity(0.5),
                                                    borderRadius: BorderRadius.circular(1.5),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // 정류장 점
                                            Positioned(
                                              top: 22,
                                              child: Container(
                                                width: isTarget ? 14 : 12,
                                                height: isTarget ? 14 : 12,
                                                decoration: BoxDecoration(
                                                  color: busesAtStop.isNotEmpty
                                                      ? widget.bus.color
                                                      : (isTarget
                                                            ? Colors.orange
                                                            : (isFirst || isLast
                                                                  ? Colors.grey
                                                                  : (isDark
                                                                        ? const Color(0xFF3A3A3C)
                                                                        : Colors.grey[300]))),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // 버스 아이콘들 (여러 대일 경우 겹쳐서 표시)
                                            if (busesAtStop.isNotEmpty)
                                              ...List.generate(busesAtStop.length, (busIndex) {
                                                final arrival = busesAtStop[busIndex];
                                                final key = _vehicleKey(arrival);
                                                final prevIndex = previousVehicleStopIndex[key];
                                                final bool moved = prevIndex != null && prevIndex != index;
                                                final double beginDy = !moved
                                                    ? 0.0
                                                    : (prevIndex < index ? -0.7 : 0.7);

                                                return TweenAnimationBuilder<double>(
                                                  key: ValueKey("$key:$index"),
                                                  tween: Tween<double>(begin: 0, end: 1),
                                                  duration: Duration(milliseconds: 1500 + (busIndex * 300)),
                                                  curve: Curves.elasticOut,
                                                  builder: (context, value, child) {
                                                    return Positioned(
                                                      top: 12 + (10 * (1 - value)) - (busIndex * 6),
                                                      child: TweenAnimationBuilder<Offset>(
                                                        tween: Tween(
                                                          begin: Offset(0, beginDy),
                                                          end: Offset.zero,
                                                        ),
                                                        duration: const Duration(milliseconds: 700),
                                                        curve: Curves.easeOutCubic,
                                                        child: child,
                                                        builder: (context, offset, slideChild) {
                                                          return Transform.translate(
                                                            offset: Offset(0, offset.dy * 18),
                                                            child: Transform.scale(
                                                              scale: (0.8 + (0.2 * value)) * (1 - (busIndex * 0.05)),
                                                              child: slideChild,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: widget.bus.color,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 1.5,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: widget.bus.color.withOpacity(0.4),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                                    ),
                                                    child: const Icon(
                                                      Icons.directions_bus_rounded,
                                                      color: Colors.white,
                                                      size: 14,
                                                    ),
                                                  ),
                                                );
                                              }),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // 정류장 이름 및 정보
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  stopName,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    height: 1.2,
                                                    fontWeight: busesAtStop.isNotEmpty || isTarget || isNearest
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                    color: busesAtStop.isNotEmpty
                                                        ? widget.bus.color
                                                        : (isDark
                                                              ? Colors.white
                                                              : (isTarget
                                                                    ? Colors.orange[800]
                                                                    : (isNearest
                                                                          ? Colors.blue[800]
                                                                          : Colors.black87))),
                                                  ),
                                                ),
                                                if (isNearest)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                                    ),
                                                    child: const Text(
                                                      "가까움",
                                                      style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                if (isTarget)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: const [
                                                        Icon(Icons.star, color: Colors.orange, size: 10),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          "주요거점",
                                                          style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (busesAtStop.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4.0),
                                                child: Text(
                                                  _buildBusAtStopText(busesAtStop),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: widget.bus.color.withOpacity(0.8),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          if (filteredArrivals.isEmpty && stops.isNotEmpty)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isDark
                                                ? Colors.white10
                                                : Colors.black87)
                                            .withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    "이 방향으로 운행 중인 차량이 없습니다.",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
