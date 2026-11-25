import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bus_model.dart';
import 'bus_service.dart';
import 'bus_route_data.dart';
import 'favorite_service.dart';
import 'ui_utils.dart';

class BusCard extends StatelessWidget {
  final BusSummary bus;

  /// 이 카드가 보여줄 방향. 화면이 상행/하행 구역을 따로 그리므로 보통
  /// 지정해서 쓴다. null이면 방향 구분 없이 전체 차량을 모아 보여준다.
  final BusDirection? direction;

  const BusCard({super.key, required this.bus, this.direction});

  // 정류장 좌표 정보 (가장 가까운 정류장 계산용)
  static const Map<String, List<double>> stopCoordinates = {
    "한국교원대학교": [36.6067, 127.3564],
    "한국교원대정문": [36.6065, 127.3568],
    "한국교원대후문": [36.6081, 127.3542],
    "교수아파트": [36.6122, 127.3527],
    "인문관": [36.6106, 127.3598],
    "종합교육관": [36.6107, 127.3610],
    "학생회관": [36.6086, 127.3598],
    "정문": [36.6067, 127.3564],
    "탑연삼거리": [36.6238, 127.3576], // 2026-11-12 정류장 3308 좌표로 바로잡음
    "강내면행정복지센터": [36.6051, 127.3530],
    "충청대학교": [36.6074, 127.3486],
    "오송역": [36.6200, 127.3275],
    "고속버스터미널": [36.6272, 127.4332],
    "시외버스터미널": [36.6272, 127.4332],
    "사창사거리": [36.6323, 127.4623],
    "청주대학교": [36.6491, 127.4913],
    "도청": [36.6348, 127.4919],
    "육거리": [36.6264, 127.4912],
    "청년창업지원센터": [36.6361, 127.4878],
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

  // 운행 정보가 없을 때 시간대별 메시지
  String _getNoInfoMessage() {
    final hour = DateTime.now().hour;
    if (hour >= 23 || hour < 5) return "운행 종료";
    if (hour >= 5 && hour < 6) return "곧 운행 시작";
    return "위치 대기 중";
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
      builder: (context) => _RouteDetailSheet(bus: bus, initialDirection: direction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 이 카드가 맡은 방향의 차량만 본다. 화면이 상행/하행 구역을 나눠
    // 그리므로 보통 한쪽만 들어온다.
    final arrivals = direction == null
        ? bus.arrivals
        : bus.arrivalsTowards(direction!);
    final BusArrival? best = direction == null
        ? bus.nextArrival
        : bus.nextArrivalTowards(direction!);
    final bool isArrived = best != null && best.remainStops == 0;
    final bool hasInfo = best != null;

    String currentStopName = hasInfo ? best.currentStopName : _getNoInfoMessage();

    // 방향은 더 이상 추측하지 않는다 — API가 준 정류장 순서에서 계산해
    // BusArrival.direction에 담아 온다. 예전엔 "남은 정거장"의 부호로
    // 갈랐는데, 그러면 돌아오는 길의 버스가 전부 "이미 지나감"이 됐다.
    final BusDirection dir =
        direction ?? best?.direction ?? BusDirection.outbound;

    // 방향은 "상행/하행"이 아니라 행선지로 — 노선마다 상행의 뜻이 다르다.
    // 두 방향을 한 카드로 보여 주는 노선(513·514·518)은 노선 이름 하나로.
    final String combined = direction == null ? busCombinedLabel(bus.number) : '';
    final String directionSubText =
        combined.isNotEmpty ? combined : busDirectionLabel(bus.number, dir);
    // 기준 정류장은 표지판 번호까지 — 탑연삼거리는 길 양쪽(3308·3309)에 있다.
    final targetStop = busTargetStop(bus.number, dir);
    final String targetStation = targetStop == null
        ? (bus.isDirect ? "교원대" : "탑연삼거리")
        : busTargetStopShort(targetStop);

    String remainText;
    if (hasInfo) {
      remainText = isArrived
          ? "$targetStation 진입 중"
          : "$targetStation까지 ${best.remainStops}정거장 전";
    } else {
      final hour = DateTime.now().hour;
      remainText = (hour >= 23 || hour < 5) ? "운행 종료 시간대" : "운행 정보 대기 중";
    }

    // 뒤차 정보 — 같은 방향의 두 번째 차.
    String secondBusInfo = "";
    if (arrivals.length > 1) {
      final sorted = [...arrivals]
        ..sort((a, b) => a.remainStops.compareTo(b.remainStops));
      final second = sorted[1];
      secondBusInfo = second.estimatedMinutes > 0
          ? "뒤차 ${second.etaFromApi ? '' : '약 '}${second.estimatedMinutes.round()}분 후"
          : "뒤차 ${second.remainStops}정거장 전";
    }

    // ETA: 정류장 도착 정보 API 값이면 그대로, 아니면 어림값이라 "약"을 붙인다.
    String etaText = "";
    if (hasInfo) {
      final about = best.etaFromApi ? "" : "약 ";
      if (isArrived) {
        etaText = "잠시 후 도착";
      } else if (best.estimatedMinutes > 0) {
        final int mins = best.estimatedMinutes.round();
        if (mins < 1) {
          etaText = "곧 도착";
        } else if (mins >= 60) {
          final h = mins ~/ 60;
          final m = mins % 60;
          etaText = "$about$h시간 $m분 후";
        } else {
          etaText = "$about$mins분 후 도착";
        }
      } else {
        etaText = "도착 예정";
      }
    }

    return Semantics(
      label: "버스 ${bus.number}, $directionSubText, $remainText, $etaText",
      child: AnimatedScaleButton(
        onTap: () => _showRouteDetail(context),
        scaleFactor: 0.96,
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
                color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04),
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
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: FavoriteService.favoritesNotifier,
                    builder: (context, favorites, _) {
                      final isFav = favorites.contains(bus.number);
                      return IconButton(
                        icon: Icon(
                          isFav ? Icons.star : Icons.star_border,
                          color: isFav ? Colors.amber : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () async {
                          if (isFav) {
                            await FavoriteService.remove(bus.number);
                          } else {
                            await FavoriteService.add(bus.number);
                          }
                        },
                      );
                    },
                  ),
                  if (hasInfo && etaText.isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          // 이제 상행·하행 모두 실제 도착 예정 시간이 있으므로
                          // 한쪽만 회색으로 죽이지 않는다. 임박한 차만 빨강.
                          color: isArrived
                              ? Colors.red.withValues(alpha: 0.15)
                              : (isDark
                                    ? Colors.blueAccent.withValues(alpha: 0.2)
                                    : Colors.blue.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_filled,
                              size: 13,
                              color: isArrived
                                  ? Colors.redAccent
                                  : (isDark ? Colors.blueAccent : Colors.blue),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                etaText,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  color: isArrived
                                      ? Colors.redAccent
                                      : (isDark
                                            ? Colors.blueAccent
                                            : Colors.blue[700]),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                          "현재 버스 위치 · $directionSubText",
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
                            // "탑연삼거리(월곡초등학교 방면)까지 3정거장 전"은 길다.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 뒤차는 짧으니 필요한 만큼만 — 반씩 나누면 왼쪽 "n정거장 전"이 잘렸다.
                  if (secondBusInfo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      secondBusInfo,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _RouteDetailSheet extends StatefulWidget {
  final BusSummary bus;

  /// 카드가 맡은 방향(구역). 있으면 노선도를 그 방향으로 연다.
  final BusDirection? initialDirection;

  const _RouteDetailSheet({required this.bus, this.initialDirection});

  @override
  State<_RouteDetailSheet> createState() => _RouteDetailSheetState();
}

class _RouteDetailSheetState extends State<_RouteDetailSheet> {
  /// 공용 문서 구독. Firebase가 없으면(화면 확인용 테스트) 빈 흐름 — 카드가
  /// 받은 값으로만 그린다.
  static Stream<DocumentSnapshot> _busLocationsStream() {
    try {
      return FirebaseFirestore.instance
          .collection('realtime')
          .doc('bus_locations')
          .snapshots();
    } catch (_) {
      return const Stream.empty();
    }
  }

  final ScrollController _scrollController = ScrollController();
  bool _hasInitialScrolled = false;
  String _selectedDirection = "상행";
  Position? _userPosition;
  List<RouteStop>? _apiStops; // API에서 가져온 정류장 데이터
  bool _isLoadingStops = true;
  String _trafficCondition = "smooth";
  Set<String> _favStops = {}; // 즐겨찾기(주요) 정류장
  Map<String, int> _lastVehicleStopIndex = {};

  @override
  void initState() {
    super.initState();
    _determineInitialDirection();
    _getUserLocation();
    _loadApiStops();
    _loadFavStops();
    _trafficCondition = BusService.estimateTrafficCondition(DateTime.now());
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

  /// 차량의 진행 방향. 왕복 노선은 상행·하행이 같은 정류장 이름을 공유해서
  /// 이름만으론 못 가르는데, 이제 BusService가 정류장 순서로 계산한 값을
  /// [BusArrival.direction]에 담아 주므로 그대로 쓰면 된다.
  String? _inferDirection(BusArrival arrival) {
    if (arrival.nodeOrd == null) return null;
    return arrival.direction.label;
  }

  void _determineInitialDirection() {
    final dynamic routeData = BusRouteData.routeStops[widget.bus.number];
    if (routeData == null) return;

    if (routeData is List) {
      _selectedDirection = "순환";
    } else if (routeData is Map) {
      final arrivals = widget.bus.arrivals;
      if (widget.initialDirection != null) {
        // "청주 방면" 구역에서 눌렀으면 청주행 노선도부터.
        _selectedDirection = widget.initialDirection!.label;
      } else if (arrivals.isNotEmpty) {
        // 가장 먼저 도착하는 차의 방향을 기본 탭으로 — 지금 당장 탈 수 있는
        // 쪽을 먼저 보여주는 게 맞다.
        _selectedDirection =
            (widget.bus.nextArrival ?? arrivals.first).direction.label;
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

  String? _getNearestStopName(List<String> stops, [List<RouteStop>? routeStops]) {
    if (_userPosition == null) return null;
    String? nearest;
    double minDistance = double.infinity;
    // 노선 정류장이 있으면 그 좌표(API 값)로. 손으로 적은 좌표 표는 틀린 곳이
    // 있었다(탑연삼거리가 교원대 정문 자리로 2km 어긋나 있었다).
    if (routeStops != null) {
      for (final s in routeStops) {
        if (s.latitude == null || s.longitude == null) continue;
        final d = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          s.latitude!,
          s.longitude!,
        );
        if (d < minDistance) {
          minDistance = d;
          nearest = s.nodeName;
        }
      }
      return nearest;
    }
    for (final stop in stops) {
      final coords = BusCard.stopCoordinates[stop];
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
          final dirTag = "[${busDirectionLabel(widget.bus.number, b.direction)}] ";
          if (b.remainStops == 0) return "$dirTag곧 도착$congestionSuffix";
          return "$dirTag${b.remainStops}전$congestionSuffix";
        })
        .join(", ");

    if (busesAtStop.length > 2) {
      final first = busesAtStop.first;
      final congestionSuffix = first.congestion != null
          ? " [${first.formattedCongestion}]"
          : "";
      final dirTag = "[${busDirectionLabel(widget.bus.number, first.direction)}] ";
      return "$dirTag${first.remainStops}전$congestionSuffix 외 ${busesAtStop.length - 1}대";
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final routeData = BusRouteData.routeStops[widget.bus.number];
    final bool hasFallbackDirections = routeData != null;

    // 정류장 목록 — 노선 스냅샷(또는 노선정보 API)을 방향(upDownCd)별로 나눈다.
    // 예전엔 운영 빌드에 노선정보 키가 없어 손으로 줄여 적은 목록(bus_route_data)
    // 에 이름으로 차를 꽂았다. 그 목록이 실제와 달라(511 상행 끝이 조치원역,
    // 747이 오송역↔오송역) 차가 엉뚱한 곳에 찍히거나 빠졌다.
    final int selectedUd = _selectedDirection == "하행" ? 1 : 0;
    final bool hasApiStops = _apiStops != null && _apiStops!.isNotEmpty;
    final bool apiHasBothDirections = hasApiStops &&
        _apiStops!.any((s) => s.upDownCd == 0) &&
        _apiStops!.any((s) => s.upDownCd == 1);
    final List<RouteStop>? dirStops = !hasApiStops
        ? null
        : apiHasBothDirections
            ? _apiStops!.where((s) => s.upDownCd == selectedUd).toList()
            : _apiStops!;
    final bool useUnifiedRoute = dirStops != null;

    List<String> stops = [];
    if (dirStops != null) {
      stops = dirStops.map((s) => s.nodeName).toList();
    } else if (hasFallbackDirections) {
      final Map<String, List<String>> routeMap = routeData;
      final List<String>? list = routeMap[_selectedDirection];
      if (list != null) {
        stops = List<String>.from(list);
      } else if (routeMap.isNotEmpty) {
        stops = List<String>.from(routeMap.values.first);
      }
    }

    final bool showDirectionToggle =
        apiHasBothDirections || (!hasApiStops && hasFallbackDirections);

    return StreamBuilder<DocumentSnapshot>(
      stream: _busLocationsStream(),
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

        // 노선 정류장이 있으면 정류장 순번으로 정확히 거른다 — 지금 이 방향
        // 목록 위에 있는 차만. 없으면(옛 폴백) 이름으로.
        List<BusArrival> filteredArrivals;
        if (useUnifiedRoute) {
          final ords = {for (final s in dirStops) s.nodeOrd};
          filteredArrivals = currentArrivals.where((a) {
            if (a.nodeOrd != null) return ords.contains(a.nodeOrd);
            final n = _normalize(a.currentStopName);
            return dirStops.any(
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

            final inferred = _inferDirection(a);
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
          if (dirStops != null && arrival.nodeOrd != null) {
            // 노선 정류장: nodeOrd로 정확히 매칭
            bestIdx = dirStops.indexWhere((s) => s.nodeOrd == arrival.nodeOrd);
            // 정확 매칭 없으면 가장 가까운 nodeOrd 정류장
            if (bestIdx == -1) {
              int minDiff = 9999;
              for (int i = 0; i < dirStops.length; i++) {
                final diff = (dirStops[i].nodeOrd - arrival.nodeOrd!).abs();
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

        final nearestStop = _getNearestStopName(stops, dirStops);
        int countOn(int ud, BusDirection fallbackDir) {
          if (!apiHasBothDirections) {
            return currentArrivals.where((a) => a.direction == fallbackDir).length;
          }
          final ords = {
            for (final s in _apiStops!)
              if (s.upDownCd == ud) s.nodeOrd,
          };
          return currentArrivals.where((a) => ords.contains(a.nodeOrd)).length;
        }

        final upboundCount = countOn(0, BusDirection.outbound);
        final downboundCount = countOn(1, BusDirection.inbound);

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
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
                                color: widget.bus.color.withValues(alpha: 0.3),
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
                                busRouteSummary(widget.bus.number).isNotEmpty
                                    ? busRouteSummary(widget.bus.number)
                                    : widget.bus.direction,
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
                                      "${dirStops?.length ?? _apiStops!.length}개 정류장",
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
                                        color: Colors.green.withValues(alpha: 0.7),
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
                                (isDark ? Colors.white : Colors.black12).withValues(alpha: 0.3),
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
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 이 방향 다음 도착 — 시간대로 짐작한 교통·혼잡도 대신 실제 값.
                          Expanded(
                            flex: 2,
                            child: Builder(builder: (context) {
                              final dirEnum = _selectedDirection == "하행"
                                  ? BusDirection.inbound
                                  : BusDirection.outbound;
                              final towards = currentArrivals
                                  .where((a) => a.direction == dirEnum)
                                  .toList()
                                ..sort((a, b) => a.remainStops.compareTo(b.remainStops));
                              final stop = busTargetStop(widget.bus.number, dirEnum);
                              final next = towards.isEmpty ? null : towards.first;
                              final mins = next?.estimatedMinutes.round() ?? 0;
                              final value = next == null
                                  ? "운행 정보 없음"
                                  : next.remainStops == 0 || mins < 1
                                      ? "곧 도착"
                                      : "${next.etaFromApi ? '' : '약 '}$mins분 후";
                              return Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: isDark ? Colors.white54 : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stop == null
                                              ? "다음 도착"
                                              : "${busTargetStopShort(stop)} 도착",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.white38 : Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          value,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            fontFeatures: KnueTokens.tabularFigures,
                                            color: next == null
                                                ? Colors.grey
                                                : (isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
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
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: ["상행", "하행"].map((dir) {
                        final isSelected = _selectedDirection == dir;
                        final dirCount = dir == "상행"
                            ? upboundCount
                            : downboundCount;
                        final displayDir = busDirectionLabel(
                          widget.bus.number,
                          dir == "상행" ? BusDirection.outbound : BusDirection.inbound,
                        );
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
                                          color: Colors.black.withValues(alpha: 0.05),
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
                                          color: widget.bus.color.withValues(alpha: 0.15),
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
                              "정류장 정보를 가져오지 못했어요.",
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
                                                    color: lineColor.withValues(alpha: 0.5),
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
                                                          color: widget.bus.color.withValues(alpha: 0.4),
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
                                                      color: Colors.blue.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
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
                                                      color: Colors.orange.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                                                    color: widget.bus.color.withValues(alpha: 0.8),
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
                                            .withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    "이 방향으로 운행 중인 차가 없어요.",
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
