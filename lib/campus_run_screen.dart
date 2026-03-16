import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';
import 'meal_screen.dart';

class Classroom {
  final String name;
  final double lat;
  final double lng;
  Classroom(this.name, this.lat, this.lng);
}

class CampusRunScreen extends StatefulWidget {
  const CampusRunScreen({super.key});
  @override
  State<CampusRunScreen> createState() => _CampusRunScreenState();
}

class _CampusRunScreenState extends State<CampusRunScreen>
    with SingleTickerProviderStateMixin {
  final List<Classroom> _allClassrooms = [
    Classroom("다정관", 36.613286, 127.359914),
    Classroom("다감관", 36.614016, 127.359718),
    Classroom("기숙사 식당", 36.612763, 127.360502),
    Classroom("종합교육관", 36.610537, 127.361035),
    Classroom("인문과학관", 36.610517, 127.360008),
    Classroom("호연관", 36.609509, 127.358781),
    Classroom("미래도서관", 36.609283, 127.359147),
    Classroom("자연과학관", 36.608424, 127.361631),
    Classroom("융합과학관", 36.609173, 127.361614),
    Classroom("응용과학관", 36.607976, 127.362114),
    Classroom("학생회관", 36.608378, 127.359853),
    Classroom("미술관", 36.607686, 127.360534),
    Classroom("음악관", 36.607311, 127.361410),
    Classroom("교원문화관", 36.607609, 127.358611),
    Classroom("교육박물관", 36.607130, 127.357262),
    Classroom("대학본부", 36.608583, 127.357278),
    Classroom("버스정류장", 36.608214, 127.358542),
    Classroom("대학원", 36.6095, 127.3475),
    Classroom("교육연구관", 36.609765, 127.357924),
    Classroom("한국교원대 정문", 36.606836, 127.354341),
    Classroom("한국교원대 후문", 36.615347, 127.356506),
    Classroom("한국교원대 쪽문", 36.614480, 127.360430),
    Classroom("제2 체육관", 36.609988, 127.362383),
    Classroom("제1 체육관", 36.610104, 127.362667),
    Classroom("복지관", 36.612863, 127.359115),
    Classroom("학군단", 36.605897, 127.360595),
    Classroom("교수아파트", 36.611975, 127.352617),
    Classroom("국제연수관", 36.613622, 127.357594),
    Classroom("함덕당", 36.611697, 127.357418),
    Classroom("교원연수관", 36.612346, 127.357202),
    Classroom("교양학관", 36.609372, 127.360774),
  ];

  final Set<String> _favoriteNames = {"한국교원대 정문", "버스정류장"};
  Classroom? _targetClassroom;
  StreamSubscription<Position>? _positionStream;
  Timer? _timer;
  final List<double> _recentSpeeds = [];
  final double _pathFactor = 1.3;

  double _currentSpeedKmh = 0.0;
  double _distanceRemaining = 0.0;
  int _estimatedSeconds = 0;
  bool _isRunning = false;
  String _statusMessage = "목표 강의실을 선택하세요";
  DateTime _currentTime = DateTime.now();
  DateTime? _runStartTime;
  Duration _elapsedDuration = Duration.zero;
  bool _isPaceMode = false;
  int? _targetDurationSeconds;
  double _requiredSpeedKmh = 0.0;
  final double _walkingSpeedMs = 1.11;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
          if (_isRunning && _runStartTime != null) {
            _elapsedDuration = DateTime.now().difference(_runStartTime!);
            if (_targetDurationSeconds != null) _recalculateRequiredSpeed();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Color _getNeonVariant(Color baseColor) {
    final hsv = HSVColor.fromColor(baseColor);
    return hsv.withSaturation(1.0).withValue(1.0).toColor();
  }

  void _showClassroomSelector(Color neonColor) {
    if (_isRunning) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: neonColor.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _ClassroomList(
                  allClassrooms: _allClassrooms,
                  favoriteNames: _favoriteNames,
                  neonColor: neonColor,
                  onSelect: (room) {
                    setState(() {
                      _targetClassroom = room;
                      _distanceRemaining = 0;
                      _estimatedSeconds = 0;
                      _statusMessage = "준비 완료";
                    });
                    Navigator.pop(context);
                  },
                  onToggleFavorite: (name) {
                    setState(() {
                      if (_favoriteNames.contains(name)) {
                        _favoriteNames.remove(name);
                      } else {
                        _favoriteNames.add(name);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTargetSettingDialog(Color neonColor) {
    if (_isRunning) return;
    int inputMinutes = 5;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text("목표 시간 설정", style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setStateSB) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: neonColor),
                    onPressed: () {
                      if (inputMinutes > 1) setStateSB(() => inputMinutes--);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "$inputMinutes분",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, color: neonColor),
                    onPressed: () {
                      if (inputMinutes < 60) setStateSB(() => inputMinutes++);
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _targetDurationSeconds = null);
                Navigator.pop(context);
              },
              child: const Text("해제", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _targetDurationSeconds = inputMinutes * 60);
                Navigator.pop(context);
              },
              child: Text(
                "설정",
                style: TextStyle(color: neonColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleTracking() async {
    if (_targetClassroom == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("먼저 목표 강의실을 선택해주세요!")));
      return;
    }

    if (_isRunning) {
      _positionStream?.cancel();
      setState(() {
        _isRunning = false;
        _currentSpeedKmh = 0;
        _statusMessage = "안내 종료";
        _recentSpeeds.clear();
      });
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          showToast(context, "위치 권한이 필요합니다.");
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        showToast(context, "위치 서비스를 활성화해주세요.");
        return;
      }

      setState(() {
        _isRunning = true;
        _statusMessage = "GPS 신호 수신 중...";
        _runStartTime = DateTime.now();
        _elapsedDuration = Duration.zero;
        _requiredSpeedKmh = 0.0;
        _recentSpeeds.clear();
      });

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              _updateMetrics(position);
            },
            onError: (error) {
              print("위치 오류: $error");
              if (mounted) {
                setState(() {
                  _statusMessage = "위치 정보를 가져올 수 없습니다";
                });
              }
            },
          );
    }
  }

  void _recalculateRequiredSpeed() {
    if (_runStartTime == null || _targetDurationSeconds == null) return;
    final remainTime = _targetDurationSeconds! - _elapsedDuration.inSeconds;
    setState(() {
      if (remainTime <= 0) {
        _requiredSpeedKmh = 999.0;
      } else {
        double reqSpeedMs = _distanceRemaining / remainTime;
        _requiredSpeedKmh = reqSpeedMs * 3.6;
      }
    });
  }

  void _updateMetrics(Position position) {
    if (_targetClassroom == null) return;

    double straightDist = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _targetClassroom!.lat,
      _targetClassroom!.lng,
    );

    double factor = straightDist < 30 ? 1.1 : _pathFactor;
    double realDist = straightDist * factor;

    double rawSpeed = position.speed < 0 ? 0 : position.speed;
    _recentSpeeds.add(rawSpeed);
    if (_recentSpeeds.length > 5) _recentSpeeds.removeAt(0);

    double avgSpeedMs = _recentSpeeds.isNotEmpty
        ? _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length
        : 0.0;

    double calcSpeed = avgSpeedMs < 0.5 ? _walkingSpeedMs : avgSpeedMs;
    int seconds = (realDist / calcSpeed).ceil();

    if (mounted) {
      setState(() {
        _distanceRemaining = realDist;
        _currentSpeedKmh = avgSpeedMs * 3.6;
        _estimatedSeconds = seconds;

        if (straightDist < 20) {
          _statusMessage = "도착했습니다! 🏁";
          _isRunning = false;
          _positionStream?.cancel();
          _recentSpeeds.clear();
        } else {
          _statusMessage = "목표까지 달리는 중!";
        }
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds > 3600) return "60분+";
    int min = totalSeconds ~/ 60;
    int sec = totalSeconds % 60;
    return "$min분 ${sec.toString().padLeft(2, '0')}초";
  }

  String _getSpeedOrPaceString() {
    if (!_isPaceMode) return _currentSpeedKmh.toStringAsFixed(1);
    if (_currentSpeedKmh < 0.5) return "-'--''";
    double pace = 60 / _currentSpeedKmh;
    int min = pace.floor();
    int sec = ((pace - min) * 60).round();
    return "$min'${sec.toString().padLeft(2, '0')}''";
  }

  String _getRequiredSpeedString() {
    if (_requiredSpeedKmh >= 999.0) return "늦음!";
    if (_requiredSpeedKmh <= 0.0) return "-";
    return "${_requiredSpeedKmh.toStringAsFixed(1)} km/h";
  }

  String _formatTimeHHMMSS(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}시 ${dt.minute.toString().padLeft(2, '0')}분 ${dt.second.toString().padLeft(2, '0')}초";

  String _formatTimeHHMM(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}시 ${dt.minute.toString().padLeft(2, '0')}분";

  String _formatDurationMMSS(Duration d) =>
      "${d.inMinutes.toString().padLeft(2, '0')}분 ${(d.inSeconds % 60).toString().padLeft(2, '0')}초";

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, primaryColor, child) {
        final neonColor = _getNeonVariant(primaryColor);
        const bgDark = Color(0xFF121212);
        const textWhite = Colors.white;

        final bool isTargetSelected = _targetClassroom != null;
        final isArrived = _distanceRemaining < 20 && _distanceRemaining > 0;

        return Scaffold(
          backgroundColor: bgDark,
          appBar: AppBar(
            backgroundColor: bgDark,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: textWhite),
              onPressed: () => showAppSwitchDialog(context, "캠퍼스런"),
            ),
            title: const Text(
              "CAMPUS RUN",
              style: TextStyle(
                color: textWhite,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
            centerTitle: true,
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "현재 시각  ${_formatTimeHHMM(_currentTime)}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 강의실 선택
                GestureDetector(
                  onTap: () => _showClassroomSelector(neonColor),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: isTargetSelected ? 12 : 18,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isTargetSelected
                            ? neonColor.withOpacity(0.5)
                            : Colors.white10,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "목표",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                              if (!isTargetSelected) const SizedBox(height: 4),
                              Flexible(
                                child: Text(
                                  _targetClassroom?.name ?? "강의실을 선택하세요",
                                  style: TextStyle(
                                    color: _targetClassroom == null
                                        ? Colors.grey
                                        : textWhite,
                                    fontSize: isTargetSelected ? 16 : 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.location_on, color: neonColor),
                      ],
                    ),
                  ),
                ),

                if (!_isRunning)
                  GestureDetector(
                    onTap: () => _showTargetSettingDialog(neonColor),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: neonColor.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(20),
                        color: _targetDurationSeconds != null
                            ? neonColor.withOpacity(0.1)
                            : Colors.transparent,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 18,
                            color: _targetDurationSeconds != null
                                ? neonColor
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _targetDurationSeconds != null
                                ? "목표: ${(_targetDurationSeconds! / 60).round()}분 안에 도착하기"
                                : "타이머 설정 (선택)",
                            style: TextStyle(
                              color: _targetDurationSeconds != null
                                  ? neonColor
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_runStartTime != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMiniStat(
                        "시작 시각",
                        _formatTimeHHMMSS(_runStartTime!),
                        Colors.white,
                      ),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _buildMiniStat(
                        "경과 시간",
                        _formatDurationMMSS(_elapsedDuration),
                        neonColor,
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 30),
                ] else ...[
                  const Spacer(),
                ],
                Text(
                  "예상 도착까지",
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: isArrived
                      ? _pulseAnimation
                      : AlwaysStoppedAnimation(1.0),
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isArrived ? _pulseAnimation.value : 1.0,
                      child: Text(
                        _formatDuration(_estimatedSeconds),
                        style: const TextStyle(
                          color: textWhite,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2.0,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    );
                  },
                ),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: neonColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricBlock(
                      "남은 거리",
                      "${_distanceRemaining.toStringAsFixed(0)}m",
                      textWhite,
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _isPaceMode = !_isPaceMode),
                      child: _buildMetricBlock(
                        _isPaceMode ? "현재 페이스" : "현재 속도",
                        _getSpeedOrPaceString(),
                        neonColor,
                        unit: _isPaceMode ? "min/km" : "km/h",
                      ),
                    ),
                  ],
                ),
                if (_targetDurationSeconds != null && _isRunning) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "목표 달성 필요 속도",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getRequiredSpeedString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                ScaleTransition(
                  scale: _isRunning
                      ? _pulseAnimation
                      : AlwaysStoppedAnimation(1.0),
                  child: GestureDetector(
                    onTap: _toggleTracking,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: _isRunning ? Colors.redAccent : neonColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRunning ? Colors.redAccent : neonColor)
                                .withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRunning ? Icons.stop : Icons.play_arrow,
                        size: 45,
                        color: _isRunning ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMetricBlock(
    String label,
    String value,
    Color valueColor, {
    String unit = "",
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// 검색 기능이 포함된 리스트 위젯
class _ClassroomList extends StatefulWidget {
  final List<Classroom> allClassrooms;
  final Set<String> favoriteNames;
  final Color neonColor;
  final Function(Classroom) onSelect;
  final Function(String) onToggleFavorite;

  const _ClassroomList({
    required this.allClassrooms,
    required this.favoriteNames,
    required this.neonColor,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  @override
  State<_ClassroomList> createState() => _ClassroomListState();
}

class _ClassroomListState extends State<_ClassroomList> {
  String _query = "";
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Classroom> filteredList = widget.allClassrooms.where((room) {
      return room.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    filteredList.sort((a, b) {
      bool isFavA = widget.favoriteNames.contains(a.name);
      bool isFavB = widget.favoriteNames.contains(b.name);
      if (isFavA && !isFavB) return -1;
      if (!isFavA && isFavB) return 1;
      return a.name.compareTo(b.name);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white),
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
            decoration: InputDecoration(
              hintText: "장소 검색...",
              hintStyle: TextStyle(color: Colors.grey[600]),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.grey[900],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filteredList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final room = filteredList[index];
              final isFav = widget.favoriteNames.contains(room.name);
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => widget.onSelect(room),
                  leading: Icon(Icons.location_on, color: Colors.grey[700]),
                  title: Text(
                    room.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : Colors.grey[600],
                    ),
                    onPressed: () {
                      widget.onToggleFavorite(room.name);
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
