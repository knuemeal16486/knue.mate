// 버스 탭 [실시간 위치] 맨 위 카드 — 내 위치에서 가장 가까운 정류장의 실시간
// 도착 정보(2026-11-12). 로직은 nearby_stop.dart(순수 함수 + 테스트).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'bus_model.dart';
import 'bus_service.dart';
import 'nearby_stop.dart';
import 'ui_utils.dart';

enum _NearbyState { locating, serviceOff, denied, deniedForever, noStops, error, ready }

class NearbyStopCard extends StatefulWidget {
  final bool isDark;

  /// 화면 확인용(test/bus_preview.dart). 넣으면 위치·네트워크 없이 이 값을 그린다.
  @visibleForTesting
  final (List<NearbyStop>, List<StopArrival>)? preview;

  const NearbyStopCard({super.key, required this.isDark, this.preview});

  @override
  State<NearbyStopCard> createState() => NearbyStopCardState();
}

class NearbyStopCardState extends State<NearbyStopCard> with WidgetsBindingObserver {
  /// 이번 실행에서 이미 권한을 물었는지. 거절한 사람에게 탭을 열 때마다
  /// 다시 묻지 않는다(버튼으로만).
  static bool _askedThisSession = false;

  static const Duration _tick = Duration(seconds: 15);
  static const Duration _refreshEvery = Duration(seconds: 30);
  static const int _collapsedCount = 5;

  /// 앱 실행 동안 하나만 둔다 — 시간표 탭에 다녀오면 이 카드가 새로 만들어지는데,
  /// 그때마다 근처 정류장을 다시 묻지 않게(지난 위치에서 100m 안이면 재사용).
  static final NearbyStopService _service = NearbyStopService(apiKey: BusService.apiKey);

  /// 마지막으로 고른 정류장. 탭에 다시 들어와도 그 정류장을 보여 준다.
  static String? _lastSelectedId;

  _NearbyState _state = _NearbyState.locating;
  List<NearbyStop> _stops = const [];
  String? _selectedId = _lastSelectedId;
  List<StopArrival> _arrivals = const [];
  DateTime? _fetchedAt;
  bool _busy = false;
  bool _expanded = false;
  Timer? _timer;

  NearbyStop? get _selected {
    for (final s in _stops) {
      if (s.nodeId == _selectedId) return s;
    }
    return _stops.isEmpty ? null : _stops.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final preview = widget.preview;
    if (preview != null) {
      _stops = preview.$1;
      _selectedId = preview.$1.isEmpty ? null : preview.$1.first.nodeId;
      _arrivals = preview.$2;
      _fetchedAt = DateTime.now();
      _state = _NearbyState.ready;
      return;
    }
    _locateAndLoad(askPermission: !_askedThisSession);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.preview != null) return;
    if (state == AppLifecycleState.resumed) {
      // 설정에서 권한·위치를 켜고 돌아왔을 수 있다.
      _locateAndLoad(askPermission: false);
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final at = _fetchedAt;
      if (_state == _NearbyState.ready &&
          (at == null || DateTime.now().difference(at) >= _refreshEvery)) {
        _loadArrivals();
      } else {
        setState(() {}); // "n분 후"를 다시 센다.
      }
    });
  }

  /// 당겨서 새로 고침 — 위치도 다시 잡고 도착 정보를 새로 받는다.
  Future<void> refresh() => _locateAndLoad(askPermission: false, force: true);

  void _set(_NearbyState s) {
    if (mounted) setState(() => _state = s);
  }

  Future<void> _locateAndLoad({required bool askPermission, bool force = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(_NearbyState.serviceOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && askPermission) {
        _askedThisSession = true;
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _set(_NearbyState.deniedForever);
        return;
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        _set(_NearbyState.denied);
        return;
      }
      if (_stops.isEmpty) _set(_NearbyState.locating);

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        _set(_NearbyState.error);
        return;
      }

      final stops = await _service.nearbyStops(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (stops.isEmpty) {
        setState(() {
          _stops = const [];
          _state = _NearbyState.noStops;
        });
        return;
      }
      setState(() {
        _stops = stops;
        // 고른 정류장이 여전히 근처에 있으면 그대로 둔다.
        if (!stops.any((s) => s.nodeId == _selectedId)) {
          _selectedId = _lastSelectedId = stops.first.nodeId;
          _arrivals = const [];
          _fetchedAt = null;
        }
      });
      await _loadArrivals(force: force, guard: false);
    } catch (e) {
      debugPrint('NearbyStopCard: $e');
      if (_stops.isEmpty) _set(_NearbyState.error);
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadArrivals({bool force = false, bool guard = true}) async {
    final stop = _selected;
    if (stop == null) return;
    if (guard) {
      if (_busy) return;
      _busy = true;
    }
    try {
      final (at, list) = await _service.arrivals(stop, force: force);
      if (!mounted || stop.nodeId != _selected?.nodeId) return;
      setState(() {
        _arrivals = list;
        _fetchedAt = at;
        _state = _NearbyState.ready;
      });
    } catch (e) {
      debugPrint('NearbyStopCard arrivals: $e');
      // 지난 값이 있으면 그대로 둔다.
      if (_fetchedAt == null) _set(_NearbyState.error);
    } finally {
      if (guard) _busy = false;
    }
  }

  void _select(NearbyStop s) {
    if (s.nodeId == _selectedId) return;
    setState(() {
      _selectedId = _lastSelectedId = s.nodeId;
      _arrivals = const [];
      _fetchedAt = null;
      _expanded = false;
    });
    // 다른 갱신이 돌고 있어도 기다리지 않는다 — 결과는 정류장이 맞을 때만 쓴다.
    _loadArrivals(guard: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        decoration: BoxDecoration(
          color: KnueTokens.surface(isDark),
          borderRadius: BorderRadius.circular(KnueTokens.radiusCard),
          border: Border.all(color: KnueTokens.hairline(isDark), width: 0.5),
          boxShadow: KnueTokens.cardShadow(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(isDark),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _body(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(Icons.near_me_rounded, size: 16, color: primary),
        const SizedBox(width: 6),
        Text(
          '가까운 정류장',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KnueTokens.caption(isDark)),
        ),
        const Spacer(),
        if (_state == _NearbyState.ready || _state == _NearbyState.error)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: '새로 고침',
            onPressed: _busy ? null : refresh,
            icon: Icon(Icons.refresh_rounded, color: KnueTokens.caption(isDark)),
          ),
      ],
    );
  }

  Widget _body(bool isDark) {
    switch (_state) {
      case _NearbyState.locating:
        return _message(isDark, Icons.my_location_rounded, '내 위치에서 가까운 정류장을 찾고 있어요…', loading: true);
      case _NearbyState.serviceOff:
        return _message(isDark, Icons.location_disabled_rounded, '위치 서비스가 꺼져 있어요.',
            action: ('위치 켜기', () => Geolocator.openLocationSettings()));
      case _NearbyState.denied:
        return _message(isDark, Icons.location_off_rounded, '위치 권한을 허용하면 가장 가까운 정류장의 버스를 보여 드려요.',
            action: ('권한 허용', () {
              _askedThisSession = true;
              _locateAndLoad(askPermission: true);
            }));
      case _NearbyState.deniedForever:
        return _message(isDark, Icons.location_off_rounded, '위치 권한이 꺼져 있어요. 설정에서 허용해 주세요.',
            action: ('설정 열기', () => Geolocator.openAppSettings()));
      case _NearbyState.noStops:
        return _message(isDark, Icons.wrong_location_rounded,
            '${formatStopDistance(kNearbyStopMaxMeters)} 안에 버스 정류장이 없어요.');
      case _NearbyState.error:
        return _message(isDark, Icons.wifi_off_rounded, '정류장 정보를 불러오지 못했어요.',
            action: ('다시 시도', () => refresh()));
      case _NearbyState.ready:
        return _ready(isDark);
    }
  }

  Widget _message(bool isDark, IconData icon, String text,
      {bool loading = false, (String, void Function())? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(icon, size: 18, color: KnueTokens.caption(isDark)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark), height: 1.35)),
          ),
          if (action != null)
            TextButton(onPressed: action.$2, child: Text(action.$1)),
        ],
      ),
    );
  }

  Widget _ready(bool isDark) {
    final stop = _selected!;
    final primary = Theme.of(context).colorScheme.primary;
    final elapsed = _fetchedAt == null ? Duration.zero : DateTime.now().difference(_fetchedAt!);
    final shown = _expanded ? _arrivals : _arrivals.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 정류장 이름 · 번호 · 거리
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                stop.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Text('· ${formatStopDistance(stop.distanceMeters)}',
                style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark))),
          ],
        ),
        // 어느 쪽 정류장인지 — 자주 타는 곳은 "월탄1리 방면"(다음 정류장),
        // 나머지는 표지판 번호.
        if (stopHeadingOrNumber(stop.nodeId, stop.nodeNo).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              stopHeadingOrNumber(stop.nodeId, stop.nodeNo),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
            ),
          ),

        // 근처 다른 정류장(길 건너 같은 이름 포함)
        if (_stops.length > 1) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _stops.take(kNearbyStopChoices))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        [
                          s.name,
                          if (stopHeadingOrNumber(s.nodeId, s.nodeNo).isNotEmpty)
                            stopHeadingOrNumber(s.nodeId, s.nodeNo),
                          formatStopDistance(s.distanceMeters),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: s.nodeId == stop.nodeId,
                      onSelected: (_) => _select(s),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),

        if (_fetchedAt == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_arrivals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('지금 이 정류장으로 오는 버스 정보가 없어요.',
                style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark))),
          )
        else
          for (final a in shown) _arrivalRow(isDark, primary, a, elapsed),

        if (_arrivals.length > _collapsedCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '접기' : '${_arrivals.length - _collapsedCount}대 더 보기'),
            ),
          ),

        const SizedBox(height: 4),
        Text(
          _fetchedAt == null ? '' : '도착 예정 시간 · ${_ago(elapsed)} 갱신',
          style: TextStyle(fontSize: 11, color: KnueTokens.caption(isDark)),
        ),
      ],
    );
  }

  String _ago(Duration d) {
    if (d.inSeconds < 10) return '방금';
    if (d.inSeconds < 60) return '${d.inSeconds}초 전';
    return '${d.inMinutes}분 전';
  }

  Widget _arrivalRow(bool isDark, Color primary, StopArrival a, Duration elapsed) {
    final badgeColor = a.isAppRoute ? primary : KnueTokens.caption(isDark);
    final soon = a.arrivalSeconds - elapsed.inSeconds < 180;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              a.routeNo,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: badgeColor),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatArrivalIn(a.arrivalSeconds, elapsed),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: KnueTokens.tabularFigures,
              color: soon ? KnueTokens.warm(isDark) : null,
            ),
          ),
          const SizedBox(width: 8),
          if (a.stopsAway != null)
            Text('${a.stopsAway}정거장 전', style: TextStyle(fontSize: 12, color: KnueTokens.caption(isDark))),
          const Spacer(),
          if (a.lowFloor)
            Text('저상', style: TextStyle(fontSize: 11, color: KnueTokens.caption(isDark))),
        ],
      ),
    );
  }
}
