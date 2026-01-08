import 'package:flutter/material.dart';
import 'constants.dart';
import 'bus_model.dart';
import 'bus_service.dart';
import 'bus_card.dart';
import 'campus_run_screen.dart';

class BusAppScreen extends StatefulWidget {
  const BusAppScreen({super.key});
  @override
  State<BusAppScreen> createState() => _BusAppScreenState();
}

class _BusAppScreenState extends State<BusAppScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  final BusService _busService = BusService();
  Future<List<BusSummary>>? _realtimeBusFuture;

  String _selectedBus = "513";
  bool _isWeekend = false;
  bool _isToSchool = false;
  int _selectedStopOffset = 0;

  // [시간표 데이터]
  final Map<String, Map<String, Map<String, List<String>>>> _busSchedules = {
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

  final Map<String, Map<String, int>> _boardingStops = {
    "513": {"고속버스터미널": 47, "사창사거리(충북대)": 35},
    "514": {"현대백화점": 44, "사창사거리(충북대)": 32, "성안길(청주대교)": 24},
    "518": {"오송역": 10, "만수공원": 5, "오송119안전센터": 3},
  };

  @override
  void initState() {
    super.initState();
    // [수정] 탭 개수 2개로 변경 (스마트 경로 제거)
    _tabController = TabController(length: 2, vsync: this);
    final weekday = DateTime.now().weekday;
    _isWeekend = (weekday == 6 || weekday == 7);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  void _refreshData() {
    if (!mounted) return;

    setState(() {
      _realtimeBusFuture = _busService
          .fetchAllBuses()
          .then((buses) => buses)
          .catchError((error) => <BusSummary>[]);

      showToast(context, "버스 정보를 업데이트했습니다.");
    });
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

  String _getTerminusName() {
    if (_selectedBus == "518") return "보건의료행정타운 출발";
    if (_selectedBus == "502") return "청주역 출발"; // 추가
    return "동부종점 출발";
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              "청람버스",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    backgroundColor: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "앱 바로가기",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 1. 청람밥상 이동 버튼
                          _AppSwitchOption(
                            icon: Icons.restaurant_menu,
                            label: "청람밥상",
                            isSelected: false,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              Navigator.pop(context); // 버스 앱 종료 -> 밥상 앱으로
                            },
                          ),
                          const SizedBox(height: 12),

                          // 2. 청람버스 (현재 화면)
                          _AppSwitchOption(
                            icon: Icons.directions_bus,
                            label: "청람버스",
                            isSelected: true, // 현재 선택됨
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _refreshData(); // 새로고침 효과
                            },
                          ),
                          const SizedBox(height: 12),

                          // 3. 캠퍼스런 이동 버튼
                          _AppSwitchOption(
                            icon: Icons.directions_run,
                            label: "캠퍼스런",
                            isSelected: false,
                            onTap: () {
                              Navigator.pop(dialogContext); // 다이얼로그 닫기
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CampusRunScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh),
                tooltip: "새로고침",
              ),
              // 추가: 예상 도착 시간 정보 버튼
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
              indicatorWeight: 3,
              tabs: const [
                Tab(text: "버스 시간표"),
                Tab(text: "실시간 위치"),
                // [수정] 스마트 경로 탭 제거됨
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTimetableTab(isDark, color),
              _buildRealtimeTab(isDark),
              // [수정] 스마트 경로 탭 뷰 제거됨
            ],
          ),
        );
      },
    );
  }

  // 실시간 탭
  Widget _buildRealtimeTab(bool isDark) {
    return Container(
      color: isDark ? Colors.black12 : const Color(0xFFF9FAFB),
      child: FutureBuilder<List<BusSummary>>(
        future: _realtimeBusFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "데이터 로드 실패\n(네트워크 확인)",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: const Text("다시 시도"),
                  ),
                ],
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.directions_bus_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "현재 운행 중인 버스가 없습니다.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: const Text("새로고침"),
                  ),
                ],
              ),
            );
          }

          final buses = snapshot.data!;
          final directBuses = buses.where((b) => b.isDirect).toList();
          final tapyeonBuses = buses.where((b) => !b.isDirect).toList();

          return RefreshIndicator(
            onRefresh: () async => _refreshData(),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                if (directBuses.isNotEmpty) ...[
                  _buildSectionHeader("교원대 직행", isDark),
                  ...directBuses.map((b) => BusCard(bus: b)),
                  const SizedBox(height: 20),
                ],

                if (tapyeonBuses.isNotEmpty) ...[
                  _buildSectionHeader("탑연삼거리 경유", isDark),
                  ...tapyeonBuses.map((b) => BusCard(bus: b)),
                  const SizedBox(height: 20),
                ],

                if (directBuses.isEmpty && tapyeonBuses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        "운행중인 버스가 없습니다.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),

                // 추가: 도착 시간 안내
                _buildArrivalInfoSection(isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  // 도착 시간 안내 섹션 (추가된 기능)
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

  // 도착 시간 정보 다이얼로그 (추가된 기능)
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
            _buildInfoItem("정거장 당 기본 시간", "2.5-3분 (노선별 상이)"),
            _buildInfoItem("시간대별 교통", "출퇴근시간 +50%"),
            _buildInfoItem("주말 영향", "주말 +20%"),
            _buildInfoItem("계절/날씨", "겨울/장마 +10-15%"),
            _buildInfoItem("추가 지연", "정거장 당 +30초"),
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

  // 섹션 헤더 위젯
  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Icon(
            Icons.label_important,
            size: 18,
            color: isDark ? Colors.white70 : Colors.blueGrey,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }

  // 시간표 탭
  Widget _buildTimetableTab(bool isDark, Color primary) {
    final directionKey = _isToSchool ? "incoming" : "outgoing";
    final dayKey = _isWeekend ? "holiday" : "weekday";
    final List<String> rawTimeList =
        _busSchedules[_selectedBus]?[directionKey]?[dayKey] ?? [];
    final List<String> timeList = rawTimeList
        .map((t) => _addMinutes(t, _selectedStopOffset))
        .toList();

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

    if (nextBusIndex != -1) _scrollToNextBus(nextBusIndex);

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ["513", "514", "518"].map((busNo) {
                  final isSelected = _selectedBus == busNo;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedBus = busNo;
                      _selectedStopOffset = 0;
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? primary
                              : Colors.grey.withOpacity(0.5),
                        ),
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
                }).toList(),
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
                        "교원문화관 출발",
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
              if (_isToSchool) ...[
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
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            itemCount: timeList.length,
            itemBuilder: (context, index) {
              final time = timeList[index];
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
              if (isNext) {
                if (diff >= 15)
                  statusIcon = Icons.directions_walk;
                else
                  statusIcon = Icons.directions_run;
              }

              return Container(
                height: isNext ? 75 : 60,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isNext
                      ? primary.withOpacity(0.2)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: isNext
                      ? Border.all(color: primary, width: 2)
                      : Border.all(
                          color: isDark ? Colors.white12 : Colors.transparent,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          statusIcon,
                          color: isNext
                              ? (isDark ? Colors.white : primary)
                              : (passed
                                    ? Colors.grey
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black54)),
                          size: isNext ? 26 : 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: isNext ? 22 : 18,
                            fontWeight: isNext
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: passed
                                ? Colors.grey
                                : (isDark ? Colors.white : Colors.black87),
                            decoration: passed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
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
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          remainText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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

class _AppSwitchOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _AppSwitchOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? (isDark ? Colors.white : Theme.of(context).primaryColor)
        : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? Colors.white24
                    : Theme.of(context).primaryColor.withOpacity(0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white54 : Theme.of(context).primaryColor)
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
                color: color,
              ),
            ),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}
