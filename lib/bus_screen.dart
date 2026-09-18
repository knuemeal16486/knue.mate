import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'bus_model.dart';
import 'bus_service.dart';
import 'bus_card.dart';
import 'bus_timetable_data.dart';
import 'call_bus_sheet.dart';
import 'ui_utils.dart';
import 'native_ad_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BusAppScreen extends StatefulWidget {
  const BusAppScreen({super.key});

  @override
  State<BusAppScreen> createState() => _BusAppScreenState();
}

class _BusAppScreenState extends State<BusAppScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // [수정] Observer 추가

  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  final BusService _busService = BusService();

  // [수정] FutureBuilder 대신 상태 변수 사용 (깜빡임 없는 갱신을 위해)
  List<BusSummary> _realtimeBusList = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isRefreshing = false; // 백그라운드 갱신 중 표시용
  DateTime? _lastUpdateTime; // 마지막 데이터 갱신 시간
  Timer? _timer;
  Timer? _tickTimer; // UI 갱신 시간 표시용
  StreamSubscription<DocumentSnapshot>? _busSub; // 실시간 구독 변수 추가

  String _selectedBus = "513";
  bool _isWeekend = false;
  bool _isToSchool = false;
  int _selectedStopOffset = 0;
  String? _lastAutoScrollKey; // 시간표 탭 자동 스크롤을 선택이 바뀔 때만 1회 실행하기 위한 키

  // 913번 3개 탭 상태 (0: 미호종점 출발, 1: 교원대 경유, 2: 평동 출발)
  int _selected913Tab = 1;
  // 913번 교원대 경유 상하행 구분 (true: 상행[미호종점 방면], false: 하행[평동 방면])
  bool _is913KnueUpbound = true;

  // 513/514/518 시간표·승차 정류장 데이터는 bus_timetable_data.dart를 단일 소스로 사용한다.
  // (과거 이 파일에 별도로 하드코딩된 사본이 있었으나 실제 시간표와 어긋나 있어 제거함)
  Map<String, Map<String, Map<String, List<String>>>> get _busSchedules =>
      BusTimetableData.schedules;
  Map<String, Map<String, int>> get _boardingStops =>
      BusTimetableData.boardingStops;

  // [알람 상태 관리] -> key: "bus:direction:day:time", value: notificationId
  Map<String, int> _scheduledAlarms = {};

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('bus_scheduled_alarms');
    if (data != null) {
      setState(() {
        _scheduledAlarms = Map<String, int>.from(json.decode(data));
      });
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bus_scheduled_alarms',
      json.encode(_scheduledAlarms),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this);
    final weekday = DateTime.now().weekday;
    _isWeekend = (weekday == 6 || weekday == 7);

    // 초기 데이터 로드 및 알람 로드
    // [개선] 초기 로딩을 백그라운드에서 수행하고 Firestore 리스너가 UI를 관리하도록 함
    _fetchBusData(isQuietRefetch: true);
    _startAutoRefresh();
    // 1초마다 UI 갱신 (마지막 갱신 시간 표시용)
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _lastUpdateTime != null) setState(() {});
    });
    _loadAlarms();
    _startRealtimeTracking();
  }

  void _startRealtimeTracking() {
    _busSub = FirebaseFirestore.instance
        .collection('realtime')
        .doc('bus_locations')
        .snapshots()
        .listen(
          (snapshot) {
            try {
              if (snapshot.exists) {
                final raw = snapshot.data();
                if (raw is! Map<String, dynamic>) {
                  if (mounted && _isLoading) {
                    setState(() => _isLoading = false);
                  }
                  return;
                }

                final dynamic summariesRaw = raw['summaries'];
                if (summariesRaw is List) {
                  final newList = summariesRaw
                      .whereType<Map>()
                      .map(
                        (e) => BusSummary.fromJson(e.cast<String, dynamic>()),
                      )
                      .toList();

                  if (!listEquals(_realtimeBusList, newList)) {
                    if (mounted) {
                      setState(() {
                        _realtimeBusList = newList;
                        _isLoading = false;
                        _isRefreshing = false;
                        _hasError = false;
                        _lastUpdateTime = DateTime.now();
                      });
                    }
                  } else if (_isLoading && mounted) {
                    setState(() {
                      _isLoading = false;
                      _lastUpdateTime = DateTime.now();
                    });
                  }
                } else {
                  // 문서는 있으나 summaries가 비어있거나 형식이 다르면 로딩 해제
                  if (mounted && _isLoading) {
                    setState(() => _isLoading = false);
                  }
                  // 초기 빈 문서 상태일 수 있어 API로 한 번 폴백
                  if (_realtimeBusList.isEmpty) {
                    _fetchBusData(isQuietRefetch: true);
                  }
                }
              } else {
                // 데이터가 없는 경우 로딩 종료 후 API 폴백
                if (_isLoading && mounted) {
                  setState(() => _isLoading = false);
                }
                if (_realtimeBusList.isEmpty) {
                  _fetchBusData(isQuietRefetch: true);
                }
              }
            } catch (e) {
              debugPrint("Realtime snapshot parse error: $e");
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  if (_realtimeBusList.isEmpty) {
                    _hasError = true;
                  }
                });
              }
            }
          },
          onError: (e) {
            debugPrint("Realtime Sync Error: $e");
            if (mounted && _realtimeBusList.isEmpty) {
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            }
          },
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tickTimer?.cancel();
    _busSub?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchBusData(isQuietRefetch: true);
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  // [개선] 자동 새로고침 타이머 간격 조정 (15초 -> 30초)
  // 너무 빈번한 API 호출은 네트워크 지연 및 서버 부하를 초래할 수 있음
  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchBusData(isQuietRefetch: true);
      }
    });
  }

  // [개선] 버스 데이터 가져오기 로직 최적화
  Future<void> _fetchBusData({bool isQuietRefetch = false}) async {
    // 이미 데이터가 있다면 로딩바를 띄우지 않음 (Seamless Update)
    if (!isQuietRefetch && _realtimeBusList.isEmpty) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    } else if (isQuietRefetch && _realtimeBusList.isNotEmpty) {
      // 백그라운드 갱신 중 표시
      if (mounted) setState(() => _isRefreshing = true);
    }

    try {
      final buses = await _busService.fetchAllBuses().timeout(
        const Duration(seconds: 18),
      );
      if (mounted) {
        setState(() {
          _realtimeBusList = buses;
          _isLoading = false;
          _isRefreshing = false;
          _hasError = false;
          _lastUpdateTime = DateTime.now();
        });

        // 수동 새로고침일 때 && 데이터가 갱신되었을 때만 토스트
        if (!isQuietRefetch) {
          showToast(context, "버스 정보를 업데이트했습니다.");
        }
      }
    } catch (e) {
      if (mounted) {
        // 이미 데이터가 있는 경우 에러 화면으로 전환하지 않고 로그만 남김
        if (_realtimeBusList.isEmpty) {
          setState(() {
            _hasError = true;
            _isLoading = false;
            _isRefreshing = false;
          });
        } else {
          setState(() => _isRefreshing = false);
        }
        debugPrint("Bus Fetch Error: $e");
      }
    }
  }

  void _scrollToNextBus(int index) {
    if (index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            (index * 72.0) - 100,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  String _addMinutes(String timeStr, int minutesToAdd) {
    if (timeStr.isEmpty) return "";
    try {
      final parts = timeStr.split(":");
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      minute += minutesToAdd;

      if (minute >= 60) {
        hour += minute ~/ 60;
        minute = minute % 60;
      }
      hour = hour % 24;

      return "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return timeStr;
    }
  }

  /// 학교로 오는 방향(incoming)의 출발지 이름.
  String _getTerminusName() {
    if (_selectedBus == "518") return "보건의료행정타운 출발";
    if (_selectedBus == "502") return "청주역 출발";
    // 913은 교원대가 종점이 아니라 경유지라 양쪽 다 종점 이름으로 적는다.
    if (_selectedBus == "913") return "평동 출발";
    return "동부종점 출발";
  }

  /// 학교에서 나가는 방향(outgoing)의 출발지 이름.
  ///
  /// 513·514·518은 교원대가 종점이라 "교원문화관 출발"이 맞지만, 913은
  /// 교원대를 지나쳐 갈 뿐이라 그렇게 적으면 틀린 시각으로 읽힌다.
  String _getOriginName() {
    if (_selectedBus == "913") return "미호종점 출발";
    return "교원문화관 출발";
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
            title: const Text("청람버스"),
            backgroundColor: Colors.transparent,
            flexibleSpace: AppleAppBarFlexibleSpace(
              themeColor: color,
              isDark: isDark,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            leading: null, // 햄버거 메뉴 제거
            actions: [
              IconButton(
                onPressed: () => _fetchBusData(), // [수정] 수동 새로고침 연결
                icon: const Icon(Icons.refresh),
                tooltip: "새로고침",
              ),
              IconButton(
                onPressed: () => _showArrivalInfoDialog(context),
                icon: const Icon(Icons.info_outline),
                tooltip: "도착 시간 정보",
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
              tabs: const [
                Tab(text: "버스 시간표"),
                Tab(text: "실시간 위치"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTimetableTab(isDark, color),
              _buildRealtimeTab(isDark),
            ],
          ),
        );
      },
    );
  }

  // [수정] 실시간 탭 - FutureBuilder 대신 상태 변수 기반 렌더링
  Widget _buildRealtimeTab(bool isDark) {
    return Container(
      color: isDark ? Colors.black12 : const Color(0xFFF9FAFB),
      child: _buildRealtimeContent(isDark),
    );
  }

  // 시간대에 따른 운행 안내 메시지
  String _getEmptyStateMessage() {
    final hour = DateTime.now().hour;
    if (hour >= 23 || hour < 5) {
      return "운행이 종료된 시간대입니다.\n첫차는 05:30부터 운행됩니다.";
    } else if (hour >= 5 && hour < 6) {
      return "곧 운행이 시작됩니다.\n잠시 후 다시 확인해주세요.";
    }
    return "현재 운행 중인 버스가 없습니다.\n잠시 후 다시 확인해주세요.";
  }

  // 마지막 갱신 시간 포맷
  String _formatLastUpdate() {
    if (_lastUpdateTime == null) return "";
    final diff = DateTime.now().difference(_lastUpdateTime!);
    if (diff.inSeconds < 5) return "방금 갱신";
    if (diff.inSeconds < 60) return "${diff.inSeconds}초 전 갱신";
    if (diff.inMinutes < 5) return "${diff.inMinutes}분 전 갱신";
    return "${diff.inMinutes}분 전 (갱신 필요)";
  }

  Widget _buildRealtimeContent(bool isDark) {
    // 1. 초기 로딩 중 → 스켈레톤 UI
    if (_isLoading) {
      return _buildSkeletonLoading(isDark);
    }

    // 2. 에러 발생 시
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "버스 정보를 불러오지 못했어요",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "네트워크 연결을 확인해주세요",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _fetchBusData(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("다시 시도"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 3. 데이터 없음 → 시간대별 안내 메시지
    if (_realtimeBusList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_bus_filled_outlined,
                size: 56,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getEmptyStateMessage(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "운행 시간표를 확인해주세요.",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // 4. 버스 목록 표시
    final directBuses = _realtimeBusList.where((b) => b.isDirect).toList();
    final tapyeonBuses = _realtimeBusList.where((b) => !b.isDirect).toList();
    final totalBuses = _realtimeBusList.fold<int>(
      0,
      (sum, b) => sum + b.arrivals.length,
    );
    final traffic = BusService.estimateTrafficCondition(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async => _fetchBusData(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // === 실시간 요약 카드 ===
          _buildRealtimeSummaryCard(isDark, traffic, totalBuses),

          // === 마지막 갱신 시간 + 갱신 중 표시 ===
          if (_lastUpdateTime != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  if (_isRefreshing) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.white24 : Colors.grey.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "갱신 중...",
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                  ] else ...[
                    // 살아있는 데이터라는 신호 — 맥동하는 앰버 점(보조색).
                    KnueLiveDot(isDark: isDark),
                    const SizedBox(width: 6),
                    Text(
                      _formatLastUpdate(),
                      style: TextStyle(
                        fontSize: 11,
                        fontFeatures: KnueTokens.tabularFigures,
                        color:
                            _lastUpdateTime != null &&
                                DateTime.now()
                                        .difference(_lastUpdateTime!)
                                        .inMinutes >=
                                    3
                            ? KnueTokens.warm(isDark)
                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          if (directBuses.isNotEmpty) ...[
            _buildSectionHeader("🎯 교원대 직행", isDark, subtitle: "정문까지 직통"),
            ...directBuses.map((b) => BusCard(bus: b)),
            const SizedBox(height: 20),
          ],

          if (tapyeonBuses.isNotEmpty) ...[
            _buildSectionHeader(
              "🔄 탑연삼거리 경유",
              isDark,
              subtitle: "탑연삼거리 하차 후 환승",
            ),
            ...tapyeonBuses.map((b) => BusCard(bus: b)),
            const SizedBox(height: 20),
          ],

          _buildArrivalInfoSection(isDark),
        ],
      ),
    );
  }

  Widget _buildRealtimeSummaryCard(
    bool isDark,
    String traffic,
    int totalBuses,
  ) {
    String trafficText;
    Color trafficColor;
    IconData trafficIcon;
    switch (traffic) {
      case "slow":
        trafficText = "서행";
        trafficColor = Colors.orange;
        trafficIcon = Icons.speed;
        break;
      case "congested":
        trafficText = "정체";
        trafficColor = Colors.red;
        trafficIcon = Icons.warning_amber_rounded;
        break;
      default:
        trafficText = "원활";
        trafficColor = Colors.green;
        trafficIcon = Icons.check_circle_outline;
    }

    final timeStr =
        "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')} 기준";

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GlassContainer(
        opacity: isDark ? 0.08 : 0.4,
        blur: 16.0,
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white10
              : Colors.blue.shade100.withOpacity(0.5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // 교통 상황
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: trafficColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(trafficIcon, color: trafficColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "교통 상황",
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            trafficText,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: trafficColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: isDark ? Colors.white10 : Colors.blue.shade100,
                ),
                // 총 운행 대수
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.directions_bus,
                          color: isDark ? Colors.blue.shade300 : Colors.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "운행 중",
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            "$totalBuses대",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.access_time,
                  size: 11,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white24 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalInfoSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.blue[800]! : Colors.blue[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: isDark ? Colors.blue[300] : Colors.blue[700],
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "도착 시간 정보",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.blue[300] : Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "• 예상 도착 시간은 교통상황, 시간대, 날씨 등을 고려하여 계산됩니다.\n"
            "• 실제 도착 시간과 차이가 있을 수 있습니다.\n"
            "• 출퇴근 시간(7-9시, 17-19시)에는 지연이 발생할 수 있습니다.",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.blueGrey[700],
            ),
          ),
        ],
      ),
    );
  }

  void _showArrivalInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("도착 시간 계산 방법"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "예상 도착 시간은 다음 요소를 고려하여 계산됩니다:",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildInfoItem("정거장 당 기본 시간", "1.6-3.0분 (노선별 상이)"),
            _buildInfoItem("시간대별 교통", "출퇴근 혼잡시간 최대 +50%"),
            _buildInfoItem("주말 영향", "주말 +10%"),
            _buildInfoItem("계절/날씨", "겨울 +10%, 한여름 +5%"),
            _buildInfoItem("근접 보정", "3정거장 이하 남으면 +1분"),
            const SizedBox(height: 12),
            const Text(
              "이 정보는 참고용이며 실제 도착 시간과 다를 수 있습니다.",
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontSize: 12)),
          Expanded(
            child: Text(
              "$title: ",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white24 : Colors.grey.shade500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 스켈레톤 로딩 UI (초기 로딩 시 보여줄 플레이스홀더)
  Widget _buildSkeletonLoading(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // 요약 카드 스켈레톤
        _buildSkeletonCard(
          isDark,
          height: 80,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
        // 섹션 헤더 스켈레톤
        _buildSkeletonBar(
          isDark,
          width: 100,
          height: 16,
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        ),
        // 버스 카드 스켈레톤 x4
        for (int i = 0; i < 4; i++) _buildSkeletonBusCard(isDark),
        // 두 번째 섹션 헤더
        _buildSkeletonBar(
          isDark,
          width: 120,
          height: 16,
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        ),
        // 버스 카드 스켈레톤 x3
        for (int i = 0; i < 3; i++) _buildSkeletonBusCard(isDark),
      ],
    );
  }

  Widget _buildSkeletonBusCard(bool isDark) {
    final shimmerBase = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFEEEEEE);
    final shimmerHighlight = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFF5F5F5);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildShimmerBox(
                shimmerBase,
                shimmerHighlight,
                width: 56,
                height: 28,
                radius: 8,
              ),
              _buildShimmerBox(
                shimmerBase,
                shimmerHighlight,
                width: 100,
                height: 28,
                radius: 12,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildShimmerBox(
                shimmerBase,
                shimmerHighlight,
                width: 8,
                height: 44,
                radius: 4,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(
                    shimmerBase,
                    shimmerHighlight,
                    width: 80,
                    height: 12,
                    radius: 4,
                  ),
                  const SizedBox(height: 6),
                  _buildShimmerBox(
                    shimmerBase,
                    shimmerHighlight,
                    width: 140,
                    height: 18,
                    radius: 4,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildShimmerBox(
            shimmerBase,
            shimmerHighlight,
            width: double.infinity,
            height: 1,
            radius: 0,
          ),
          const SizedBox(height: 10),
          _buildShimmerBox(
            shimmerBase,
            shimmerHighlight,
            width: 200,
            height: 14,
            radius: 4,
          ),
        ],
      ),
    );
  }

  /// 스켈레톤 조각. 예전에는 TweenAnimationBuilder로 1.5초에 걸쳐 한 번만
  /// 훑고 멈춰서, 로딩이 길어지면 화면이 굳은 것처럼 보였다. 공용 [KnueSkeleton]에
  /// 위임해 계속 은은히 맥동하게 한다. (base/highlight는 호출부 호환용으로만 유지)
  Widget _buildShimmerBox(
    Color base,
    Color highlight, {
    required double width,
    required double height,
    required double radius,
  }) {
    return KnueSkeleton(
      width: width,
      height: height,
      radius: radius,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  Widget _buildSkeletonCard(
    bool isDark, {
    double height = 60,
    EdgeInsets margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildSkeletonBar(
    bool isDark, {
    double width = 100,
    double height = 14,
    EdgeInsets margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildSubDirectionToggle(
    String label,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
    Color primary,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withOpacity(isDark ? 0.25 : 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // 시간표 탭
  Widget _buildTimetableTab(bool isDark, Color primary) {
    final String directionKey;
    final List<String> timeList;
    final List<String?> subInfoList;

    if (_selectedBus == "913") {
      if (_selected913Tab == 0) {
        // 미호종점 출발 (하행 기점)
        directionKey = "outgoing";
        final trips = BusTimetableData.route913MihoToPyeongdong;
        timeList = trips.map((t) => t.originTime).toList();
        subInfoList = trips
            .map((t) => "교원대 ${t.knueTime} 경유 · 평동 ${t.destinationTime} 도착")
            .toList();
      } else if (_selected913Tab == 1) {
        // 교원대 경유
        if (_is913KnueUpbound) {
          // 상행 (미호종점 방면 / 평동발)
          directionKey = "knue_up";
          final trips = BusTimetableData.route913PyeongdongToMiho;
          timeList = trips.map((t) => t.knueTime).toList();
          subInfoList = trips
              .map(
                (t) => "평동 ${t.originTime} 출발 · 미호종점 ${t.destinationTime} 도착",
              )
              .toList();
        } else {
          // 하행 (평동 방면 / 미호발)
          directionKey = "knue_down";
          final trips = BusTimetableData.route913MihoToPyeongdong;
          timeList = trips.map((t) => t.knueTime).toList();
          subInfoList = trips
              .map((t) => "미호 ${t.originTime} 출발 · 평동 ${t.destinationTime} 도착")
              .toList();
        }
      } else {
        // 평동 출발 (상행 기점)
        directionKey = "incoming";
        final trips = BusTimetableData.route913PyeongdongToMiho;
        timeList = trips.map((t) => t.originTime).toList();
        subInfoList = trips
            .map((t) => "교원대 ${t.knueTime} 경유 · 미호종점 ${t.destinationTime} 도착")
            .toList();
      }
    } else {
      directionKey = _isToSchool ? "incoming" : "outgoing";
      final dayKey = _isWeekend ? "holiday" : "weekday";
      final List<String> rawTimeList =
          _busSchedules[_selectedBus]?[directionKey]?[dayKey] ?? [];
      timeList = rawTimeList
          .map((t) => _addMinutes(t, _selectedStopOffset))
          .toList();
      subInfoList = List.filled(timeList.length, null);
    }

    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    int nextBusIndex = -1;
    for (int i = 0; i < timeList.length; i++) {
      try {
        final parts = timeList[i].split(":");
        final busMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        if (busMinutes >= currentMinutes) {
          nextBusIndex = i;
          break;
        }
      } catch (e) {
        continue;
      }
    }

    final dayKey = _isWeekend ? "holiday" : "weekday";
    final scrollKey =
        "$_selectedBus:$directionKey:$dayKey:$_selectedStopOffset";
    if (nextBusIndex != -1 && _lastAutoScrollKey != scrollKey) {
      _lastAutoScrollKey = scrollKey;
      _scrollToNextBus(nextBusIndex);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // 노선 4개 + 구분선 + 콜버스 버튼이 좁은 화면에서는 한 줄에
              // 다 안 들어가 오른쪽으로 넘쳤다("RIGHT OVERFLOWED"). 가로
              // 스크롤로 감싸 넘치는 대신 옆으로 밀리게 한다.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...["513", "514", "518", "913"].map((busNo) {
                      final isSelected = _selectedBus == busNo;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedBus = busNo;
                          _selectedStopOffset = 0;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected
                                  ? primary
                                  : Colors.grey.withOpacity(0.3),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primary.withOpacity(
                                        isDark ? 0.15 : 0.08,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            "$busNo번",
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.black87),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                    GestureDetector(
                      onTap: () => CallBusBottomSheet.show(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: primary.withOpacity(isDark ? 0.4 : 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_bus_outlined,
                              size: 14,
                              color: isDark ? Colors.white70 : primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "콜버스",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDayChip(
                    "평일",
                    !_isWeekend,
                    () => setState(() => _isWeekend = false),
                    isDark,
                    primary,
                  ),
                  const SizedBox(width: 12),
                  _buildDayChip(
                    "휴일",
                    _isWeekend,
                    () => setState(() => _isWeekend = true),
                    isDark,
                    primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_selectedBus == "913") ...[
                // 913번 전용 3개 탭: 미호종점 출발 | 교원대 경유 | 평동 출발
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildDirectionToggle(
                          "미호종점 출발",
                          _selected913Tab == 0,
                          () => setState(() {
                            _selected913Tab = 0;
                            _selectedStopOffset = 0;
                          }),
                          isDark,
                          primary,
                        ),
                      ),
                      Expanded(
                        child: _buildDirectionToggle(
                          "교원대 경유",
                          _selected913Tab == 1,
                          () => setState(() {
                            _selected913Tab = 1;
                            _selectedStopOffset = 0;
                          }),
                          isDark,
                          primary,
                        ),
                      ),
                      Expanded(
                        child: _buildDirectionToggle(
                          "평동 출발",
                          _selected913Tab == 2,
                          () => setState(() {
                            _selected913Tab = 2;
                            _selectedStopOffset = 0;
                          }),
                          isDark,
                          primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selected913Tab == 1) ...[
                  const SizedBox(height: 10),
                  // 교원대 경유 상행/하행 서브 토글
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? primary.withValues(alpha: 0.15)
                          : primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primary.withValues(alpha: isDark ? 0.35 : 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSubDirectionToggle(
                            "상행 (미호종점 방면)",
                            _is913KnueUpbound,
                            () => setState(() => _is913KnueUpbound = true),
                            isDark,
                            primary,
                          ),
                        ),
                        Expanded(
                          child: _buildSubDirectionToggle(
                            "하행 (평동 방면)",
                            !_is913KnueUpbound,
                            () => setState(() => _is913KnueUpbound = false),
                            isDark,
                            primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primary.withOpacity(isDark ? 0.25 : 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: isDark ? Colors.white70 : primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selected913Tab == 0
                              ? "미호종점에서 평동 방면으로 출발하는 시간표입니다. (교원대까지 약 13분)"
                              : (_selected913Tab == 1
                                    ? (_is913KnueUpbound
                                          ? "교원대 정류장 통과/도착 시간표입니다. (평동 출발 ➔ 교원대 ➔ 미호종점)"
                                          : "교원대 정류장 통과/도착 시간표입니다. (미호종점 출발 ➔ 교원대 ➔ 가경터미널/평동)")
                                    : "평동에서 미호종점 방면으로 출발하는 시간표입니다. (교원대까지 약 50분)"),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // 기존 513, 514, 518 2개 탭
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildDirectionToggle(
                          _getOriginName(),
                          !_isToSchool,
                          () => setState(() {
                            _isToSchool = false;
                            _selectedStopOffset = 0;
                          }),
                          isDark,
                          primary,
                        ),
                      ),
                      Expanded(
                        child: _buildDirectionToggle(
                          _getTerminusName(),
                          _isToSchool,
                          () => setState(() {
                            _isToSchool = true;
                            _selectedStopOffset = 0;
                          }),
                          isDark,
                          primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isToSchool &&
                    (_boardingStops[_selectedBus]?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "교통상황에 따라 5~10분 정도 차이가 날 수 있습니다.",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _boardingStops[_selectedBus]!.entries.map((
                        entry,
                      ) {
                        final isSelected = _selectedStopOffset == entry.value;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedStopOffset = entry.value),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primary
                                  : (isDark
                                        ? Colors.grey.shade800
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? primary
                                    : (isDark
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade400),
                              ),
                            ),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (!_isToSchool)
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        "교원대 정문은 약 1분 후 도착합니다.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            itemCount: timeList.isEmpty ? 0 : timeList.length + 1,
            itemBuilder: (context, index) {
              if (index == timeList.length) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 24),
                  child: KnueNativeAdCard(isCompact: true, placement: 'bus'),
                );
              }
              final time = timeList[index];
              final subInfo = subInfoList[index];
              int busMinutes = 0;
              try {
                final parts = time.split(":");
                busMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
              } catch (e) {
                return const SizedBox();
              }

              bool passed = false;
              if (nextBusIndex == -1)
                passed = true;
              else
                passed = index < nextBusIndex;
              final isNext = index == nextBusIndex;

              String remainText = "";
              int diff = 0;
              if (isNext) {
                diff = busMinutes - currentMinutes;
                if (diff < 60)
                  remainText = "$diff분 남음";
                else
                  remainText = "1시간 이상";
              }

              IconData statusIcon = Icons.access_time_filled;
              bool isWalking = false;
              bool isRunning = false;
              if (isNext) {
                if (diff <= 5) {
                  statusIcon = Icons.directions_run;
                  isRunning = true;
                } else if (diff <= 20) {
                  statusIcon = Icons.directions_walk;
                  isWalking = true;
                } else {
                  statusIcon = Icons.directions_walk;
                }
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  // "다음 버스" 카드 배경. 8%는 실제 폰 화면에서 거의
                  // 흰 배경과 구분이 안 갈 만큼 옅어서("물 빠진" 느낌) 14%로 올렸다.
                  color: isNext
                      ? (isDark
                            ? primary.withOpacity(0.2)
                            : primary.withOpacity(0.14))
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: isNext
                      ? Border.all(color: primary, width: 2)
                      : Border.all(
                          color: isDark ? Colors.white12 : Colors.transparent,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: isNext
                          ? primary.withOpacity(isDark ? 0.1 : 0.05)
                          : Colors.black.withOpacity(isDark ? 0.15 : 0.015),
                      blurRadius: isNext ? 32 : 12,
                      offset: Offset(0, isNext ? 6 : 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _AnimatedPersonIcon(
                          icon: statusIcon,
                          color: isNext
                              ? (isDark ? Colors.white : primary)
                              : (passed
                                    ? Colors.grey
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black54)),
                          size: isNext ? 26 : 20,
                          isWalking: isWalking,
                          isRunning: isRunning,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: isNext ? 22 : 17.5,
                                    fontWeight: isNext
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    letterSpacing: isNext ? -0.6 : -0.3,
                                    // 시각은 자리수 폭을 고정해 세로로 줄이 맞게.
                                    fontFeatures: KnueTokens.tabularFigures,
                                    color: passed
                                        ? Colors.grey
                                        : isNext
                                        ? (isDark
                                              ? Colors.white
                                              : Colors.black87)
                                        // 다음 차 외에는 한 단계 물려 위계를 만든다.
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black.withValues(
                                                  alpha: 0.62,
                                                )),
                                    decoration: passed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (!passed) ...[
                                  const SizedBox(width: 8),
                                  Builder(
                                    builder: (context) {
                                      final alarmKey =
                                          "${_selectedBus}:$directionKey:${_isWeekend ? 'hol' : 'wkd'}:$time";
                                      final isAlarmSet = _scheduledAlarms
                                          .containsKey(alarmKey);

                                      return GestureDetector(
                                        onTap: () => _showAlarmDialog(
                                          time,
                                          busMinutes,
                                          customDirectionKey: directionKey,
                                        ),
                                        child: Icon(
                                          isAlarmSet
                                              ? Icons
                                                    .notifications_active_rounded
                                              : Icons
                                                    .notifications_none_rounded,
                                          size: 20,
                                          color: isAlarmSet
                                              ? KnueTokens.warm(isDark)
                                              : (isNext
                                                    ? (isDark
                                                          ? Colors.white70
                                                          : primary.withOpacity(
                                                              0.7,
                                                            ))
                                                    : (isDark
                                                          ? Colors.white38
                                                          : Colors
                                                                .grey
                                                                .shade400)),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                            if (subInfo != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                subInfo,
                                style: TextStyle(
                                  fontSize: isNext ? 12 : 11.5,
                                  fontWeight: isNext
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: passed
                                      ? Colors.grey.shade500
                                      : isNext
                                      ? (isDark ? Colors.white70 : primary)
                                      : (isDark
                                            ? Colors.white54
                                            : Colors.grey.shade600),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (isNext)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          // 다음 버스까지 남은 시간 — 곧 출발한다는 걸 강조하려고
                          // 빨간색으로. (다른 화면의 "임박 신호"는 계속 앰버를 쓴다 —
                          // 이 카드만 명시적으로 빨간색을 요청받았다.)
                          color: isDark
                              ? const Color(0xFFEF4444)
                              : const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          remainText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFeatures: KnueTokens.tabularFigures,
                          ),
                        ),
                      )
                    else if (passed)
                      const Text(
                        "출발함",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAlarmDialog(
    String timeStr,
    int busMinutes, {
    String? customDirectionKey,
  }) {
    final dirKey = customDirectionKey ?? (_isToSchool ? 'in' : 'out');
    final alarmKey =
        "${_selectedBus}:$dirKey:${_isWeekend ? 'hol' : 'wkd'}:$timeStr";
    final isAlarmSet = _scheduledAlarms.containsKey(alarmKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isAlarmSet
                  ? Icons.notifications_active_rounded
                  : Icons.alarm_add_rounded,
              color: isAlarmSet
                  ? Colors.orangeAccent
                  : Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 10),
            Text(
              isAlarmSet
                  ? '설정된 알람 ($timeStr)'
                  : '$_selectedBus번 알람 설정 ($timeStr)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isAlarmSet) ...[
              const Text('이미 알람이 설정되어 있습니다.', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _cancelBusAlarm(alarmKey);
                },
                child: const Text(
                  '알람 취소하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ] else ...[
              const Text('몇 분 전에 알려드릴까요?', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              ...[5, 10, 15].map(
                (min) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Theme.of(
                        context,
                      ).primaryColor.withOpacity(0.1),
                      foregroundColor: Theme.of(context).primaryColor,
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _scheduleBusAlarm(
                        timeStr,
                        busMinutes,
                        min,
                        customDirectionKey: dirKey,
                      );
                    },
                    child: Text(
                      '$min분 전',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  void _cancelBusAlarm(String alarmKey) async {
    final notificationId = _scheduledAlarms[alarmKey];
    if (notificationId != null) {
      await NotificationService().cancelAlarm(notificationId);
      if (!mounted) return;
      setState(() {
        _scheduledAlarms.remove(alarmKey);
      });
      _saveAlarms();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('알람이 취소되었습니다.'),
            showCloseIcon: true,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _scheduleBusAlarm(
    String timeStr,
    int busMinutes,
    int minutesBefore, {
    String? customDirectionKey,
  }) async {
    final dirKey = customDirectionKey ?? (_isToSchool ? 'in' : 'out');
    final alarmKey =
        "${_selectedBus}:$dirKey:${_isWeekend ? 'hol' : 'wkd'}:$timeStr";
    final now = DateTime.now();
    final parts = timeStr.split(':');
    if (parts.length != 2) return;

    int hour = int.tryParse(parts[0]) ?? 0;
    int minute = int.tryParse(parts[1]) ?? 0;

    DateTime scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledTime.isBefore(now)) {
      if (hour < 4 && now.hour > 18) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      } else if (scheduledTime.difference(now).inMinutes < -1) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 지난 시간입니다.')));
        return;
      }
    }

    DateTime alarmTime = scheduledTime.subtract(
      Duration(minutes: minutesBefore),
    );

    if (alarmTime.isBefore(now)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설정하려는 알람 시간이 이미 지났습니다.')));
      return;
    }

    final formattedAlarmTime =
        '${alarmTime.hour.toString().padLeft(2, '0')}:${alarmTime.minute.toString().padLeft(2, '0')}';
    final id = now.millisecondsSinceEpoch % 100000;

    await NotificationService().scheduleAlarm(
      id: id,
      title: '🚌 버스 출발 알림!',
      body:
          '[$timeStr]에 출발하는 $_selectedBus번 버스가 $minutesBefore분 뒤에 떠나요! 얼른 준비하세요! 🏃💨',
      scheduledTime: alarmTime,
    );

    if (!mounted) return;
    setState(() {
      _scheduledAlarms[alarmKey] = id;
    });
    _saveAlarms();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$formattedAlarmTime에 알람이 울립니다. ($minutesBefore분 전)'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Widget _buildDirectionToggle(
    String text,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
    Color primary,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildDayChip(
    String text,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
    Color primary,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? primary
                : (isDark
                      ? Colors.grey.shade600
                      : Colors.grey.withOpacity(0.5)),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.grey),
          ),
        ),
      ),
    );
  }
}

// 출발 시간에 따른 사람 아이콘 애니메이션 위젯
class _AnimatedPersonIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool isWalking;
  final bool isRunning;

  const _AnimatedPersonIcon({
    required this.icon,
    required this.color,
    required this.size,
    this.isWalking = false,
    this.isRunning = false,
  });

  @override
  _AnimatedPersonIconState createState() => _AnimatedPersonIconState();
}

class _AnimatedPersonIconState extends State<_AnimatedPersonIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isRunning ? 400 : 1000),
    );
    if (widget.isWalking || widget.isRunning) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_AnimatedPersonIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isWalking != oldWidget.isWalking ||
        widget.isRunning != oldWidget.isRunning) {
      _controller.duration = Duration(
        milliseconds: widget.isRunning ? 400 : 1000,
      );
      if (widget.isWalking || widget.isRunning) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double angle = 0;
        double dx = 0;
        double dy = 0;
        double scaleX = 1.0;
        double scaleY = 1.0;

        final double val = _controller.value;
        // Curves를 활용해 더 자연스러운 가감속 구현
        final double sinVal = math.sin(val * math.pi * 2);
        final double absCosVal = math.cos(val * math.pi).abs();

        if (widget.isRunning) {
          // [급하게 뛰기]
          // 앞으로 기울어짐 (기본 기울기 + 역동적 변화)
          angle = 0.25 + (0.1 * sinVal);
          // 상하 바운스 (포물선 느낌)
          dy = -6 * absCosVal;
          // 좌우 흔들림
          dx = 2 * sinVal;
          // 신축 효과 (Stretch & Squash)
          scaleY = 1.0 + (0.15 * absCosVal);
          scaleX = 1.0 - (0.1 * absCosVal);
        } else if (widget.isWalking) {
          // [살살 걷기]
          // 약간의 회전
          angle = 0.1 * sinVal;
          // 가벼운 상하 bobbing
          dy = -2 * absCosVal;
          // 앞뒤로 살짝 움직임
          dx = 1.5 * sinVal;
        }

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: Icon(widget.icon, color: widget.color, size: widget.size),
            ),
          ),
        );
      },
    );
  }
}
