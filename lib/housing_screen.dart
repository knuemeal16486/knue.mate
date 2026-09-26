import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_auth_service.dart';
import 'constants.dart';
import 'housing_admin_screen.dart';
import 'housing_compare_sheet.dart';
import 'housing_detail_sheet.dart';
import 'housing_filter_sheet.dart';
import 'housing_iso.dart';
import 'housing_landmark.dart';
import 'housing_list_view.dart';
import 'housing_model.dart';
import 'housing_service.dart';
import 'housing_shape_edit.dart';
import 'housing_sun.dart';
import 'housing_survey.dart';
import 'building_data.dart' show BuildingData, kBuildings;
import 'campus_building_info.dart';
import 'ui_utils.dart';

/// 자취방 지도.
///
/// OpenStreetMap 타일을 쓰지 않고 건물을 직접 360도 2.5D 아이소메트릭으로 그린다.
/// 건물 모양·층수·도로는 VWorld(국토교통부) 실측 데이터를 기반으로 로컬 에셋에
/// 개발자 지도 편집 도구 모드
enum HousingEditTool {
  inspect, // 👆 일반 탐색/선택 모드
  addBlock, // ➕ 건물 블록 추가 모드
  merge, // 🔗 건물 블록 합치기 모드
  paint, // 🎨 건물 색상 칠하기 모드
  landmark, // 📍 버스정류장·정문·후문·쪽문 위치 찍기
  label, // 🏷️ 건물 이름표 숨기기/다시 보이기
  delete, // 🗑️ 건물 삭제/숨김 모드
  reshape, // ✏️ 건물 모양(외곽선) 직접 고치기 모드
}

class _EditUndoSnapshot {
  final Map<String, HousingBuildingOverride> overrides;
  final List<BaseBuilding> buildings;
  const _EditUndoSnapshot(this.overrides, this.buildings);
}

/// 다른 화면(캠퍼스맵의 장소 탭·검색)이 3D 지도에게 "여기로 옮겨 줘"라고
/// 보내는 요청. 건물 이름이나 경위도 중 하나를 준다. [seq]는 같은 곳을 다시
/// 눌러도 알림이 가게 하려고 매번 바꾼다.
@immutable
class HousingFocusRequest {
  final String? buildingName;
  final double? lat, lon;
  final int seq;
  const HousingFocusRequest.building(this.buildingName, this.seq)
      : lat = null,
        lon = null;
  const HousingFocusRequest.at(this.lat, this.lon, this.seq) : buildingName = null;
}

class HousingScreen extends StatefulWidget {
  final bool isEmbedded;

  /// 캠퍼스맵에서 연 경우: 인문과학관에서 시작하고 교내 건물에만 이름표를 단다.
  /// 위쪽 [캠퍼스]/[자취방]으로 오갈 수 있다.
  final bool campusMode;

  /// 캠퍼스맵의 장소 탭·검색이 보내는 이동 요청.
  final ValueListenable<HousingFocusRequest?>? focusRequests;

  /// 테스트에서 찍은 위치 마커를 띄워 보려고 넣는다(Firestore 없이).
  @visibleForTesting
  final List<HousingLandmark>? debugLandmarks;

  const HousingScreen({
    super.key,
    this.isEmbedded = false,
    this.campusMode = false,
    this.focusRequests,
    this.debugLandmarks,
  });

  @override
  State<HousingScreen> createState() => _HousingScreenState();
}

class _HousingScreenState extends State<HousingScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  CampusBase _base = CampusBase.empty;

  /// 에셋에 구워진 지도. 직접 추가·병합한 건물이 실시간으로 바뀔 때마다
  /// 여기에 다시 붙여 [_base]를 만든다.
  CampusBase _assetBase = CampusBase.empty;
  StreamSubscription<Map<String, HousingBuildingOverride>>? _overrideSub;
  StreamSubscription<List<BaseBuilding>>? _customSub;

  /// 개발자가 찍은 버스정류장·정문·후문·쪽문(housing_landmark.dart).
  late List<HousingLandmark> _landmarks = widget.debugLandmarks ?? const [];
  StreamSubscription<List<HousingLandmark>>? _landmarkSub;

  /// 위치 도구로 끌고 있는 마커와 그 임시 위치(지도 월드 좌표).
  String? _dragLandmarkId;
  Offset? _dragLandmarkWorld;
  bool _dragLandmarkMoved = false;
  Offset _dragLandmarkDownAt = Offset.zero;

  /// 모양 고치기 중인 건물과 아직 저장 안 한 외곽선(지상 좌표, 열린 모양).
  String? _shapeEditId;
  List<Offset>? _shapeDraft;

  /// 지금 끌고 있는 꼭짓점. 끄는 동안은 손잡이만 다시 그리고, 손을 떼면
  /// 지도 전체를 다시 계산한다(매 움직임마다 하면 버벅인다).
  int? _dragVertex;
  final GlobalKey _mapCanvasKey = GlobalKey();

  /// 컴퓨터에서 모양을 고칠 때 Esc·Delete로 꼭짓점을 지우려고 키 입력을 받는다.
  final FocusNode _mapFocus = FocusNode(debugLabel: 'housingMap');

  /// 위에서 수직으로 내려다보는 평면 시점인지(false면 3D 아이소메트릭).
  bool _topDown = false;

  // ── 시간별 그림자 ──
  bool _showShadows = false;

  /// 그림자를 볼 날짜(한국 시각)와 그날 자정 이후 분.
  ({int year, int month, int day, int minute}) _shadowDay = nowInKst();
  int _shadowMinute = 12 * 60;
  ({int sunrise, int sunset}) _sunTimes = (sunrise: 6 * 60, sunset: 18 * 60);

  /// _rebuild가 마지막으로 만든 지도 위 건물들. 시각만 바뀔 땐 지도를
  /// 통째로 다시 계산하지 않고 그림자만 새로 만든다.
  List<BaseBuilding> _effectiveBuildings = const [];
  Path? _shadowPath;

  SunPosition get _sun => sunPositionAt(
        kstToUtc(_shadowDay.year, _shadowDay.month, _shadowDay.day, _shadowMinute),
      );

  void _rebuildShadows() {
    _shadowPath = _showShadows ? buildShadowPath(_effectiveBuildings, _proj, _sun) : null;
  }

  void _toggleShadows() {
    setState(() {
      _showShadows = !_showShadows;
      if (_showShadows) {
        final now = nowInKst();
        _shadowDay = now;
        _sunTimes = sunriseSunsetKst(now.year, now.month, now.day);
        _shadowMinute = _clampToDaylight(now.minute);
      }
      _rebuildShadows();
    });
  }

  /// 밤이면 그림자가 없으니 해가 떠 있는 시각 안으로 끌어온다.
  int _clampToDaylight(int minute) =>
      minute.clamp(_sunTimes.sunrise + 20, _sunTimes.sunset - 20);

  void _setShadowMinute(int minute) {
    setState(() {
      _shadowMinute = minute;
      _rebuildShadows();
    });
  }

  /// 지금 시점의 투영. 화면의 모든 좌표 계산이 이걸 거친다.
  IsoProjection get _proj =>
      IsoProjection(scale: _scale, rotation: _rotationAngle, topDown: _topDown);

  void _toggleTopDown() {
    _persistShapeDraft();
    setState(() {
      _topDown = !_topDown;
      // 모양 편집 중이면 손잡이 높이를 새 시점에 맞게 다시 잡는다.
      _shapeDraft = null;
      _shapeEditId = null;
      _dragVertex = null;
      _selectedVertex = null;
      _rebuild();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOnTarget();
    });
  }


  /// OSM 도로 중심선(ODbL). 화면 하단에 출처를 표기한다.
  List<OsmRoad> _osmRoads = const [];
  IsoOsmRoads _isoOsmRoads = IsoOsmRoads.empty;
  bool _loading = true;

  double _rotationAngle = 0.0; // radian (0 ~ 2*PI)

  final double _scale = 2.2;

  List<IsoBuilding> _buildings = const [];
  CombinedRoads _roadPaths = CombinedRoads.empty;
  IsoTerrain _isoTerrain = IsoTerrain.empty;
  IsoLandUse _landuse = IsoLandUse.empty;
  Offset _origin = Offset.zero;
  Size _canvas = Size.zero;
  Size _viewportSize = Size.zero;

  String? _selectedId;
  BaseBuilding? _peekBuilding;
  HousingZone? _selectedZone;
  String _searchQuery = '';
  /// 건물별 요약 — 학생 제보([_reports])와 시세 조사([kHousingSurvey])를
  /// 합친 것. 시세 조사는 이름으로 건물을 찾으므로, 제보나 건물 이름이
  /// 바뀌면 [_rebuild]가 다시 만든다.
  Map<String, HousingSummary> _summaries = const {};

  /// Firestore에서 받은 학생 제보 원본(건물 id별).
  Map<String, List<HousingReport>> _reports = const {};

  /// [_summaries]를 마지막으로 만든 입력. 같으면 다시 만들지 않는다.
  (Map<String, List<HousingReport>>, String)? _summaryInput;

  /// 관리자가 바로잡은 건물 정보. 있으면 학생 제보 다수결보다 우선한다.
  Map<String, HousingBuildingOverride> _overrides = const {};

  /// "내 조건 찾기"로 건 조건. 비어 있으면 아무것도 안 거른다.
  HousingFilter _filter = const HousingFilter();

  /// 퀵 필터: 월 35만원 이하
  bool _quickMaxRent35 = false;

  /// 퀵 필터: 원룸/1.5룸만
  bool _quickRoomTypes = false;

  /// 지도 위 말풍선 시세 마커 표시 여부 (기본값: false로 끈 상태, 버튼을 누르면 켜짐)
  bool _showPriceTags = false;

  /// 캠퍼스 모드: 교내 건물에만 이름표, 자취방 필터·시세는 숨김.
  late bool _campusMode = widget.campusMode;

  /// 폰 세로 화면에서 지도 도구(시점 회전·시세·이름표·등시선·그림자·위에서 보기)를
  /// 펼쳤는지. 폰에선 기본으로 접어 두어 지도를 가리지 않게 한다.
  bool _hudExpanded = false;

  /// 폰에서 개발자 편집 도구 모음을 접었는지. 폰에선 기본으로 접어 두어
  /// 검색창·칩 줄과 함께 화면 위를 덮지 않게 한다.
  bool _devToolbarCollapsed = true;

  /// 일반 사용자용 "개발 중" 안내를 닫았는지(기기에 기억).
  bool _noticeDismissed = false;
  static const String _noticeDismissedKey = 'housing_dev_notice_dismissed';

  /// 건물 이름표를 지도에 띄울지(시세 배지처럼 켜고 끈다).
  bool _showLabels = true;

  /// 누른 건물을 기준으로 도보 등시선(3/5/10분)을 그릴지. 버튼을 켰을 때만.
  bool _showIsochrone = false;

  /// 뷰 모드: true=목록 뷰, false=지도 뷰
  bool _isListView = false;

  /// 사용자가 찜한 자취방 건물 ID 목록
  Set<String> _favoriteIds = {};

  /// 찜한 방만 필터링할지 여부
  bool _onlyFavorites = false;

  /// 목록 뷰 정렬 기준
  HousingSortType _sortType = HousingSortType.monthlyTotalAsc;

  bool get _hasActiveFilters =>
      !_filter.isEmpty ||
      _onlyFavorites ||
      _selectedZone != null ||
      _quickMaxRent35 ||
      _quickRoomTypes;

  /// 비교함 — 최대 3개 건물 ID를 담는다.
  final List<String> _compareBuildingIds = [];

  /// 개발자 지도 편집 도구 모드
  HousingEditTool _editTool = HousingEditTool.inspect;

  /// 색상 칠하기 도구에서 현재 선택된 색상
  Color _paintColor = const Color(0xFF03C75A);

  /// 칠하기 도구에서 "시스템"을 골랐는지. 고르면 [_paintColor] 대신 쓴다.
  bool _paintSystem = false;

  /// 블록 합치기(Merge) 모드에서 현재 선택된 건물 ID들
  final Set<String> _mergeSelectedBuildingIds = {};

  /// 실행 취소(Undo) 스냅샷 스택
  final List<_EditUndoSnapshot> _undoStack = [];

  void _toggleCompare(String buildingId) {
    setState(() {
      if (_compareBuildingIds.contains(buildingId)) {
        _compareBuildingIds.remove(buildingId);
      } else if (_compareBuildingIds.length < 3) {
        _compareBuildingIds.add(buildingId);
        showToast(context, '비교함에 담겼습니다 (${_compareBuildingIds.length}/3)');
      } else {
        showToast(context, '최대 3개까지 비교할 수 있어요. 먼저 하나를 빼주세요.');
      }
    });
  }

  void _showCompareSheet(bool isDark) {
    if (_compareBuildingIds.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HousingCompareSheet(
        buildings: _base.buildings.where((b) => _compareBuildingIds.contains(b.id)).toList(),
        summaries: _summaries,
        knowns: {for (final id in _compareBuildingIds) id: _resolvedKnown(id)},
        overrides: {for (final id in _compareBuildingIds) id: _overrides[id]},
        isDark: isDark,
        onRemove: (id) {
          Navigator.pop(context);
          setState(() => _compareBuildingIds.remove(id));
        },
        onClearAll: () {
          Navigator.pop(context);
          setState(() => _compareBuildingIds.clear());
        },
        onShowOnMap: (b) {
          setState(() => _isListView = false);
          _focusBuilding(b, openDetail: false);
        },
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _filter = const HousingFilter();
      _selectedZone = null;
      _onlyFavorites = false;
      _quickMaxRent35 = false;
      _quickRoomTypes = false;
      _rebuild();
    });
  }

  void _toggleQuickMaxRent35() {
    setState(() {
      _quickMaxRent35 = !_quickMaxRent35;
      if (_quickMaxRent35) {
        _filter = _filter.copyWith(maxMonthly: 35);
      } else {
        _filter = _filter.copyWith(clearMonthly: true);
      }
      _rebuild();
    });
  }

  void _toggleQuickRoomTypes() {
    setState(() {
      _quickRoomTypes = !_quickRoomTypes;
      if (_quickRoomTypes) {
        _filter = _filter.copyWith(
          roomTypes: {HousingRoomType.oneRoom, HousingRoomType.onePointFive},
        );
      } else {
        _filter = _filter.copyWith(roomTypes: {});
      }
      _rebuild();
    });
  }

  /// "내 조건 찾기" 판정을 원룸 후보 건물마다. 후보: 교내가 아니고 원룸으로
  /// 보이거나(3층 이상 등) 제보·확인 시세가 있는 건물.
  Map<String, ({HousingFilterVerdict verdict, HousingPricePoint? best})> _filterVerdicts(HousingFilter f) {
    final out = <String, ({HousingFilterVerdict verdict, HousingPricePoint? best})>{};
    for (final b in _effectiveBuildings) {
      if (b.isCampus) continue;
      final o = _overrides[b.id];
      final hasPrices = o != null && o.prices.isNotEmpty;
      if (!hasPrices && !looksLikeOneRoom(b, _summaries)) continue;
      out[b.id] = evaluateHousingFilter(_summaries[b.id], o, f);
    }
    return out;
  }

  /// 조건에 맞는 건물 id. 지도에서 강조하고, 결과 목록의 근거가 된다.
  Set<String> get _matchingBuildingIds {
    if (_filter.isEmpty) return const {};
    return {
      for (final e in _filterVerdicts(_filter).entries)
        if (housingPassesFilter(e.value.verdict, _filter)) e.key,
    };
  }

  final TransformationController _transformController =
      TransformationController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadNoticeDismissed();
    widget.focusRequests?.addListener(_onFocusRequest);
  }

  /// 캠퍼스맵 장소 탭·검색에서 온 이동 요청.
  void _onFocusRequest() {
    final r = widget.focusRequests?.value;
    if (r == null || !mounted || _loading) return;
    final name = r.buildingName;
    if (name != null) {
      final b = _findBuildingByName(name);
      if (b != null) {
        setState(() {
          _campusMode = _campusMode || b.isCampus;
          _peekBuilding = b;
          _rebuild();
        });
        _focusBuilding(b, openDetail: false);
        return;
      }
    }
    if (r.lat != null && r.lon != null) {
      // 캠퍼스맵의 위도·경도 그대로 옮겨 가고, 그 자리 건물을 고른다.
      final b = _buildingAtLatLng(r.lat!, r.lon!);
      setState(() {
        _campusMode = true;
        _peekBuilding = b;
        _rebuild();
      });
      _centerOnTarget(scale: 1.6, world: lonLatToHousingWorld(r.lon!, r.lat!));
    }
  }

  /// 3D 지도 교내 건물 id → 캠퍼스맵 건물 정보(설명·층별 호실·위도경도).
  /// 이름으로 먼저, 안 되면 캠퍼스맵 좌표로 잇는다(matchCampusInfo).
  Map<String, BuildingData> get _campusInfoById => matchCampusInfo(
        _effectiveBuildings,
        kBuildings,
        nameOf: (b) => (_overrides[b.id]?.isNamed ?? false) ? _overrides[b.id]!.name : b.officialName,
      );

  /// 캠퍼스맵이 보낸 위도·경도 자리의 건물: 그 좌표를 가진 캠퍼스맵 건물에
  /// 이어진 3D 건물, 없으면 그 점을 품은 건물.
  BaseBuilding? _buildingAtLatLng(double lat, double lon) {
    final world = lonLatToHousingWorld(lon, lat);
    for (final e in _campusInfoById.entries) {
      final p = e.value.position;
      if ((p.latitude - lat).abs() < 1e-7 && (p.longitude - lon).abs() < 1e-7) {
        for (final b in _effectiveBuildings) {
          if (b.id == e.key) return b;
        }
      }
    }
    final proj = _proj;
    return hitTestBuilding(_buildings, proj.project(world.dx, world.dy));
  }

  /// 이름(교내 공식 명칭·수정한 이름)으로 지도 위 건물을 찾는다.
  BaseBuilding? _findBuildingByName(String name) {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');
    final n = norm(name);
    BaseBuilding? prefix;
    for (final b in _effectiveBuildings) {
      final names = [
        b.officialName,
        _overrides[b.id]?.isNamed == true ? _overrides[b.id]!.name : null,
      ];
      for (final x in names) {
        if (x == null) continue;
        if (norm(x) == n) return b;
        if (prefix == null && norm(x).startsWith(n)) prefix = b;
      }
    }
    return prefix;
  }

  /// 처음 보여줄 자리: 캠퍼스 모드는 인문과학관, 아니면 원룸촌 쪽.
  void _centerHome() {
    if (_campusMode) {
      final b = _findBuildingByName('인문과학관');
      if (b != null) {
        _centerOnTarget(scale: 1.3, world: b.center);
        return;
      }
    }
    _centerOnTarget(scale: 0.88);
  }

  void _setCampusMode(bool on) {
    if (_campusMode == on) return;
    setState(() {
      _campusMode = on;
      if (on) _isListView = false;
      _peekBuilding = null;
      _selectedId = null;
      _rebuild();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerHome();
    });
  }

  Future<void> _loadNoticeDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_noticeDismissedKey) ?? false;
      if (mounted && v) setState(() => _noticeDismissed = true);
    } catch (_) {}
  }

  Future<void> _dismissNotice() async {
    setState(() => _noticeDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_noticeDismissedKey, true);
    } catch (_) {}
  }

  /// 폰 세로처럼 좁은 화면. 지도 도구를 접고 안내를 짧게 한다.
  bool get _compact => MediaQuery.sizeOf(context).width < 600;

  @override
  void dispose() {
    _overrideSub?.cancel();
    _customSub?.cancel();
    _landmarkSub?.cancel();
    _revealTimer?.cancel();
    widget.focusRequests?.removeListener(_onFocusRequest);
    _rotateRepeat?.cancel();
    // 화면을 나가도 고치던 모양은 올린다.
    _persistShapeDraft();
    _mapFocus.dispose();
    _transformController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final base = await CampusBase.load();
      final osm = await CampusBase.loadOsmRoads();

      if (!mounted) return;
      _assetBase = base;
      _base = base;
      _osmRoads = osm;

      // 개발자 수정(모양·삭제·병합·추가 건물·색)을 먼저 받고 나서 지도를
      // 보여준다. 예전엔 에셋 지도를 먼저 그린 뒤 수정이 도착하면 다시 그려서,
      // 들어갈 때마다 건물이 바뀌는 게 눈에 보였다. 두 번째 실행부터는 기기에
      // 남은 사본이 곧바로 와서 거의 기다리지 않는다. 네트워크가 느리면
      // 오래 붙잡지 않고 먼저 보여준다.
      _watchAdminEdits();
      final waitedTooLong = Completer<void>();
      _revealTimer = Timer(const Duration(milliseconds: 2500), () => _markFirst(waitedTooLong));
      await Future.any([
        Future.wait([_firstOverrides.future, _firstCustom.future]),
        waitedTooLong.future,
      ]);
      _revealTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rebuild();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerHome();
      });

      try {
        final results = await Future.wait([
          HousingService.fetchReportsByBuilding(),
          HousingService.fetchFavorites(),
        ]);
        if (!mounted) return;
        setState(() {
          _reports = (results[0] as Map<String, List<HousingReport>>?) ?? _reports;
          _favoriteIds = results[1] as Set<String>;
          _rebuild();
        });
      } catch (e) {
        debugPrint('fetchHousingDetails fallback: $e');
      }
    } catch (e, stack) {
      debugPrint('HousingScreen._load error: $e\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String buildingId) async {
    final isFav = await HousingService.toggleFavorite(buildingId);
    if (!mounted) return;
    setState(() {
      if (isFav) {
        _favoriteIds.add(buildingId);
      } else {
        _favoriteIds.remove(buildingId);
      }
      _rebuild();
    });
  }

  /// 건물 하나의 표시용 이름·구역 정보. 관리자가 덮어썼으면 그걸 쓰고,
  /// 아니면 학생 제보 다수결로 정해진 이름을 쓴다.
  OneRoomName? _resolvedKnown(String buildingId) {
    final override = _overrides[buildingId];
    if (override != null && override.isNamed) return override.toOneRoomName();
    final oneRoomId = _summaries[buildingId]?.oneRoomId;
    return oneRoomId == null ? null : kOneRoomNameById[oneRoomId];
  }

  void _centerMap() => _centerHome();

  void _centerOnTarget({double? scale, Offset? world}) {
    if (_viewportSize == Size.zero) return;
    final proj = _proj;

    Offset targetPt;
    if (world != null) {
      targetPt = proj.project(world.dx, world.dy) + _origin;
    } else if (_selectedId != null) {
      final b = _base.buildings.firstWhere(
        (elem) => elem.id == _selectedId,
        orElse: () => _base.buildings.first,
      );
      targetPt = proj.project(b.center.dx, b.center.dy) + _origin;
    } else {
      // 교원대 정문 ~ 월탄리 원룸촌 핵심 요충지 (x: 280, y: 150)
      targetPt = proj.project(280, 150) + _origin;
    }

    final currentScale = (scale ?? _transformController.value.getMaxScaleOnAxis()).clamp(
      0.45,
      3.5,
    );
    final tx = (_viewportSize.width / 2) - (targetPt.dx * currentScale);
    final ty = (_viewportSize.height * 0.48) - (targetPt.dy * currentScale);

    if (mounted) {
      setState(() {
        _transformController.value = Matrix4.identity()
          ..translate(tx, ty)
          ..scale(currentScale);
      });
    } else {
      _transformController.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(currentScale);
    }
  }

  void _zoomBy(double factor) {
    if (_viewportSize == Size.zero) return;
    final matrix = _transformController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.3, 7.0);
    final scaleChange = targetScale / currentScale;

    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final tx =
        center.dx - (center.dx - matrix.getTranslation().x) * scaleChange;
    final ty =
        center.dy - (center.dy - matrix.getTranslation().y) * scaleChange;

    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale);
  }

  void _rebuild() {
    final proj = _proj;

    // 관리자 수정 반영: 삭제·병합 제외, 고친 외곽선, 고친 층수(=높이)
    var effectiveBuildings = applyBuildingOverrides(
      inheritMergedCampus(_base.buildings, _overrides),
      _overrides,
    );
    final draft = _shapeDraft;
    if (_shapeEditId != null && draft != null && draft.length >= 3) {
      effectiveBuildings = [
        for (final b in effectiveBuildings)
          b.id == _shapeEditId ? b.copyWith(ring: draft) : b,
      ];
    }

    // 시세 조사는 이름으로 붙으므로, 이름이 바뀌었을 때만 요약을 다시 만든다.
    final nameById = {
      for (final b in effectiveBuildings)
        b.id: (_overrides[b.id]?.isNamed ?? false) ? _overrides[b.id]!.name : (b.officialName ?? ''),
    };
    final input = (_reports, [for (final e in nameById.entries) '${e.key}=${e.value}'].join('|'));
    if (_summaryInput?.$1 != input.$1 || _summaryInput?.$2 != input.$2) {
      _summaryInput = input;
      _summaries = summarizeWithSurvey(_reports, nameById);
    }

    // 무엇을 칠하고 어떤 이름표를 달지는 housingMapStyle이 정한다 — 지도
    final matches = Set<String>.from(_matchingBuildingIds);
    if (_onlyFavorites) {
      if (matches.isEmpty) {
        matches.addAll(_favoriteIds);
      } else {
        matches.retainAll(_favoriteIds);
      }
    }

    _effectiveBuildings = effectiveBuildings;
    _rebuildShadows();

    final style = housingMapStyle(
      effectiveBuildings,
      summaries: _summaries,
      overrides: _overrides,
      matches: matches,
    );

    _buildings = layoutBuildings(
      effectiveBuildings,
      proj,
      selectedId: _selectedId,
      highlightedIds: _mergeSelectedBuildingIds,
      oneRoomIds: style.oneRoomIds,
      zoneColors: style.zoneColors,
      // 캠퍼스 모드에선 교내 건물에만 이름표를 단다(교내 건물은 이름이 없으면
      // 공식 명칭을 쓰므로 원룸 이름만 빼면 된다).
      displayNames: _campusMode
          ? {
              for (final b in effectiveBuildings)
                if (b.isCampus && style.displayNames[b.id] != null) b.id: style.displayNames[b.id]!,
            }
          : style.displayNames,
      windowIds: style.windowIds,
      showLabels: _showLabels,
      hiddenLabelIds: {
        for (final e in _overrides.entries)
          if (e.value.hideLabel == true) e.key,
      },
    );
    _roadPaths = projectRoads(_base.roads, proj);
    _isoOsmRoads = projectOsmRoads(_osmRoads, proj);
    _isoTerrain = projectTerrain(_base.terrain, proj);
    _landuse = projectLandUse(_base.landuse, proj);

    final b = boundsOf(_buildings, _roadPaths);
    _origin = Offset(-b.left + 80, -b.top + 80);
    _canvas = Size(b.width + 160, b.height + 160);
  }

  /// 관리자 수정(이름·색·층수·삭제)과 직접 추가·병합한 건물을 실시간으로
  /// 받는다. 저장하는 즉시, 다른 기기에서 고친 것도 열린 지도에 바로 뜬다.
  /// 첫 수정 데이터가 도착했는지. 지도를 처음 보여줄 때 기다린다([_load]).
  final Completer<void> _firstOverrides = Completer<void>();
  final Completer<void> _firstCustom = Completer<void>();
  Timer? _revealTimer;

  void _markFirst(Completer<void> c) {
    if (!c.isCompleted) c.complete();
  }

  void _watchAdminEdits() {
    try {
      _listenAdminEdits();
    } catch (e) {
      // Firebase가 안 떠 있으면(테스트 등) 수정 없이 기본 지도만 그린다.
      debugPrint('watchAdminEdits unavailable: $e');
      _markFirst(_firstOverrides);
      _markFirst(_firstCustom);
    }
  }

  void _listenAdminEdits() {
    _overrideSub = HousingService.watchOverrides().listen(
      (overrides) {
        _markFirst(_firstOverrides);
        if (!mounted) return;
        setState(() {
          _overrides = overrides;
          _rebuild();
        });
      },
      onError: (Object e) {
        debugPrint('watchOverrides error: $e');
        _markFirst(_firstOverrides);
      },
    );
    _customSub = HousingService.watchCustomBuildings().listen(
      (custom) {
        _markFirst(_firstCustom);
        if (!mounted) return;
        setState(() {
          _base = CampusBase(
            buildings: withCustomBuildings(_assetBase.buildings, custom),
            roads: _assetBase.roads,
            terrain: _assetBase.terrain,
            landuse: _assetBase.landuse,
          );
          _rebuild();
        });
      },
      onError: (Object e) {
        debugPrint('watchCustomBuildings error: $e');
        _markFirst(_firstCustom);
      },
    );
    _landmarkSub = HousingLandmarkService.watch().listen(
      (list) {
        // 도보 거리·등시선이 찍은 정문·탑연 정류장을 쓰게 한다.
        kPlacedLandmarkPositions.value = campusLandmarkOverrides(list);
        if (!mounted) return;
        setState(() => _landmarks = list);
      },
      onError: (Object e) => debugPrint('watchLandmarks error: $e'),
    );
  }

  void _rotateTo(double angle, {bool keepCenter = true}) {
    setState(() {
      _rotationAngle = (angle % (2 * math.pi));
      _rebuild();
    });
    if (keepCenter) {
      _centerOnTarget();
    }
  }

  void _rotateBy(double delta) {
    _rotateTo(_rotationAngle + delta, keepCenter: true);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_EditUndoSnapshot(Map.from(_overrides), List.from(_base.buildings)));
    if (_undoStack.length > 20) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final last = _undoStack.removeLast();
    setState(() {
      _overrides = last.overrides;
      _base = CampusBase(
        buildings: last.buildings,
        roads: _base.roads,
        terrain: _base.terrain,
        landuse: _base.landuse,
      );
      _mergeSelectedBuildingIds.clear();
      _rebuild();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('↩️ 이전 편집 작업이 취소되었습니다.'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  /// [color]가 null이면 "시스템" 색(밝은/다크 모드 기본 색을 따름).
  Future<void> _applyPaintColor(BaseBuilding b, Color? color) async {
    _pushUndoSnapshot();
    final hex = color == null
        ? HousingBuildingOverride.systemColor
        : '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final existing = _overrides[b.id];
    // 처음 칠하는 건물은 이름을 비워 둔다 — 색만 바꾼 문서로 남아 이름표·
    // 구역이 새로 붙지 않는다(HousingBuildingOverride.isNamed).
    final updated = (existing != null)
        ? existing.copyWith(customColorHex: hex)
        : HousingBuildingOverride(
            buildingId: b.id,
            name: '',
            zone: HousingZone.values.first,
            customColorHex: hex,
          );

    setState(() {
      _overrides = Map.from(_overrides)..[b.id] = updated;
      _rebuild();
    });

    final label = updated.isNamed ? updated.name : (b.officialName ?? b.buildingNo ?? '건물');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎨 [$label] 색상이 변경되었습니다.'),
        duration: const Duration(milliseconds: 1200),
      ),
    );

    try {
      await HousingService.setOverride(updated);
    } catch (e) {
      debugPrint('paint save error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e));
    }
  }

  void _toggleMergeSelection(String buildingId) {
    setState(() {
      if (_mergeSelectedBuildingIds.contains(buildingId)) {
        _mergeSelectedBuildingIds.remove(buildingId);
      } else {
        _mergeSelectedBuildingIds.add(buildingId);
      }
      _rebuild();
    });
  }

  Future<void> _promptMergeSelectedBuildings() async {
    if (_mergeSelectedBuildingIds.length < 2) return;
    final selected = _base.buildings.where((b) => _mergeSelectedBuildingIds.contains(b.id)).toList();
    if (selected.length < 2) return;

    final defaultName = '${selected.first.officialName ?? "건물"} (통합)';
    final nameCtrl = TextEditingController(text: defaultName);
    HousingZone selectedZone = _overrides[selected.first.id]?.zone ?? HousingZone.values.first;
    Color selectedColor = _overrides[selected.first.id]?.customColor ?? const Color(0xFF03C75A);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.merge_type_rounded, color: Color(0xFF007AFF)),
              const SizedBox(width: 8),
              Text('${selected.length}개 건물 합치기', style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선택한 ${selected.length}개 건물의 외곽선을 결합하여 하나의 통합 건물 블록으로 병합합니다.',
                style: const TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '새 건물 이름', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<HousingZone>(
                value: selectedZone,
                decoration: const InputDecoration(labelText: '구역', border: OutlineInputBorder(), isDense: true),
                items: HousingZone.values.map((z) => DropdownMenuItem(value: z, child: Text(z.label))).toList(),
                onChanged: (v) => setDlgState(() => selectedZone = v ?? selectedZone),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('합치기'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    _pushUndoSnapshot();

    // Convex Hull로 외곽 다각형 결합
    // 외곽선을 고쳐 둔 동은 고친 모양으로 합친다.
    final allPoints = selected.expand((b) {
      final r = _overrides[b.id]?.customRing;
      return (r != null && r.length >= 3) ? r : b.ring;
    }).toList();
    final mergedRing = computeConvexHull(allPoints);

    final mergedId = 'merged_${DateTime.now().millisecondsSinceEpoch}';
    final mergedName = nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim();
    // 층수를 고쳐 둔 동이 있으면 그 값으로 — 합친 뒤 도로 낮아지지 않게.
    final maxFloors = selected
        .map((b) => _overrides[b.id]?.floors ?? b.floors)
        .reduce(math.max);
    final hex = '#${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    // 교내 건물을 합치면 결과도 교내 건물이고 용도(기숙사·강의동…)를 이어받는다.
    final traits = mergedCampusTraits(selected);
    final newBuilding = BaseBuilding(
      id: mergedId,
      officialName: mergedName,
      floors: maxFloors,
      ring: mergedRing,
      road: selected.first.road,
      buildingNo: selected.first.buildingNo,
      isCampus: traits.isCampus,
      use: traits.use,
    );

    final newOverride = HousingBuildingOverride(
      buildingId: mergedId,
      name: mergedName,
      zone: selectedZone,
      floors: maxFloors,
      customColorHex: hex,
      customRing: mergedRing,
    );

    try {
      await HousingService.saveCustomBuilding(building: newBuilding, override: newOverride);

      // 기존 건물들은 병합되어 숨김 처리
      for (final oldB in selected) {
        final oldO = (_overrides[oldB.id] ?? HousingBuildingOverride(
          buildingId: oldB.id,
          name: oldB.officialName ?? '',
          zone: selectedZone,
        )).copyWith(mergedWith: mergedId, isDeleted: true);
        await HousingService.setOverride(oldO);
        _overrides = {..._overrides, oldB.id: oldO};
      }
    } catch (e) {
      debugPrint('merge save error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e));
      return;
    }

    setState(() {
      _base = CampusBase(
        buildings: [..._base.buildings, newBuilding],
        roads: _base.roads,
        terrain: _base.terrain,
        landuse: _base.landuse,
      );
      _overrides = {..._overrides, mergedId: newOverride};
      _mergeSelectedBuildingIds.clear();
      _editTool = HousingEditTool.inspect;
      _peekBuilding = newBuilding;
      _rebuild();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🔗 [ $mergedName ] 건물로 병합되었습니다.')),
    );
  }

  Future<void> _promptAddBlockAt(Offset worldPt) async {
    final nameCtrl = TextEditingController(text: '신규 원룸');
    final floorCtrl = TextEditingController(text: '3');
    HousingZone selectedZone = HousingZone.values.first;
    Color selectedColor = const Color(0xFF03C75A);

    const colorPresets = kHousingPalette;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_box_rounded, color: Color(0xFF03C75A)),
              SizedBox(width: 8),
              Text('새 건물 블록 배치', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '선택한 좌표 (X: ${worldPt.dx.toStringAsFixed(1)}, Y: ${worldPt.dy.toStringAsFixed(1)})에 12m × 10m 건물 블록을 배치합니다.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '건물 이름', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: floorCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '층수', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<HousingZone>(
                        value: selectedZone,
                        decoration: const InputDecoration(labelText: '구역', border: OutlineInputBorder(), isDense: true),
                        items: HousingZone.values.map((z) => DropdownMenuItem(value: z, child: Text(z.label))).toList(),
                        onChanged: (v) => setDlgState(() => selectedZone = v ?? selectedZone),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('건물 색상', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: colorPresets.map((clr) {
                    final isSel = selectedColor.toARGB32() == clr.toARGB32();
                    return GestureDetector(
                      onTap: () => setDlgState(() => selectedColor = clr),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: clr,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? Colors.black87 : Colors.black12, width: isSel ? 2.5 : 1),
                        ),
                        child: isSel ? Icon(Icons.check, color: paletteCheckColor(clr), size: 14) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('배치 완료'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    _pushUndoSnapshot();

    // 12m x 10m 사각형 건물 ring 생성
    const halfW = 6.0;
    const halfH = 5.0;
    final ring = [
      Offset(worldPt.dx - halfW, worldPt.dy - halfH),
      Offset(worldPt.dx + halfW, worldPt.dy - halfH),
      Offset(worldPt.dx + halfW, worldPt.dy + halfH),
      Offset(worldPt.dx - halfW, worldPt.dy + halfH),
    ];

    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final name = nameCtrl.text.trim().isEmpty ? '신규 원룸' : nameCtrl.text.trim();
    final floors = int.tryParse(floorCtrl.text) ?? 3;
    final hex = '#${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    final newBuilding = BaseBuilding(
      id: newId,
      officialName: name,
      floors: floors,
      ring: ring,
      isCampus: false,
    );

    final override = HousingBuildingOverride(
      buildingId: newId,
      name: name,
      zone: selectedZone,
      floors: floors,
      customColorHex: hex,
      customRing: ring,
    );

    try {
      await HousingService.saveCustomBuilding(building: newBuilding, override: override);
    } catch (e) {
      debugPrint('add block save error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e));
      return;
    }
    if (!mounted) return;

    setState(() {
      _base = CampusBase(
        buildings: [..._base.buildings, newBuilding],
        roads: _base.roads,
        terrain: _base.terrain,
        landuse: _base.landuse,
      );
      _overrides = Map.from(_overrides)..[newId] = override;
      _peekBuilding = newBuilding;
      _editTool = HousingEditTool.inspect;
      _rebuild();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('➕ [ $name ] 새 건물 블록이 생성되었습니다.')),
    );
  }

  Future<void> _confirmDeleteBuilding(BaseBuilding b) async {
    final o = _overrides[b.id];
    final name = (o != null && o.isNamed) ? o.name : (b.officialName ?? '건물');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('건물 블록 삭제', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '정말 [ $name ] 건물을 지도에서 삭제하시겠습니까?\n실행 취소(Undo) 버튼으로 복원할 수 있습니다.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    _pushUndoSnapshot();

    final isCustom = b.id.startsWith('custom_') || b.id.startsWith('merged_');
    // 지도 데이터에 구워진 건물은 지울 수 없으니 "삭제됨" 표시를 단다.
    final hidden = (_overrides[b.id] ?? HousingBuildingOverride(
      buildingId: b.id,
      name: '',
      zone: HousingZone.values.first,
    )).copyWith(isDeleted: true);
    try {
      if (isCustom) {
        await HousingService.deleteCustomBuilding(b.id);
      } else {
        await HousingService.setOverride(hidden);
      }
    } catch (e) {
      debugPrint('delete building error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e, what: '삭제'));
      return;
    }
    if (!mounted) return;

    if (isCustom) {
      _base = CampusBase(
        buildings: _base.buildings.where((x) => x.id != b.id).toList(),
        roads: _base.roads,
        terrain: _base.terrain,
        landuse: _base.landuse,
      );
    } else {
      _overrides = {..._overrides, b.id: hidden};
    }

    setState(() {
      if (_peekBuilding?.id == b.id) _peekBuilding = null;
      if (_selectedId == b.id) _selectedId = null;
      _mergeSelectedBuildingIds.remove(b.id);
      _rebuild();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🗑️ [ $name ] 건물이 삭제되었습니다.')),
    );
  }

  void _onTapMap(Offset local) {
    final localWithoutOrigin = local - _origin;
    final hit = hitTestBuilding(_buildings, localWithoutOrigin);

    if (AdminAuthService.isAdmin.value) {
      if (_editTool == HousingEditTool.paint && hit != null) {
        _applyPaintColor(hit, _paintSystem ? null : _paintColor);
        return;
      } else if (_editTool == HousingEditTool.merge && hit != null) {
        _toggleMergeSelection(hit.id);
        return;
      } else if (_editTool == HousingEditTool.delete && hit != null) {
        _confirmDeleteBuilding(hit);
        return;
      } else if (_editTool == HousingEditTool.reshape) {
        if (hit != null && hit.id != _shapeEditId) _startShapeEdit(hit);
        return;
      } else if (_editTool == HousingEditTool.label && hit != null) {
        _toggleLabel(hit);
        return;
      } else if (_editTool == HousingEditTool.landmark) {
        // 빈 곳을 탭하면 새 위치. 이미 찍은 마커는 마커 쪽에서 받는다.
        final world = _proj.unproject(localWithoutOrigin.dx, localWithoutOrigin.dy);
        _promptLandmark(world: world);
        return;
      } else if (_editTool == HousingEditTool.addBlock) {
        final proj = _proj;
        final worldPt = proj.unproject(localWithoutOrigin.dx, localWithoutOrigin.dy);
        _promptAddBlockAt(worldPt);
        return;
      }
    }

    if (hit == null) {
      if (_peekBuilding != null || _selectedId != null) {
        setState(() {
          _peekBuilding = null;
          _selectedId = null;
          _rebuild();
        });
      }
      return;
    }
    setState(() {
      _peekBuilding = hit;
    });
    _focusBuilding(hit, openDetail: false);
  }

  void _focusBuilding(BaseBuilding b, {bool openDetail = true}) {
    setState(() {
      _selectedId = b.id;
      _rebuild();
    });

    final proj = _proj;
    final pt = proj.project(b.center.dx, b.center.dy) + _origin;
    final size = MediaQuery.of(context).size;
    const targetScale = 1.6;
    final tx = (size.width / 2) - (pt.dx * targetScale);
    final ty = (size.height * 0.35) - (pt.dy * targetScale);

    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale);

    if (openDetail) {
      _showDetail(b);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // 캠퍼스맵 탭에 끼우면 바깥 Scaffold(extendBodyBehindAppBar)가 상단바 높이를
        // 이미 padding.top에 담아 넘긴다. 여기서 104를 또 더하면 검색창이 화면
        // 중간에 뜨고 안내 배너는 반투명 상단바 뒤에 가려진다. 그래서 본문 전체를
        // 상단바 아래에서 시작시키고, 안쪽 오프셋은 단독 화면과 같게 둔다.
        const topBase = 10.0;
        final embeddedTop = widget.isEmbedded ? MediaQuery.of(context).padding.top : 0.0;

        return Scaffold(
          appBar: widget.isEmbedded
              ? null
              : AppBar(
                  title: const Text("자취방 구하기"),
                  backgroundColor: Colors.transparent,
                  flexibleSpace: AppleAppBarFlexibleSpace(
                    themeColor: color,
                    isDark: isDark,
                  ),
                  iconTheme: const IconThemeData(color: Colors.white),
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: AdminAuthService.isAdmin,
                      builder: (context, isAdmin, _) {
                        if (isAdmin) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _openAddBuildingDialog(isDark, color),
                                icon: const Icon(Icons.add_business_rounded),
                                tooltip: "새 건물 추가 (개발자)",
                              ),
                              IconButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HousingAdminScreen(),
                                  ),
                                ).then((_) => _load()),
                                icon: const Icon(Icons.admin_panel_settings_rounded),
                                tooltip: "자취방 관리 대시보드",
                              ),
                            ],
                          );
                        }
                        return IconButton(
                          onPressed: () => _promptDeveloperMode(isDark, color),
                          icon: const Icon(Icons.lock_outline_rounded),
                          tooltip: "개발자 모드 활성화",
                        );
                      },
                    ),
                    IconButton(
                      onPressed: () => _openFilterSheet(isDark),
                      icon: Icon(
                        _filter.isEmpty
                            ? Icons.tune_rounded
                            : Icons.filter_alt_rounded,
                      ),
                      tooltip: "내 조건 찾기",
                    ),
                    IconButton(
                      onPressed: () => _showHelp(isDark),
                      icon: const Icon(Icons.help_outline_rounded),
                      tooltip: "지도 안내",
                    ),
                  ],
                ),
          body: Padding(
            padding: EdgeInsets.only(top: embeddedTop),
            child: MediaQuery.removePadding(
            context: context,
            removeTop: widget.isEmbedded,
            child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: color),
                      const SizedBox(height: 14),
                      Text(
                        '자취방 3D 지도를 준비하고 있어요...',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildDevNoticeBanner(isDark),
                    Expanded(
                      child: Stack(
                        children: [
                          // 메인 뷰 (지도 또는 목록)
                          Positioned.fill(
                            child: _isListView
                                ? HousingListView(
                                    buildings: inheritMergedCampus(_base.buildings, _overrides),
                                    summaries: _summaries,
                                    overrides: _overrides,
                                    favoriteIds: _favoriteIds,
                                    filter: _filter,
                                    selectedZone: _selectedZone,
                                    onlyFavorites: _onlyFavorites,
                                    searchQuery: _searchQuery,
                                    sortType: _sortType,
                                    isDark: isDark,
                                    themeColor: color,
                                    onSortChanged: (st) =>
                                        setState(() => _sortType = st),
                                    onTapBuilding: (b) =>
                                        _showDetail(b),
                                    onToggleFavorite: (id) =>
                                        _toggleFavorite(id),
                                    onShowOnMap: (b) {
                                      setState(() {
                                        _isListView = false;
                                        _peekBuilding = b;
                                      });
                                      _focusBuilding(b, openDetail: false);
                                    },
                                  )
                                : _buildMap(isDark),
                          ),

                          // 상단 검색 & 구역 필터 바
                          Positioned(
                            top: topBase,
                            left: 12,
                            right: 12,
                            child: _buildSearchBar(isDark),
                          ),

                          // 개발자 지도 편집 툴바 (블록 추가, 병합, 색칠, 삭제, Undo)
                          // Positioned는 반드시 바깥에 둔다. 일반 사용자일 때
                          // 위치 없는 SizedBox.shrink가 Stack 자식이 되면 Stack이
                          // 거기에 맞춰 폭 0으로 줄어 지도 전체가 사라진다.
                          if (!_isListView)
                            Positioned(
                              top: topBase + 82,
                              left: 12,
                              right: 12,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: AdminAuthService.isAdmin,
                                builder: (context, isAdmin, _) => isAdmin
                                    ? _buildDevEditorToolbar(isDark, color)
                                    : const SizedBox.shrink(),
                              ),
                            ),

                          // 건물 블록 병합 모드 플로팅 바 (2개 이상 선택 시)
                          if (!_isListView && _shapeDraft != null)
                            Positioned(
                              bottom: 76,
                              left: 20,
                              right: 20,
                              child: _buildShapeEditBar(isDark),
                            ),

                          if (!_isListView && _mergeSelectedBuildingIds.length >= 2)
                            Positioned(
                              bottom: 76,
                              left: 20,
                              right: 20,
                              child: _buildMergeFloatingBar(isDark, color),
                            ),

                          // 360도 회전 나침반 & 방위각 컨트롤러 HUD (지도 모드일 때만, 스니크픽 카드 높이에 따라 부드럽게 조정)
                          if (!_isListView)
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              bottom: _peekBuilding != null ? 150 : 66,
                              right: 14,
                              child: _buildRotationControls(isDark, color),
                            ),

                          // 하단 스니크픽 미니 요약 카드 (건물 선택 시)
                          if (!_isListView && _peekBuilding != null)
                            Positioned(
                              bottom: 16,
                              left: 12,
                              right: 12,
                              child: _buildPeekCard(_peekBuilding!, isDark, color),
                            ),

                                                    // 비교함 플로팅 바 (1개 이상 담겼을 때)
                          if (_compareBuildingIds.isNotEmpty && (_isListView || _peekBuilding == null))
                            Positioned(
                              bottom: 66,
                              left: 24,
                              right: 24,
                              child: _buildCompareFloatingBar(isDark, color),
                            ),
                          if (!_isListView &&
                              _showShadows &&
                              _peekBuilding == null &&
                              _shapeDraft == null &&
                              _mergeSelectedBuildingIds.length < 2)
                            Positioned(
                              bottom: 72,
                              left: 16,
                              right: 16,
                              child: _buildShadowTimeBar(isDark, color),
                            ),
// 지도/목록 모드 전환 플로팅 토글 버튼 (하단 중앙). 목록은 자취방
                          // 목록이라 캠퍼스 모드에선 숨긴다.
                          if (!_campusMode && (_isListView || _peekBuilding == null))
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: _buildViewModeToggle(isDark, color),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDevNoticeBanner(bool isDark) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminAuthService.isAdmin,
      builder: (context, isAdmin, _) {
        if (isAdmin) {
          return Container(
            width: double.infinity,
            color: const Color(0xFF03C75A).withValues(alpha: isDark ? 0.22 : 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.build_circle_rounded, color: Color(0xFF03C75A), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // 폰에선 한 줄로 — 할 일 안내는 아래 도구 모음이 한다.
                    _compact
                        ? "🛠️ 개발자 모드"
                        : "🛠️ 개발자 모드 ON: 지도의 건물을 탭해 이름·색상·정보를 수정하거나 상단 [+]로 건물을 추가하세요.",
                    style: const TextStyle(
                      color: Color(0xFF03C75A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    AdminAuthService.revokeOnThisDevice();
                    showToast(context, "개발자 모드가 종료되었습니다.");
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("종료", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        }
        // 한 번 닫으면 다시 띄우지 않는다 — 폰에선 세 줄이나 차지해 지도를 가렸다.
        if (_noticeDismissed) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.1),
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.construction_rounded, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "자취방 구하기는 지속적으로 개발 중이에요. 건물 정보가 정확하지 않을 수 있어요",
                  style: TextStyle(color: Colors.blue, fontSize: _compact ? 12 : 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.blue),
                tooltip: '안내 닫기',
                visualDensity: VisualDensity.compact,
                onPressed: _dismissNotice,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchInputChanged,
                  onSubmitted: (_) {
                    final results = _getMatchingSearchResults();
                    if (results.isNotEmpty) {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      _focusBuilding(results.first.building, openDetail: true);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: "원룸 이름 검색 (예: ㄷㅅ, 다솜빌, 해오름)",
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _peekBuilding = null;
                    });
                  },
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),

        // 실시간 검색 결과 드롭다운
        if (_searchQuery.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: _getMatchingSearchResults().map((item) {
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "상세보기 ›",
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF007AFF),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _focusBuilding(item.building, openDetail: true);
                  },
                );
              }).toList(),
            ),
          ),

        // 구역 필터 칩 리스트
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // 캠퍼스맵에서 열었으면 캠퍼스/자취방을 오간다.
              if (widget.campusMode) ...[
                _buildModeChip('캠퍼스', Icons.school_rounded, _campusMode, isDark, () => _setCampusMode(true)),
                _buildModeChip('자취방', Icons.apartment_rounded, !_campusMode, isDark, () => _setCampusMode(false)),
              ],
              if (!_campusMode) ...[
                if (_hasActiveFilters) _buildResetFilterChip(isDark),
                _buildPriceTagToggleChip(isDark),
              ],
              _buildLabelToggleChip(isDark),
              if (!_campusMode) ...[
                _buildFavoriteChip(isDark),
                _buildQuickFilterChip('월 35 이하', _quickMaxRent35, isDark, onTap: _toggleQuickMaxRent35),
                _buildQuickFilterChip('원룸/1.5룸', _quickRoomTypes, isDark, onTap: _toggleQuickRoomTypes),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 그림자 시각 막대: 해 뜰 때부터 질 때까지 끌어서 본다.
  Widget _buildShadowTimeBar(bool isDark, Color color) {
    final sun = _sun;
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;
    const amber = Color(0xFFFFA000);
    final now = nowInKst();
    final isToday = now.year == _shadowDay.year &&
        now.month == _shadowDay.month &&
        now.day == _shadowDay.day;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF161922).withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: amber.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_rounded, color: amber, size: 18),
                const SizedBox(width: 6),
                Text(
                  formatKstMinute(_shadowMinute),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    fontFamily: KnueTokens.fontFamily,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '해 높이 ${sun.altitude.round()}° · ${_sunDirectionLabel(sun.azimuth)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: sub, fontFamily: KnueTokens.fontFamily),
                  ),
                ),
                if (isToday)
                  TextButton(
                    onPressed: () => _setShadowMinute(_clampToDaylight(nowInKst().minute)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('지금', style: TextStyle(fontSize: 12)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: _toggleShadows,
                  tooltip: '그림자 끄기',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '일출 ${formatKstMinute(_sunTimes.sunrise).substring(3)}',
                  style: TextStyle(fontSize: 10.5, color: sub),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: amber,
                      thumbColor: amber,
                      inactiveTrackColor: amber.withValues(alpha: 0.2),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      min: _sunTimes.sunrise.toDouble(),
                      max: _sunTimes.sunset.toDouble(),
                      divisions: ((_sunTimes.sunset - _sunTimes.sunrise) / 5).round().clamp(1, 1000),
                      value: _shadowMinute
                          .clamp(_sunTimes.sunrise, _sunTimes.sunset)
                          .toDouble(),
                      onChanged: (v) => _setShadowMinute(v.round()),
                    ),
                  ),
                ),
                Text(
                  '일몰 ${formatKstMinute(_sunTimes.sunset).substring(3)}',
                  style: TextStyle(fontSize: 10.5, color: sub),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 해가 있는 쪽을 8방위로.
  String _sunDirectionLabel(double azimuth) {
    const names = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
    return '${names[((azimuth + 22.5) % 360 ~/ 45)]}쪽 해';
  }

  Widget _buildResetFilterChip(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: _clearAllFilters,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 3),
              Text(
                '초기화',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilterChip(
    String label,
    bool isSelected,
    bool isDark, {
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF007AFF)
                : (isDark
                    ? const Color(0xFF2C2C2E).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (isDark ? Colors.white12 : Colors.black12),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteChip(bool isDark) {
    final isSelected = _onlyFavorites;
    final count = _favoriteIds.length;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _onlyFavorites = !_onlyFavorites;
            _rebuild();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.redAccent
                : (isDark
                    ? const Color(0xFF2C2C2E).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (isDark ? Colors.white12 : Colors.black12),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 13,
                color: isSelected ? Colors.white : Colors.redAccent,
              ),
              const SizedBox(width: 4),
              Text(
                '찜 $count',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                  fontFeatures: KnueTokens.tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String label, IconData icon, bool selected, bool isDark, VoidCallback onTap) {
    const green = Color(0xFF03C75A);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? green
                : (isDark ? const Color(0xFF2C2C2E).withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12), width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: selected ? Colors.white : (isDark ? Colors.white70 : green)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleLabels() {
    setState(() {
      _showLabels = !_showLabels;
      _rebuild();
    });
  }

  Widget _buildLabelToggleChip(bool isDark) {
    final on = _showLabels;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: _toggleLabels,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on
                ? const Color(0xFF007AFF)
                : (isDark ? const Color(0xFF2C2C2E).withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.label_rounded : Icons.label_off_outlined,
                size: 13,
                color: on ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF007AFF)),
              ),
              const SizedBox(width: 4),
              Text(
                '이름표',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceTagToggleChip(bool isDark) {
    final isSelected = _showPriceTags;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showPriceTags = !_showPriceTags;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF007AFF)
                : (isDark
                    ? const Color(0xFF2C2C2E).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (isDark ? Colors.white12 : Colors.black12),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.sell_rounded : Icons.sell_outlined,
                size: 13,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF007AFF)),
              ),
              const SizedBox(width: 4),
              Text(
                '시세 뱃지',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSearchInputChanged(String query) {
    final trimmed = query.trim();
    setState(() => _searchQuery = trimmed);
    if (trimmed.isNotEmpty) {
      final results = _getMatchingSearchResults();
      if (results.isNotEmpty) {
        final firstBuilding = results.first.building;
        setState(() => _peekBuilding = firstBuilding);
        // 검색어 입력 시 즉시 그 건물로 시점 부드럽게 이동 (상세 시트는 열지 않고 카메라만 이동)
        _focusBuilding(firstBuilding, openDetail: false);
      }
    } else {
      setState(() => _peekBuilding = null);
    }
  }

  List<_SearchResultItem> _getMatchingSearchResults() {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    final results = <_SearchResultItem>[];
    final matchedIds = <String>{};

    // 0. 가게 이름·업종 — 그 가게가 든 건물로 옮겨 간다.
    for (final (id, shop) in findShops(_overrides, q, matchesKoreanHousingSearch)) {
      BaseBuilding? b;
      for (final elem in _base.buildings) {
        if (elem.id == id) {
          b = elem;
          break;
        }
      }
      if (b == null) continue;
      matchedIds.add(b.id);
      final bName = _resolvedKnown(b.id)?.name ?? b.officialName ?? '건물';
      results.add(
        _SearchResultItem(
          name: shop.name,
          subtitle: ['🏪 $bName', if (shop.detail.isNotEmpty) shop.detail].join(' · '),
          color: const Color(0xFFFF9800),
          building: b,
        ),
      );
    }

    // 1. 관리자가 덮어쓴 원룸 건물 검색 (우선순위 최고)
    for (final entry in _overrides.entries) {
      final o = entry.value;
      if (matchesKoreanHousingSearch(o.name, q) ||
          (o.address != null && matchesKoreanHousingSearch(o.address!, q))) {
        BaseBuilding? b;
        for (final elem in _base.buildings) {
          if (elem.id == entry.key) {
            b = elem;
            break;
          }
        }
        if (b == null) continue;
        matchedIds.add(b.id);

        final s = _summaries[b.id];
        final priceText = (s != null && s.hasData)
            ? ' · 보증금 ${s.avgDeposit ?? 0}만/월 ${s.avgMonthlyTotal ?? s.avgRent ?? 0}만'
            : '';

        results.add(
          _SearchResultItem(
            name: o.name,
            subtitle: b.isCampus
                ? '캠퍼스 시설 · 지상 ${o.floors ?? b.floors}층'
                : '${displayAddress(b, o)}$priceText',
            color: b.isCampus ? HousingZone.campus.color : o.zone.color,
            building: b,
          ),
        );
      }
    }

    // 2. 알려진 원룸 사전 검색 (kOneRoomNames - 초성 검색 지원)
    for (final item in kOneRoomNames) {
      if (matchesKoreanHousingSearch(item.name, q) ||
          matchesKoreanHousingSearch(item.id, q)) {
        final b = _base.buildings.firstWhere(
          (elem) => _summaries[elem.id]?.oneRoomId == item.id,
          orElse: () => _base.buildings.firstWhere(
            (elem) => !elem.isCampus && !matchedIds.contains(elem.id),
            orElse: () => _base.buildings.first,
          ),
        );
        if (matchedIds.contains(b.id)) continue;
        matchedIds.add(b.id);

        final s = _summaries[b.id];
        final priceText = (s != null && s.hasData)
            ? ' · 보증금 ${s.avgDeposit ?? 0}만/월 ${s.avgMonthlyTotal ?? s.avgRent ?? 0}만'
            : '';

        results.add(
          _SearchResultItem(
            name: item.name,
            subtitle: '${displayAddress(b, _overrides[b.id])}$priceText',
            color: item.zone.color,
            building: b,
          ),
        );
      }
    }

    // 3. 교내 건물 및 일반 건물 검색
    for (final b in _base.buildings) {
      if (matchedIds.contains(b.id)) continue;
      final name = b.officialName ?? b.id;
      if (matchesKoreanHousingSearch(name, q) ||
          matchesKoreanHousingSearch(b.addressLabel, q)) {
        matchedIds.add(b.id);
        final isCamp = b.isCampus;
        final s = _summaries[b.id];
        final priceText = (!isCamp && s != null && s.hasData)
            ? ' · 보증금 ${s.avgDeposit ?? 0}만/월 ${s.avgMonthlyTotal ?? s.avgRent ?? 0}만'
            : '';

        results.add(
          _SearchResultItem(
            name: name,
            subtitle: isCamp
                ? '교원대 캠퍼스 · 지상 ${_overrides[b.id]?.floors ?? b.floors}층'
                : '${displayAddress(b, _overrides[b.id])}$priceText',
            color: isCamp ? const Color(0xFF3F51B5) : const Color(0xFF10B981),
            building: b,
          ),
        );
      }
    }

    return results.take(8).toList();
  }

  Widget _buildRotationControls(bool isDark, Color themeClr) {
    // 폰에선 나침반·확대·축소·중심 맞춤만 두고 나머지는 [더보기]로 펼친다.
    final showAll = !_compact || _hudExpanded;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.92);
    final deg = (_rotationAngle * 180 / math.pi).round() % 360;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 360도 나침반 버튼 (탭 시 북향 0도로 리셋)
          GestureDetector(
            onTap: () => _rotateTo(0.0),
            child: Tooltip(
              message: "북향(0°)으로 리셋",
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: -_rotationAngle,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.navigation_rounded,
                          size: 16,
                          color: Color(0xFFFF3B30),
                        ),
                        Text(
                          '$deg°',
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // 45도 회전
          if (showAll) ...[
            _hudIconButton(
              icon: Icons.rotate_right_rounded,
              tooltip: "45° 시점 회전",
              onTap: () => _rotateBy(math.pi / 4),
              isDark: isDark,
            ),
            const SizedBox(height: 4),
          ],

          // 확대
          _hudIconButton(
            icon: Icons.add_rounded,
            tooltip: "확대",
            onTap: () => _zoomBy(1.3),
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 축소
          _hudIconButton(
            icon: Icons.remove_rounded,
            tooltip: "축소",
            onTap: () => _zoomBy(0.77),
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 중심 맞춤
          _hudIconButton(
            icon: Icons.my_location_rounded,
            tooltip: "캠퍼스 중심으로",
            onTap: _centerMap,
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 여기부터는 폰에서 [더보기]를 눌러야 보인다.
          if (showAll) ...[
          // 원룸 시세 뱃지 토글 (기본 끈 상태, 터치 시 켜짐)
          _hudIconButton(
            icon: _showPriceTags ? Icons.sell_rounded : Icons.sell_outlined,
            tooltip: _showPriceTags ? "원룸 시세 뱃지 끄기" : "원룸 시세 뱃지 켜기",
            onTap: () => setState(() => _showPriceTags = !_showPriceTags),
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 건물 이름표 토글
          _hudIconButton(
            icon: _showLabels ? Icons.label_rounded : Icons.label_off_outlined,
            tooltip: _showLabels ? "건물 이름표 끄기" : "건물 이름표 켜기",
            onTap: _toggleLabels,
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 도보 등시선: 누른 건물 기준, 켰을 때만
          _hudIconButton(
            icon: _showIsochrone ? Icons.radar_rounded : Icons.radar_outlined,
            tooltip: _showIsochrone ? "도보 등시선 끄기" : "도보 등시선 켜기(누른 건물 기준)",
            onTap: () {
              setState(() => _showIsochrone = !_showIsochrone);
              if (_showIsochrone && _peekBuilding == null && _selectedId == null) {
                showToast(context, '건물을 누르면 그 건물에서 걸어서 3·5·10분 거리가 보여요.');
              }
            },
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 시간별 그림자
          _hudIconButton(
            icon: _showShadows ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
            tooltip: _showShadows ? "그림자 끄기" : "시간별 그림자 보기",
            onTap: _toggleShadows,
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // 위에서 보기(평면) ↔ 3D
          _hudIconButton(
            icon: _topDown ? Icons.view_in_ar_rounded : Icons.map_outlined,
            tooltip: _topDown ? "3D로 보기" : "위에서 보기",
            onTap: _toggleTopDown,
            isDark: isDark,
          ),
          ],

          // 폰: 지도 도구 펼치기/접기
          if (_compact) ...[
            const SizedBox(height: 4),
            _hudIconButton(
              icon: _hudExpanded ? Icons.expand_less_rounded : Icons.more_horiz_rounded,
              tooltip: _hudExpanded ? "지도 도구 접기" : "지도 도구 더보기",
              onTap: () => setState(() => _hudExpanded = !_hudExpanded),
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  /// 지도 상에서 건물을 터치했을 때 화면 하단에 뜨는 콤팩트 스니크픽 카드
  Widget _buildPeekCard(BaseBuilding b, bool isDark, Color themeClr) {
    final s = _summaries[b.id] ?? HousingSummary.empty;
    final known = _resolvedKnown(b.id);
    final isFav = _favoriteIds.contains(b.id);
    final name = known?.name ?? b.officialName ?? (b.isCampus ? '캠퍼스 건물' : '이름 미확인 건물');
    final monthly = s.avgMonthlyTotal ?? s.avgRent;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: InkWell(
          onTap: () => _showDetail(b),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 구역 뱃지 / 주소 / 찜 & 닫기
                Row(
                  children: [
                    // 구역 딱지는 "캠퍼스 시설"만 — 원룸 구역 태그는 뺐다.
                    if (known != null && b.isCampus) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeZone(b, known).color.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: badgeZone(b, known).color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              badgeZone(b, known).label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: badgeZone(b, known).color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        b.addressLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontFeatures: KnueTokens.tabularFigures,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleFavorite(b.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.redAccent : (isDark ? Colors.white54 : Colors.black38),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _peekBuilding = null;
                          _selectedId = null;
                          _rebuild();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white38 : Colors.black38,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // 중간: 이름 및 시세
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!b.isCampus) ...[
                      if (s.hasData && monthly != null) ...[
                        Text(
                          '월 $monthly만원',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: themeClr,
                            fontFeatures: KnueTokens.tabularFigures,
                          ),
                        ),
                        if (s.avgDeposit != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '보증금 ${s.avgDeposit}만',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontFeatures: KnueTokens.tabularFigures,
                            ),
                          ),
                        ],
                      ] else ...[
                        Text(
                          '시세 제보 대기 중',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // 상가: 든 가게들. 누르면 상세에서 전체 목록을 본다.
                if (_overrides[b.id]?.shops case final shops? when shops.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 14, color: Color(0xFFFF9800)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '가게 ${shops.length}곳 · ${shops.take(4).map((x) => x.name).join(', ')}${shops.length > 4 ? ' 외' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ],

                // 하단: 도보 시간 뱃지 & 상세보기
                Row(
                  children: [
                    if (b.isCampus) ...[
                      _peekBadge(
                        Icons.school_rounded,
                        '캠퍼스 시설 · 지상 ${_overrides[b.id]?.floors ?? b.floors}층',
                        const Color(0xFF3F51B5),
                        isDark,
                      ),
                    ],
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: AdminAuthService.isAdmin,
                      builder: (context, isAdmin, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isAdmin) ...[
                              GestureDetector(
                                onTap: () => _openEditBuildingSheet(b, isDark, themeClr),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF03C75A).withValues(alpha: isDark ? 0.25 : 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF03C75A), width: 0.8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_rounded, size: 13, color: Color(0xFF03C75A)),
                                      SizedBox(width: 3),
                                      Text(
                                        '수정',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF03C75A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            Text(
                              '상세보기',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: themeClr,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: themeClr,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _promptDeveloperMode(bool isDark, Color themeClr) async {
    final controller = TextEditingController();
    bool obscure = true;
    bool verifying = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF03C75A)),
              SizedBox(width: 8),
              Text("개발자 모드 활성화", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "관리자 비밀번호를 입력하면 건물 이름, 지도 색상, 정보 수정 및 신규 건물 추가 기능이 즉시 활성화됩니다.",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "비밀번호",
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setDlgState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("취소"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF03C75A),
                foregroundColor: Colors.white,
              ),
              onPressed: verifying
                  ? null
                  : () async {
                      setDlgState(() => verifying = true);
                      final res = await AdminAuthService.unlock(controller.text);
                      if (!mounted) return;
                      if (res == AdminUnlockResult.ok) {
                        Navigator.pop(ctx);
                        setState(() {});
                        showToast(context, "🛠️ 개발자 모드가 활성화되었습니다!");
                      } else {
                        setDlgState(() => verifying = false);
                        showToast(context, res.message);
                      }
                    },
              child: verifying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("확인"),
            ),
          ],
        ),
      ),
    );
  }

  /// 편집 창 안의 목록 편집 칸(가게·시세). 항목을 누르면 고치고, ✕로 뺀다.
  /// 실제 저장은 편집 창의 [저장 및 즉시 반영]에서 한 번에 한다.
  Widget _editorListSection<T>({
    required String title,
    required IconData icon,
    required List<T> items,
    required String Function(T) titleOf,
    required String Function(T) subtitleOf,
    required VoidCallback onAdd,
    required void Function(int) onEdit,
    required void Function(int) onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text('$title (${items.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('추가', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: () => onEdit(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titleOf(items[i]), style: const TextStyle(fontSize: 13)),
                          if (subtitleOf(items[i]).isNotEmpty)
                            Text(subtitleOf(items[i]), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onRemove(i),
                      visualDensity: VisualDensity.compact,
                      tooltip: '빼기',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 가게 하나 넣기/고치기. 취소하면 null.
  Future<HousingShop?> _editShopDialog(HousingShop? current) async {
    final name = TextEditingController(text: current?.name ?? '');
    final category = TextEditingController(text: current?.category ?? '');
    final floor = TextEditingController(text: current?.floor ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current == null ? '가게 추가' : '가게 고치기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '가게 이름', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: category,
              decoration: const InputDecoration(labelText: '업종 (예: 카페, 편의점)', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: floor,
              decoration: const InputDecoration(labelText: '층 (예: 1층, 지하)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
        ],
      ),
    );
    final result = (ok == true && name.text.trim().isNotEmpty)
        ? HousingShop(name: name.text.trim(), category: category.text.trim(), floor: floor.text.trim())
        : null;
    // 컨트롤러는 여기서 dispose하지 않는다. 대화상자가 닫히는 애니메이션
    // 동안 입력칸이 아직 그려져서, 바로 정리하면 disposed 컨트롤러 오류가 난다.
    if (ok == true && result == null && mounted) showToast(context, '가게 이름을 입력해 주세요.');
    return result;
  }

  /// 시세 한 건 넣기/고치기. 금액은 만원 단위. 취소하면 null.
  Future<HousingPriceEntry?> _editPriceDialog(HousingPriceEntry? current) async {
    final deposit = TextEditingController(text: current?.deposit.toString() ?? '');
    final rent = TextEditingController(text: current?.monthlyRent.toString() ?? '');
    final fee = TextEditingController(text: current?.maintenanceFee?.toString() ?? '');
    // 방 구조는 칩으로 고른다 — 자유 입력이면 "원룸형"·"1룸"처럼 제각각 적혀
    // "내 조건 찾기"가 방 구조를 못 알아봤다.
    HousingRoomType? roomType = roomTypeFromText(current?.roomType);
    final asOf = TextEditingController(text: current?.asOf ?? '');
    final note = TextEditingController(text: current?.note ?? '');
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
        title: Text(current == null ? '시세 추가' : '시세 고치기'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: deposit, keyboardType: TextInputType.number, decoration: deco('보증금(만원)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: rent, keyboardType: TextInputType.number, decoration: deco('월세(만원)'))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: fee, keyboardType: TextInputType.number, decoration: deco('관리비(만원)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: asOf, decoration: deco('기준 시기(예: 2026-09)'))),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in HousingRoomType.values)
                      ChoiceChip(
                        label: Text(t.label, style: const TextStyle(fontSize: 12)),
                        selected: roomType == t,
                        onSelected: (sel) => setDlg(() => roomType = sel ? t : null),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: deco('메모')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
        ],
      )),
    );
    final d = int.tryParse(deposit.text.trim());
    final r = int.tryParse(rent.text.trim());
    final result = (ok == true && d != null && r != null)
        ? HousingPriceEntry(
            deposit: d,
            monthlyRent: r,
            maintenanceFee: int.tryParse(fee.text.trim()),
            roomType: roomType?.label ?? '',
            asOf: asOf.text.trim(),
            note: note.text.trim(),
          )
        : null;
    // 컨트롤러는 여기서 dispose하지 않는다. 대화상자가 닫히는 애니메이션
    // 동안 입력칸이 아직 그려져서, 바로 정리하면 disposed 컨트롤러 오류가 난다.
    if (ok == true && result == null && mounted) showToast(context, '보증금과 월세를 숫자로 입력해 주세요.');
    return result;
  }

  void _openEditBuildingSheet(BaseBuilding b, bool isDark, Color themeClr) {
    final existing = _overrides[b.id];
    final known = _resolvedKnown(b.id);
    final nameCtrl = TextEditingController(text: known?.name ?? b.officialName ?? '');
    final addrCtrl = TextEditingController(text: displayAddress(b, existing));
    final phoneCtrl = TextEditingController(text: existing?.landlordPhone ?? '');
    final floorCtrl = TextEditingController(text: (existing?.floors ?? b.floors).toString());
    final yearCtrl = TextEditingController(
      text: (existing?.builtYear ?? known?.builtYear ?? builtYearByName(b.officialName) ?? '').toString(),
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final mapFloorsCtrl = TextEditingController(text: existing?.mapFloors?.toString() ?? '');

    // 교내 건물은 원룸 구역이 아니라 "캠퍼스 시설"이 기본이다.
    HousingZone selectedZone = existing?.zone ??
        known?.zone ??
        (b.isCampus ? HousingZone.campus : HousingZone.values.first);
    Color? selectedColor = existing?.customColor;
    bool systemColor = existing?.usesSystemColor ?? false;
    // 창문은 지금 지도에 난 대로 시작한다(기본: 자취방 건물만).
    // (위에서 보기에선 창문을 안 그리니 그려진 창문이 아니라 원룸 여부로 본다.)
    final windowsAtStart = existing?.showWindows ??
        _buildings.any((x) => x.building.id == b.id && x.isOneRoom && !x.building.isCampus);
    var windowsOn = windowsAtStart;
    var shops = [...?existing?.shops];
    var prices = [...?existing?.prices];

    const colorPresets = kHousingPalette;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.edit_rounded, color: Color(0xFF03C75A), size: 20),
                    const SizedBox(width: 8),
                    const Text("건물 정보 및 색상 편집", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text("건물 ID: ${b.id}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 14),

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "건물 이름 (지도 및 목록에 표시)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                const Text("건물 지도 색상 (옥상 및 입체 벽면)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      onTap: () => setSheetState(() {
                        selectedColor = null;
                        systemColor = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (selectedColor == null && !systemColor)
                              ? const Color(0xFF03C75A).withValues(alpha: 0.15)
                              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (selectedColor == null && !systemColor) ? const Color(0xFF03C75A) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          "구역 색",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (selectedColor == null && !systemColor) ? FontWeight.bold : FontWeight.normal,
                            color: (selectedColor == null && !systemColor) ? const Color(0xFF03C75A) : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                    _systemColorChip(
                      selected: systemColor,
                      isDark: isDark,
                      onTap: () => setSheetState(() {
                        systemColor = true;
                        selectedColor = null;
                      }),
                    ),
                    ...colorPresets.map((clr) {
                      final isSel = !systemColor && selectedColor != null && selectedColor!.value == clr.value;
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          selectedColor = clr;
                          systemColor = false;
                        }),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: clr,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSel ? Colors.white : Colors.black12,
                              width: isSel ? 2.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: clr.withValues(alpha: isSel ? 0.5 : 0.2),
                                blurRadius: isSel ? 6 : 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: isSel ? Icon(Icons.check_rounded, color: paletteCheckColor(clr), size: 18) : null,
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<HousingZone>(
                  value: selectedZone,
                  decoration: const InputDecoration(labelText: "원룸 구역", border: OutlineInputBorder(), isDense: true),
                  items: HousingZone.values.map((z) => DropdownMenuItem(value: z, child: Text(z.label))).toList(),
                  onChanged: (v) => setSheetState(() => selectedZone = v ?? HousingZone.values.first),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: floorCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "층수", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: yearCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "준공연도", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mapFloorsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "지도 높이(층) — 선택",
                    helperText: "층고가 높아 실제 층수보다 높아 보여야 할 때만. 비우면 층수대로 그려요.",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: "도로명 주소", border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "임대인/관리실 연락처", border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: "개발자/관리자 메모", border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('창문 표시', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('벽에 창문을 그려요. 기본은 자취방 건물만 켜져 있어요.', style: TextStyle(fontSize: 11.5)),
                  value: windowsOn,
                  onChanged: (v) => setSheetState(() => windowsOn = v),
                ),
                const SizedBox(height: 8),

                // 상가 건물의 가게들
                _editorListSection<HousingShop>(
                  title: '가게 목록',
                  icon: Icons.storefront_rounded,
                  items: shops,
                  titleOf: (x) => x.name,
                  subtitleOf: (x) => x.detail,
                  onAdd: () async {
                    final x = await _editShopDialog(null);
                    if (x != null) setSheetState(() => shops = [...shops, x]);
                  },
                  onEdit: (i) async {
                    final x = await _editShopDialog(shops[i]);
                    if (x != null) setSheetState(() => shops = [...shops]..[i] = x);
                  },
                  onRemove: (i) => setSheetState(() => shops = [...shops]..removeAt(i)),
                ),
                const SizedBox(height: 12),

                // 개발자가 직접 적는 시세(여러 건)
                _editorListSection<HousingPriceEntry>(
                  title: '시세 (직접 입력)',
                  icon: Icons.payments_outlined,
                  items: prices,
                  titleOf: (x) => x.priceText,
                  subtitleOf: (x) => x.detail,
                  onAdd: () async {
                    final x = await _editPriceDialog(null);
                    if (x != null) setSheetState(() => prices = [...prices, x]);
                  },
                  onEdit: (i) async {
                    final x = await _editPriceDialog(prices[i]);
                    if (x != null) setSheetState(() => prices = [...prices]..[i] = x);
                  },
                  onRemove: (i) => setSheetState(() => prices = [...prices]..removeAt(i)),
                ),
                const SizedBox(height: 18),

                Row(
                  children: [
                    if (b.id.startsWith('custom_')) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: const Text("삭제"),
                        onPressed: () async {
                          try {
                            await HousingService.deleteCustomBuilding(b.id);
                          } catch (e) {
                            debugPrint('delete custom building error: $e');
                            if (mounted) showToast(context, adminWriteErrorMessage(e, what: '삭제'));
                            return;
                          }
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          setState(() {
                            _base = CampusBase(
                              buildings: _base.buildings.where((x) => x.id != b.id).toList(),
                              roads: _base.roads,
                              terrain: _base.terrain,
                              landuse: _base.landuse,
                            );
                            _overrides = Map.of(_overrides)..remove(b.id);
                            _peekBuilding = null;
                            _selectedId = null;
                            _rebuild();
                          });
                          showToast(context, "건물이 삭제되었습니다.");
                        },
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF03C75A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text("저장 및 즉시 반영", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            showToast(context, "건물 이름을 입력해 주세요.");
                            return;
                          }
                          final colorHex = systemColor
                              ? HousingBuildingOverride.systemColor
                              : selectedColor != null
                                  ? '#${selectedColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}'
                                  : null;
                          final override = HousingBuildingOverride(
                            buildingId: b.id,
                            name: name,
                            zone: selectedZone,
                            address: addrCtrl.text.trim().isNotEmpty ? addrCtrl.text.trim() : null,
                            landlordPhone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                            // b는 지도에 그려진 건물이라 floors가 지도 높이일 수 있다 —
                            // 표시 층수는 기존 값에서 가져온다.
                            floors: int.tryParse(floorCtrl.text.trim()) ?? existing?.floors ?? b.floors,
                            mapFloors: int.tryParse(mapFloorsCtrl.text.trim()),
                            builtYear: int.tryParse(yearCtrl.text.trim()),
                            note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                            customColorHex: colorHex,
                            // 이 시트에 칸이 없는 값은 기존 것을 그대로 둔다.
                            // 안 옮기면 저장할 때마다 외곽선·병합·삭제 표시가 지워진다.
                            landlordName: existing?.landlordName,
                            unitCount: existing?.unitCount,
                            customRing: existing?.customRing,
                            isDeleted: existing?.isDeleted,
                            mergedWith: existing?.mergedWith,
                            hideLabel: existing?.hideLabel,
                            // 처음 값에서 바꿨을 때만 따로 적는다(아니면 기본 규칙을 따른다).
                            showWindows: windowsOn != windowsAtStart ? windowsOn : existing?.showWindows,
                            shops: shops,
                            prices: prices,
                          );

                          try {
                            await HousingService.setOverride(override);
                          } catch (e) {
                            debugPrint('setOverride error: $e');
                            if (mounted) showToast(context, adminWriteErrorMessage(e));
                            return;
                          }
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          setState(() {
                            _overrides = {..._overrides, b.id: override};
                            _rebuild();
                          });
                          showToast(context, "'$name' 건물 정보와 색상이 저장되었습니다!");
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAddBuildingDialog(bool isDark, Color themeClr) {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final floorCtrl = TextEditingController(text: "3");
    HousingZone selectedZone = HousingZone.values.first;
    Color selectedColor = const Color(0xFF03C75A);

    const colorPresets = kHousingPalette;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_business_rounded, color: Color(0xFF03C75A)),
              SizedBox(width: 8),
              Text("새 건물 추가 (개발자)", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "건물 이름", hintText: "예: 청람파크빌", border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<HousingZone>(
                  value: selectedZone,
                  decoration: const InputDecoration(labelText: "원룸 구역", border: OutlineInputBorder(), isDense: true),
                  items: HousingZone.values.map((z) => DropdownMenuItem(value: z, child: Text(z.label))).toList(),
                  onChanged: (v) => setDlgState(() => selectedZone = v ?? HousingZone.values.first),
                ),
                const SizedBox(height: 12),
                const Text("건물 색상", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: colorPresets.map((clr) {
                    final isSel = selectedColor.value == clr.value;
                    return GestureDetector(
                      onTap: () => setDlgState(() => selectedColor = clr),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: clr,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? Colors.white : Colors.black12, width: isSel ? 2.5 : 1),
                        ),
                        child: isSel ? Icon(Icons.check, color: paletteCheckColor(clr), size: 16) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: floorCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "층수", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: addrCtrl,
                        decoration: const InputDecoration(labelText: "주소(선택)", hintText: "월탄3길 10", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("취소"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF03C75A), foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  showToast(context, "건물 이름을 입력해 주세요.");
                  return;
                }
                final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                // 기준 좌표: 원룸촌 중심 (320, 180) 주변에 사각형 생성
                const cx = 320.0, cy = 180.0, w = 16.0, h = 12.0;
                final ring = [
                  const Offset(cx - w / 2, cy - h / 2),
                  const Offset(cx + w / 2, cy - h / 2),
                  const Offset(cx + w / 2, cy + h / 2),
                  const Offset(cx - w / 2, cy + h / 2),
                ];
                final newBuilding = BaseBuilding(
                  id: newId,
                  officialName: name,
                  floors: int.tryParse(floorCtrl.text.trim()) ?? 3,
                  road: selectedZone.label,
                  buildingNo: '',
                  ring: ring,
                  isCampus: false,
                );
                final colorHex = '#${selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                final override = HousingBuildingOverride(
                  buildingId: newId,
                  name: name,
                  zone: selectedZone,
                  address: addrCtrl.text.trim().isNotEmpty ? addrCtrl.text.trim() : null,
                  floors: newBuilding.floors,
                  customColorHex: colorHex,
                );

                try {
                  await HousingService.saveCustomBuilding(building: newBuilding, override: override);
                } catch (e) {
                  debugPrint('add building save error: $e');
                  if (mounted) showToast(context, adminWriteErrorMessage(e));
                  return;
                }
                if (!mounted) return;
                Navigator.pop(ctx);
                setState(() {
                  _base = CampusBase(
                    buildings: [..._base.buildings, newBuilding],
                    roads: _base.roads,
                    terrain: _base.terrain,
                    landuse: _base.landuse,
                  );
                  _overrides = {..._overrides, newId: override};
                  _rebuild();
                });
                _focusBuilding(newBuilding);
                showToast(context, "'$name' 건물이 지도에 추가되었습니다!");
              },
              child: const Text("추가 완료"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _peekBadge(IconData icon, String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 3.5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: KnueTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  /// 개발자 모드 전용 지도 편집 툴바
  /// 도구 모음을 접었을 때 보여줄 지금 도구 이름.
  static const Map<HousingEditTool, String> _toolNames = {
    HousingEditTool.inspect: '탐색',
    HousingEditTool.addBlock: '블록추가',
    HousingEditTool.merge: '합치기',
    HousingEditTool.paint: '색칠하기',
    HousingEditTool.landmark: '위치',
    HousingEditTool.label: '이름표',
    HousingEditTool.reshape: '모양',
    HousingEditTool.delete: '삭제',
  };

  /// 폰에서 접힌 편집 도구 모음: 지금 도구 + 실행취소·저장 + 펼치기.
  Widget _buildCollapsedDevToolbar(bool isDark) {
    final fg = isDark ? Colors.white : Colors.black87;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161920).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF03C75A).withValues(alpha: 0.4), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _devToolbarCollapsed = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '🛠️ 편집: ${_toolNames[_editTool] ?? ''}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg, fontFamily: KnueTokens.fontFamily),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo_rounded, size: 18),
                tooltip: '실행취소',
                visualDensity: VisualDensity.compact,
                onPressed: _undoStack.isNotEmpty ? _undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Color(0xFF03C75A)),
                tooltip: '저장',
                visualDensity: VisualDensity.compact,
                onPressed: _saveAllEdits,
              ),
              IconButton(
                icon: const Icon(Icons.expand_more_rounded, size: 20),
                tooltip: '편집 도구 펼치기',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _devToolbarCollapsed = false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevEditorToolbar(bool isDark, Color themeClr) {
    if (_compact && _devToolbarCollapsed) return _buildCollapsedDevToolbar(isDark);
    const colorPresets = kHousingPalette;

    String toolHint = '';
    switch (_editTool) {
      case HousingEditTool.inspect:
        toolHint = '👆 건물 탭 시 상세 정보를 확인합니다.';
        break;
      case HousingEditTool.addBlock:
        toolHint = '➕ 지도의 빈 공간을 탭하여 새 건물 블록을 배치하세요.';
        break;
      case HousingEditTool.merge:
        toolHint = '🔗 합칠 건물들을 차례로 탭하세요 (${_mergeSelectedBuildingIds.length}개 선택됨)';
        break;
      case HousingEditTool.paint:
        toolHint = '🎨 아래 색상을 고른 뒤 건물을 탭하면 즉시 색상이 바뀝니다.';
        break;
      case HousingEditTool.delete:
        toolHint = '🗑️ 삭제할 건물을 탭하세요.';
        break;
      case HousingEditTool.label:
        toolHint = '🏷️ 건물을 탭하면 이름표를 숨기고, 숨긴 건물을 다시 탭하면 보여요.';
        break;
      case HousingEditTool.landmark:
        toolHint = '📍 빈 곳을 탭해 버스정류장·정문·후문·쪽문을 찍으세요. 찍은 마커는 끌어서 옮기고, 탭하면 이름 바꾸기·삭제.';
        break;
      case HousingEditTool.reshape:
        toolHint = _shapeDraft == null
            ? '✏️ 모양을 고칠 건물을 탭하세요.'
            : '✏️ 꼭짓점을 끌어 옮기고, 변 가운데 +로 추가. 지울 꼭짓점은 눌러 고른 뒤 아래 [꼭짓점 삭제]. ↺↻로 1°씩 돌리기, 컴퓨터에선 방향키로 옮기기. 지도 이동은 두 손가락으로.';
        break;
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF161920).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color(0xFF03C75A).withValues(alpha: 0.45)
                : const Color(0xFF03C75A).withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 도구 선택 바
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _devToolBtn(
                    tool: HousingEditTool.inspect,
                    icon: Icons.touch_app_rounded,
                    label: '탐색',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.addBlock,
                    icon: Icons.add_box_rounded,
                    label: '블록추가',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.merge,
                    icon: Icons.merge_type_rounded,
                    label: '합치기',
                    isDark: isDark,
                    badgeCount: _mergeSelectedBuildingIds.isNotEmpty
                        ? _mergeSelectedBuildingIds.length
                        : null,
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.paint,
                    icon: Icons.palette_rounded,
                    label: '색칠하기',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.label,
                    icon: Icons.label_off_outlined,
                    label: '이름표',
                    isDark: isDark,
                    activeColor: const Color(0xFF607D8B),
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.landmark,
                    icon: Icons.add_location_alt_rounded,
                    label: '위치',
                    isDark: isDark,
                    activeColor: const Color(0xFF2196F3),
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.reshape,
                    icon: Icons.polyline_rounded,
                    label: '모양',
                    isDark: isDark,
                    activeColor: const Color(0xFFFF9500),
                  ),
                  const SizedBox(width: 4),
                  _devToolBtn(
                    tool: HousingEditTool.delete,
                    icon: Icons.delete_outline_rounded,
                    label: '삭제',
                    isDark: isDark,
                    activeColor: Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 20,
                    width: 1,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(width: 8),
                  // 실행취소(Undo) 버튼
                  InkWell(
                    onTap: _undoStack.isNotEmpty ? _undo : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.undo_rounded,
                            size: 16,
                            color: _undoStack.isNotEmpty
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '실행취소',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _undoStack.isNotEmpty
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.grey,
                              fontFamily: KnueTokens.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 저장: 남은 편집을 올리고 서버가 받았는지 확인한다.
                  InkWell(
                    onTap: _saveAllEdits,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF03C75A).withValues(alpha: isDark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_upload_rounded, size: 16, color: Color(0xFF03C75A)),
                          const SizedBox(width: 3),
                          Text(
                            '저장',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF02A04A),
                              fontFamily: KnueTokens.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 폰: 도구 모음 접기
                  if (_compact)
                    IconButton(
                      icon: const Icon(Icons.expand_less_rounded, size: 20),
                      tooltip: '편집 도구 접기',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _devToolbarCollapsed = true),
                    ),
                ],
              ),
            ),

            // 색상 칠하기 모드일 때 색상 팔레트 바 노출
            if (_editTool == HousingEditTool.paint) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    Text(
                      '페인트 색상:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontFamily: KnueTokens.fontFamily,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _systemColorChip(
                      selected: _paintSystem,
                      isDark: isDark,
                      onTap: () => setState(() => _paintSystem = true),
                    ),
                    const SizedBox(width: 3),
                    ...colorPresets.map((clr) {
                      final isSel = !_paintSystem && _paintColor.toARGB32() == clr.toARGB32();
                      return GestureDetector(
                        onTap: () => setState(() {
                          _paintColor = clr;
                          _paintSystem = false;
                        }),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: clr,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSel
                                  ? (isDark ? Colors.white : Colors.black)
                                  : (isDark ? Colors.white30 : Colors.black12),
                              width: isSel ? 2.5 : 1.0,
                            ),
                            boxShadow: isSel
                                ? [
                                    BoxShadow(
                                      color: clr.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSel
                              ? Icon(
                                  Icons.check,
                                  size: 13,
                                  color: paletteCheckColor(clr),
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 5),
            // 하단 도움말 한 줄
            Text(
              toolHint,
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white54 : Colors.black54,
                fontFamily: KnueTokens.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _devToolBtn({
    required HousingEditTool tool,
    required IconData icon,
    required String label,
    required bool isDark,
    Color? activeColor,
    int? badgeCount,
  }) {
    final isSel = _editTool == tool;
    final primary = activeColor ?? const Color(0xFF03C75A);

    return InkWell(
      onTap: () {
        if (tool != HousingEditTool.reshape) _persistShapeDraft();
        setState(() {
          _editTool = tool;
          if (tool != HousingEditTool.merge) {
            _mergeSelectedBuildingIds.clear();
          }
          if (tool != HousingEditTool.reshape) {
            _shapeEditId = null;
            _shapeDraft = null;
            _dragVertex = null;
          }
          _rebuild();
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSel
              ? primary.withValues(alpha: isDark ? 0.35 : 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSel ? primary : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? primary : (isDark ? Colors.white70 : Colors.black87),
                fontFamily: KnueTokens.fontFamily,
              ),
            ),
            if (badgeCount != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 병합 모드 하단 액션 플로팅 바
  /// [이름표] 도구: 건물 이름표를 숨기거나 다시 보인다.
  Future<void> _toggleLabel(BaseBuilding b) async {
    final existing = _overrides[b.id];
    final hide = !(existing?.hideLabel ?? false);
    final updated = existing?.copyWith(hideLabel: hide) ??
        HousingBuildingOverride(
          buildingId: b.id,
          name: '',
          zone: HousingZone.values.first,
          hideLabel: hide,
        );
    _pushUndoSnapshot();
    setState(() {
      _overrides = {..._overrides, b.id: updated};
      _rebuild();
    });
    final name = _resolvedKnown(b.id)?.name ?? b.officialName ?? '건물';
    showToast(context, hide ? "🏷️ '$name' 이름표를 숨겼어요." : "🏷️ '$name' 이름표를 다시 보여요.");
    try {
      await HousingService.setOverride(updated);
    } catch (e) {
      debugPrint('label toggle error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e));
    }
  }

  // ── 버스정류장·정문·후문·쪽문 ─────────────────────────────

  bool get _landmarkToolOn =>
      AdminAuthService.isAdmin.value && _editTool == HousingEditTool.landmark;

  /// 찍은 위치 마커. 마커 크기는 확대와 상관없이 화면 기준으로 같다.
  ///  - 버스정류장: 모두에게 표지판만 보인다(이름은 위치 도구에서만).
  ///  - 정문·후문·쪽문: 지도엔 띄우지 않는다. 도보 거리 계산에만 쓰이고,
  ///    옮기거나 지울 수 있게 위치 도구를 켰을 때만 보인다.
  Widget _buildLandmarkOverlay(bool isDark) {
    const w = 150.0, h = 64.0;
    return IgnorePointer(
      ignoring: !_landmarkToolOn,
      child: AnimatedBuilder(
        animation: _transformController,
        builder: (context, _) {
          final zoom = _transformController.value.getMaxScaleOnAxis();
          final proj = _proj;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final l in _landmarks)
                if (l.kind == HousingLandmarkKind.busStop || _landmarkToolOn)
                () {
                  final world = (_dragLandmarkId == l.id ? _dragLandmarkWorld : null) ?? l.world;
                  final z = CampusElevation.elevationAt(world.dx, world.dy) * 0.45;
                  final p = proj.project(world.dx, world.dy, z) + _origin;
                  return Positioned(
                    left: p.dx - w / zoom / 2,
                    top: p.dy - h / zoom,
                    width: w / zoom,
                    height: h / zoom,
                    child: FittedBox(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _landmarkMarker(l, isDark),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
  }

  Widget _landmarkMarker(HousingLandmark l, bool isDark) {
    final dragging = _dragLandmarkId == l.id;
    if (l.kind == HousingLandmarkKind.busStop) {
      return _busStopMarker(l, isDark, dragging, showName: _landmarkToolOn);
    }
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: l.kind.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: dragging ? 2 : 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(l.kind.icon, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              l.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFamily: KnueTokens.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => setState(() {
        _dragLandmarkId = l.id;
        _dragLandmarkWorld = l.world;
        _dragLandmarkMoved = false;
        _dragLandmarkDownAt = e.position;
      }),
      onPointerMove: (e) => _dragLandmarkTo(e.position),
      onPointerUp: (_) => _endLandmarkDrag(l),
      onPointerCancel: (_) => setState(() {
        _dragLandmarkId = null;
        _dragLandmarkWorld = null;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill,
          // 핀 꼬리: 정확히 어디를 찍었는지 보이게.
          Container(width: 2, height: 8, color: l.kind.color),
        ],
      ),
    );
  }

  /// 버스정류장은 정류장 표지판처럼: 파란 네모 판에 버스 그림, 기둥. 이름은 [showName]일 때만 위에.
  Widget _busStopMarker(HousingLandmark l, bool isDark, bool dragging, {required bool showName}) {
    const blue = Color(0xFF1E6FD9);
    final sign = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: blue,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: dragging ? 2.2 : 1.6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: const Icon(Icons.directions_bus_filled_rounded, size: 16, color: Colors.white),
    );
    final name = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2230) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: blue.withValues(alpha: 0.6)),
      ),
      child: Text(
        l.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : blue,
          fontFamily: KnueTokens.fontFamily,
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => setState(() {
        _dragLandmarkId = l.id;
        _dragLandmarkWorld = l.world;
        _dragLandmarkMoved = false;
        _dragLandmarkDownAt = e.position;
      }),
      onPointerMove: (e) => _dragLandmarkTo(e.position),
      onPointerUp: (_) => _endLandmarkDrag(l),
      onPointerCancel: (_) => setState(() {
        _dragLandmarkId = null;
        _dragLandmarkWorld = null;
      }),
      // 이름·표지판·기둥을 세로로 가운데 맞춘다 — 기둥 끝이 정확히 찍은 자리다.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showName) ...[
            Flexible(child: name),
            const SizedBox(height: 2),
          ],
          sign,
          Container(width: 2.5, height: 12, color: const Color(0xFF7A8699)),
        ],
      ),
    );
  }

  void _dragLandmarkTo(Offset globalPos) {
    if (_dragLandmarkId == null) return;
    // 손가락이 살짝 떨린 건 탭으로 본다.
    if (!_dragLandmarkMoved && (globalPos - _dragLandmarkDownAt).distance < 8) return;
    final box = _mapCanvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos) - _origin;
    final world = _proj.unproject(local.dx, local.dy);
    setState(() {
      _dragLandmarkWorld = world;
      _dragLandmarkMoved = true;
    });
  }

  Future<void> _endLandmarkDrag(HousingLandmark l) async {
    final moved = _dragLandmarkMoved;
    final world = _dragLandmarkWorld;
    if (!moved || world == null) {
      setState(() {
        _dragLandmarkId = null;
        _dragLandmarkWorld = null;
      });
      // 끌지 않고 뗐으면 탭 — 이름 바꾸기·삭제.
      await _promptLandmark(existing: l);
      return;
    }
    try {
      await HousingLandmarkService.save(l.copyWith(world: world));
    } catch (e) {
      debugPrint('landmark move error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e));
    }
    if (!mounted) return;
    // 저장 결과는 실시간 리스너가 돌려준다. 그때까지 끈 자리에 둔다.
    setState(() {
      _dragLandmarkId = null;
      _dragLandmarkWorld = null;
    });
  }

  /// 새 위치 찍기([world]) 또는 찍은 위치 고치기([existing]).
  Future<void> _promptLandmark({Offset? world, HousingLandmark? existing}) async {
    var kind = existing?.kind ?? HousingLandmarkKind.busStop;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '위치 찍기' : '위치 고치기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in HousingLandmarkKind.values)
                    ChoiceChip(
                      avatar: Icon(k.icon, size: 16, color: kind == k ? Colors.white : k.color),
                      label: Text(k.label),
                      selected: kind == k,
                      selectedColor: k.color,
                      labelStyle: TextStyle(color: kind == k ? Colors.white : null),
                      onSelected: (_) => setDlg(() => kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '이름',
                  hintText: kind == HousingLandmarkKind.busStop ? '예: 탑연삼거리, 교원대 정문' : '비우면 "${kind.label}"',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (kind == HousingLandmarkKind.busStop)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '이름에 "탑연"이 들어간 정류장은 원룸 상세의 "정류장 n분" 계산에 쓰여요.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('삭제'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('저장')),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    // 컨트롤러는 여기서 dispose하지 않는다. 대화상자가 닫히는 애니메이션
    // 동안 입력칸이 아직 그려져서, 바로 정리하면 disposed 컨트롤러 오류가 난다.
    if (!mounted || result == null) return;
    try {
      if (result == 'delete' && existing != null) {
        await HousingLandmarkService.delete(existing.id);
        if (mounted) showToast(context, "'${existing.label}' 위치를 지웠어요.");
      } else if (result == 'save') {
        final l = existing?.copyWith(kind: kind, name: name) ??
            HousingLandmark.atWorld(
              id: 'lm_${DateTime.now().millisecondsSinceEpoch}',
              kind: kind,
              name: name,
              world: world!,
            );
        await HousingLandmarkService.save(l);
        if (mounted) showToast(context, "📍 '${l.label}' 위치를 저장했어요.");
      }
    } catch (e) {
      debugPrint('landmark save error: $e');
      if (mounted) showToast(context, adminWriteErrorMessage(e, what: result == 'delete' ? '삭제' : '저장'));
    }
  }

  // ── 건물 모양 고치기 ──────────────────────────────────────

  /// 손잡이를 띄울 높이. 눈에 보이는 윤곽이 지붕이라 거기 있어야 어느
  /// 모서리인지 바로 안다. 편집 동안은 고정한다(꼭짓점을 옮기면 중심이
  /// 바뀌어 고도가 달라지는데, 그걸 따라가면 손잡이가 손가락 밑에서 샌다).
  double _shapeEditZ = 0;

  /// 저장 안 한 모양 변경이 있는지. 손을 멈추면 [_shapeAutoSave]가 1초 뒤
  /// 올리고, 닫거나 다른 건물·도구로 바꾸거나 화면을 나갈 때도 올린다.
  /// (예전엔 막대의 [저장]을 안 누르면 그냥 버려져서, 나갔다 오면 고친
  /// 모양이 사라져 있었다.)
  bool _shapeDirty = false;
  Timer? _shapeAutoSave;

  /// 올리다 실패한 쓰기 수. [저장] 버튼이 결과를 알려줄 때 쓴다.
  int _saveFailures = 0;

  void _markShapeDirty() {
    _shapeDirty = true;
    _shapeAutoSave?.cancel();
    _shapeAutoSave = Timer(const Duration(seconds: 1), _persistShapeDraft);
  }

  /// 편집 중인 모양을 서버로 올린다(기다리지 않음). 화면을 닫는 중에도
  /// 부를 수 있게 setState를 쓰지 않는다 — 실시간 리스너가 로컬 쓰기를
  /// 곧바로 돌려줘 화면은 그쪽으로 갱신된다.
  void _persistShapeDraft() {
    _shapeAutoSave?.cancel();
    _shapeAutoSave = null;
    final id = _shapeEditId;
    final draft = _shapeDraft;
    if (!_shapeDirty || id == null || draft == null || draft.length < 3) return;
    _shapeDirty = false;
    // 이름·구역을 정해 둔 적 없는 건물이면 이름을 비워 둔다 — 모양만 고친
    // 문서로 남아 색·이름표는 그대로다(HousingBuildingOverride.isNamed).
    final override = _overrides[id]?.copyWith(customRing: draft) ??
        HousingBuildingOverride(
          buildingId: id,
          name: '',
          zone: HousingZone.values.first,
          customRing: draft,
        );
    _overrides = {..._overrides, id: override};
    HousingService.setOverride(override).catchError((Object e) {
      debugPrint('shape save error: $e');
      _saveFailures++;
      if (mounted) showToast(context, adminWriteErrorMessage(e));
    });
  }

  /// 도구 모음 [저장]: 남은 편집을 올리고 서버가 받았는지 확인해 알려준다.
  Future<void> _saveAllEdits() async {
    _persistShapeDraft();
    final failuresBefore = _saveFailures;
    showToast(context, '저장하는 중…');
    try {
      await HousingService.waitForPendingWrites();
      if (!mounted) return;
      if (_saveFailures > failuresBefore) {
        showToast(context, '일부를 저장하지 못했어요. 관리자 권한을 확인해 주세요.');
      } else {
        showToast(context, '✅ 서버에 모두 저장했어요.');
      }
    } on TimeoutException {
      if (mounted) showToast(context, '아직 서버에 올리는 중이에요. 네트워크를 확인해 주세요 — 연결되면 이어서 올라가요.');
    } catch (e) {
      debugPrint('waitForPendingWrites error: $e');
      if (mounted) showToast(context, '저장 상태를 확인하지 못했어요.');
    }
  }

  void _startShapeEdit(BaseBuilding b) {
    _persistShapeDraft(); // 고치던 다른 건물이 있으면 먼저 올린다
    _mapFocus.requestFocus();
    final proj = _proj;
    setState(() {
      _shapeEditId = b.id;
      _shapeDraft = openRing(b.ring);
      _shapeEditZ = buildingBaseZ(b) + proj.heightOf(b);
      _dragVertex = null;
      _selectedVertex = null;
      _peekBuilding = null;
      _rebuild();
    });
  }

  void _endShapeEdit() {
    _persistShapeDraft();
    setState(() {
      _shapeEditId = null;
      _shapeDraft = null;
      _dragVertex = null;
      _selectedVertex = null;
      _rebuild();
    });
  }

  Offset _shapeToCanvas(Offset p) {
    final proj = _proj;
    return proj.project(p.dx, p.dy, _shapeEditZ) + _origin;
  }

  void _dragShapeVertex(int i, Offset globalPos) {
    final box = _mapCanvasKey.currentContext?.findRenderObject() as RenderBox?;
    final draft = _shapeDraft;
    if (box == null || draft == null || i >= draft.length) return;
    // globalToLocal이 InteractiveViewer의 확대·이동을 거꾸로 풀어 준다.
    final local = box.globalToLocal(globalPos) - _origin;
    final proj = _proj;
    final world = proj.unproject(local.dx, local.dy, _shapeEditZ);
    setState(() => _shapeDraft = moveRingVertex(draft, i, world));
    _markShapeDirty();
  }

  /// 손가락에 가장 가까운 손잡이를 잡는다(pickShapeHandle). "+"면 그 자리에
  /// 꼭짓점을 새로 만들고 곧바로 그걸 끈다.
  void _beginShapeDrag(Offset globalPos) {
    final box = _mapCanvasKey.currentContext?.findRenderObject() as RenderBox?;
    final draft = _shapeDraft;
    if (box == null || draft == null || draft.isEmpty) return;
    final pick = pickShapeHandle(
      [for (final p in draft) _shapeToCanvas(p)],
      [for (final p in ringMidpoints(draft)) _shapeToCanvas(p)],
      box.globalToLocal(globalPos),
    );
    if (pick == null) return;
    _mapFocus.requestFocus();
    setState(() {
      if (pick.isMidpoint) {
        _shapeDraft = insertRingMidpoint(draft, pick.index);
        _markShapeDirty();
        _dragVertex = pick.index + 1;
      } else {
        _dragVertex = pick.index;
      }
      _selectedVertex = _dragVertex;
    });
  }

  /// 고른 꼭짓점. 마지막으로 누른 꼭짓점이고, [꼭짓점 삭제] 버튼이 이걸 지운다.
  /// (두 번 탭으로 지우던 방식은 첫 탭이 끌기로 잡혀 잘 안 먹혔다.)
  int? _selectedVertex;

  void _endShapeDrag() {
    if (_dragVertex == null) return;
    setState(() {
      _dragVertex = null;
      _rebuild();
    });
  }

  void _removeSelectedVertex() {
    final draft = _shapeDraft;
    final i = _selectedVertex;
    if (draft == null || i == null || i >= draft.length) return;
    final next = removeRingVertex(draft, i);
    if (next == null) {
      showToast(context, '꼭짓점은 3개 밑으로 줄일 수 없어요.');
      return;
    }
    setState(() {
      _shapeDraft = next;
      _selectedVertex = null;
      _rebuild();
    });
    _markShapeDirty();
  }

  /// 편집 중인 모양을 [degrees]만큼 돌린다(양수 = 위에서 볼 때 시계 방향).
  /// [rebuild]가 false면 손잡이만 다시 그린다 — 버튼을 누르고 있는 동안
  /// 매번 지도 전체를 다시 계산하면 버벅인다.
  void _rotateShapeDraft(double degrees, {bool rebuild = true}) {
    final draft = _shapeDraft;
    if (draft == null) return;
    setState(() {
      _shapeDraft = rotateRing(draft, degrees);
      if (rebuild) _rebuild();
    });
    _markShapeDirty();
  }

  /// 누르고 있으면 계속 도는 타이머.
  Timer? _rotateRepeat;

  Widget _rotateButton(double step, IconData icon, String tooltip) {
    void stop() {
      if (_rotateRepeat == null) return;
      _rotateRepeat?.cancel();
      _rotateRepeat = null;
      if (mounted) setState(_rebuild);
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onLongPressStart: (_) {
          _rotateRepeat?.cancel();
          _rotateRepeat = Timer.periodic(
            const Duration(milliseconds: 90),
            (_) => _rotateShapeDraft(step, rebuild: false),
          );
        },
        onLongPressEnd: (_) => stop(),
        onLongPressCancel: stop,
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: () => _rotateShapeDraft(step),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// 지도 데이터에 원래 있던 모양으로 되돌린다(저장해야 반영된다).
  void _resetShapeDraft() {
    final id = _shapeEditId;
    if (id == null) return;
    BaseBuilding? original;
    for (final b in _base.buildings) {
      if (b.id == id) original = b;
    }
    if (original == null) return;
    final ring = openRing(original.ring);
    setState(() {
      _shapeDraft = ring;
      _selectedVertex = null;
      _rebuild();
    });
    _markShapeDirty();
  }

  /// 모양 막대 [저장]: 지금 모양을 올리고 편집을 닫은 뒤 서버 확인까지.
  Future<void> _saveShapeEdit() async {
    if (_shapeEditId == null || (_shapeDraft?.length ?? 0) < 3) return;
    _shapeDirty = true; // 바뀐 게 없어 보여도 버튼을 누르면 늘 올린다
    _pushUndoSnapshot();
    _endShapeEdit();
    await _saveAllEdits();
  }

  /// 지도 위에 겹치는 편집 손잡이. 지도와 함께 확대·이동되고, 손잡이
  /// 크기만 화면 기준으로 일정하게 유지한다.
  Widget _buildShapeOverlay(bool isDark) {
    const accent = Color(0xFFFF9500);
    return AnimatedBuilder(
      animation: _transformController,
      builder: (context, _) {
        final draft = _shapeDraft;
        if (draft == null) return const SizedBox.shrink();
        final zoom = _transformController.value.getMaxScaleOnAxis();
        final pts = [for (final p in draft) _shapeToCanvas(p)];
        final mids = [for (final p in ringMidpoints(draft)) _shapeToCanvas(p)];
        final touch = 40 / zoom;
        Widget dot(double d, Color fill, {IconData? icon}) => Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2 / zoom),
              ),
              child: icon == null ? null : Icon(icon, size: d * 0.8, color: accent),
            );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ShapeOutlinePainter(pts, accent, 2 / zoom)),
              ),
            ),
            for (var i = 0; i < mids.length; i++)
              Positioned(
                left: mids[i].dx - touch / 2,
                top: mids[i].dy - touch / 2,
                width: touch,
                height: touch,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _beginShapeDrag(e.position),
                  onPointerMove: (e) {
                    final v = _dragVertex;
                    if (v != null) _dragShapeVertex(v, e.position);
                  },
                  onPointerUp: (_) => _endShapeDrag(),
                  onPointerCancel: (_) => _endShapeDrag(),
                  child: Center(
                    child: dot(14 / zoom, Colors.white.withValues(alpha: 0.85), icon: Icons.add_rounded),
                  ),
                ),
              ),
            for (var i = 0; i < pts.length; i++)
              Positioned(
                left: pts[i].dx - touch / 2,
                top: pts[i].dy - touch / 2,
                width: touch,
                height: touch,
                // 끌기는 제스처 경쟁을 거치지 않는 Listener로 받는다 —
                // 지도(InteractiveViewer)와 손가락을 다투지 않게.
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _beginShapeDrag(e.position),
                  onPointerMove: (e) {
                    final v = _dragVertex;
                    if (v != null) _dragShapeVertex(v, e.position);
                  },
                  onPointerUp: (_) => _endShapeDrag(),
                  onPointerCancel: (_) => _endShapeDrag(),
                  child: Center(
                    child: dot(
                      (_dragVertex == i ? 22 : (_selectedVertex == i ? 19 : 16)) / zoom,
                      (_dragVertex == i || _selectedVertex == i) ? accent : Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildShapeEditBar(bool isDark) {
    const accent = Color(0xFFFF9500);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF161922).withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.polyline_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedVertex == null
                        ? '꼭짓점 ${_shapeDraft?.length ?? 0}개'
                        : '꼭짓점 ${_shapeDraft?.length ?? 0}개 · ${_selectedVertex! + 1}번 선택됨',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                      fontFamily: KnueTokens.fontFamily,
                    ),
                  ),
                ),
                _rotateButton(-1, Icons.rotate_left_rounded, '왼쪽으로 1° 돌리기'),
                _rotateButton(1, Icons.rotate_right_rounded, '오른쪽으로 1° 돌리기'),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: _endShapeEdit,
                  tooltip: '편집 닫기(자동 저장)',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  // 고른 꼭짓점이 없거나 셋뿐이면 누를 수 없다.
                  onPressed: (_selectedVertex != null && (_shapeDraft?.length ?? 0) > 3)
                      ? _removeSelectedVertex
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: (_selectedVertex != null && (_shapeDraft?.length ?? 0) > 3)
                          ? Colors.redAccent
                          : Colors.grey.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                  label: const Text('꼭짓점 삭제', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _resetShapeDraft,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('원래대로', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saveShapeEdit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "시스템" 색 선택지. 고르면 고정 색 없이 밝은/다크 모드 기본 건물 색을 따른다.
  Widget _systemColorChip({
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const green = Color(0xFF03C75A);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? green.withValues(alpha: 0.15)
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? green : Colors.transparent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.brightness_6_rounded,
              size: 14,
              color: selected ? green : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 4),
            Text(
              '시스템',
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? green : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMergeFloatingBar(bool isDark, Color themeClr) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF161922).withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF007AFF).withValues(alpha: 0.4),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.merge_type_rounded, color: Color(0xFF007AFF), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_mergeSelectedBuildingIds.length}개 건물 선택됨',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFamily: KnueTokens.fontFamily,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _promptMergeSelectedBuildings,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('하나로 합치기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                setState(() {
                  _mergeSelectedBuildingIds.clear();
                  _rebuild();
                });
              },
              tooltip: '선택 취소',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareFloatingBar(bool isDark, Color themeClr) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1E26).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: const Color(0xFF007AFF).withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.compare_arrows_rounded, size: 18, color: Color(0xFF007AFF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '비교함 ${_compareBuildingIds.length}/3 담김',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '원룸 시세 및 도보거리를 한눈에 비교해보세요',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => _showCompareSheet(isDark),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('비교 보기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: isDark ? Colors.white54 : Colors.black45,
              onPressed: () => setState(() => _compareBuildingIds.clear()),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
  Widget _hudIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildMap(bool isDark) {
    // 배경색은 바닥색과 한 세트다. 따로 정하면 대비가 어긋나므로
    // housing_iso.dart 한 곳에서 가져온다.
    final mapBg = mapBackgroundColor(isDark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final newViewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewportSize != newViewport || _transformController.value.isIdentity()) {
          final isFirstLayout = _viewportSize == Size.zero || _transformController.value.isIdentity();
          _viewportSize = newViewport;
          if (isFirstLayout) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerHome();
            });
          }
        }

        return Container(
          color: mapBg,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            children: [
              Positioned.fill(child: _buildMapCanvas(isDark)),
              // 도로는 OpenStreetMap 데이터(ODbL)다. 출처 표기는 선택이
              // 아니라 라이선스 조건이므로 지도가 보이는 동안 늘 띄운다.
              Positioned(
                right: 6,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      '도로 © OpenStreetMap 기여자',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapCanvas(bool isDark) {
    // 1. 원룸 시세 말풍선 맵 생성 (기본 끈 상태, 토글 켰을 때 전체 표시 또는 선택 건물 표시)
    final priceTags = <String, String>{};
    for (final b in _effectiveBuildings) {
      if (b.isCampus || _campusMode) continue;
      final isTarget = _showPriceTags || b.id == _selectedId || b.id == _peekBuilding?.id;
      if (!isTarget) continue;

      // 제보된 시세 → 개발자가 적은 최근 시세 순. 둘 다 없으면 띄우지 않는다
      // (예전엔 이름만 있어도 지어낸 "200/34"를 띄웠다).
      final p = _summaries[b.id]?.getPricing(HousingRoomType.oneRoom);
      final entered = sortedPriceEntries(_overrides[b.id]?.prices ?? const []);
      if (p != null) {
        priceTags[b.id] = '${p.deposit}/${p.monthlyRent}';
      } else if (entered.isNotEmpty) {
        priceTags[b.id] = '${entered.first.deposit}/${entered.first.monthlyRent}';
      }
    }

    // 2. 누른 건물. 등시선을 켰으면 이 건물을 기준으로 그린다.
    //    (예전엔 여기서 정문까지 직선을 그어 "도보 n분"을 띄웠다 — 뺐다.)
    BaseBuilding? activeBuilding;
    if (_selectedId != null) {
      for (final b in _effectiveBuildings) {
        if (b.id == _selectedId) {
          activeBuilding = b;
          break;
        }
      }
    }
    activeBuilding ??= _peekBuilding;

    final active = activeBuilding;
    final isochrone = (_showIsochrone && active != null)
        ? IsochroneCenter(
            _resolvedKnown(active.id)?.name ?? active.officialName ?? '이 건물',
            active.center,
          )
        : null;

    return Focus(
      focusNode: _mapFocus,
      onKeyEvent: _onMapKey,
      child: InteractiveViewer(
      transformationController: _transformController,
      // 모양을 고치는 동안 한 손가락은 꼭짓점을 끄는 데 쓴다. 지도는 두
      // 손가락으로 옮긴다.
      panEnabled: _shapeDraft == null && _dragLandmarkId == null,
      constrained: false,
      // 너무 멀리 빠지면 지도가 점이 된다 — 원룸촌 전체가 보일 정도까지만.
      minScale: 0.3,
      maxScale: 8.0,
      boundaryMargin: const EdgeInsets.all(4000),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        key: _mapCanvasKey,
        clipBehavior: Clip.none,
        children: [
      GestureDetector(
        onTapUp: (d) => _onTapMap(d.localPosition),
        child: CustomPaint(
          size: _canvas,
          painter: HousingMapPainter(
            buildings: _buildings,
            roads: _roadPaths,
            terrain: _isoTerrain,
            landuse: _landuse,
            isDark: isDark,
            origin: _origin,
            osmRoads: _isoOsmRoads,
            // 건물 번호 배지는 쓰지 않는다(숫자 마커가 지도를 어지럽혔다).
            showBuildingNumbers: false,
            shadows: _shadowPath,
            projection: _proj,
            // 이름표를 화면 고정 크기로 그리려면 지금 배율을 알아야 한다.
            view: _transformController,
            priceTags: priceTags,
            isochroneCenter: isochrone,
          ),
        ),
      ),
          if (_landmarks.isNotEmpty) Positioned.fill(child: _buildLandmarkOverlay(isDark)),
          if (_shapeDraft != null) Positioned.fill(child: _buildShapeOverlay(isDark)),
        ],
      ),
      ),
    );
  }

  /// 방향키 → 화면 방향.
  static final Map<LogicalKeyboardKey, Offset> _arrowDirs = {
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
  };

  /// 편집 중인 모양을 화면 방향 [screenDir]로 [meters]만큼 옮긴다.
  void _moveShapeDraft(Offset screenDir, double meters, {bool rebuild = true}) {
    final draft = _shapeDraft;
    if (draft == null) return;
    final proj = _proj;
    final delta = screenDirToWorld(
      (sx, sy) => proj.unproject(sx, sy, _shapeEditZ),
      screenDir.dx,
      screenDir.dy,
      meters,
    );
    setState(() {
      _shapeDraft = translateRing(draft, delta);
      if (rebuild) _rebuild();
    });
    _markShapeDirty();
  }

  /// 모양 고치는 중 키보드(컴퓨터용): Esc·Delete·Backspace = 고른 꼭짓점
  /// 지우기, [ ] = 왼쪽·오른쪽으로 1° 돌리기, 방향키 = 0.5m씩 옮기기
  /// (Shift를 같이 누르면 3m). 누르고 있으면 계속된다.
  KeyEventResult _onMapKey(FocusNode node, KeyEvent e) {
    if (_shapeDraft == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final arrow = _arrowDirs[k];
    if (arrow != null) {
      // 누르고 있는 동안(반복)은 손잡이만 옮기고, 손을 뗄 때 지도를 다시 계산한다.
      if (e is KeyUpEvent) {
        setState(_rebuild);
      } else {
        final fast = HardwareKeyboard.instance.isShiftPressed;
        _moveShapeDraft(arrow, fast ? 3.0 : 0.5, rebuild: e is KeyDownEvent);
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.bracketLeft || k == LogicalKeyboardKey.bracketRight) {
      _rotateShapeDraft(k == LogicalKeyboardKey.bracketLeft ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (k != LogicalKeyboardKey.escape &&
        k != LogicalKeyboardKey.delete &&
        k != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_selectedVertex == null) {
      showToast(context, '지울 꼭짓점을 먼저 눌러 고르세요.');
    } else {
      _removeSelectedVertex();
    }
    return KeyEventResult.handled;
  }



  void _showDetail(BaseBuilding b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => HousingDetailSheet(
          building: b,
          // 캠퍼스맵에 있던 교내 건물 정보(설명·층별 호실)를 이어 붙인다.
          campusInfo: b.isCampus ? _campusInfoById[b.id] : null,
          summary: _summaries[b.id] ?? HousingSummary.empty,
          known: _resolvedKnown(b.id),
          edited: _overrides[b.id],
          isDark: isDark,
          isFavorite: _favoriteIds.contains(b.id),
          isCompared: _compareBuildingIds.contains(b.id),
          onToggleFavorite: () => _toggleFavorite(b.id),
          onToggleCompare: b.isCampus ? null : () {
            _toggleCompare(b.id);
            setSheetState(() {});
          },
          onReported: () async {
            final r = await HousingService.fetchReportsByBuilding();
            if (!mounted) return;
            // 다시 받기에 실패하면(null) 덮어쓰지 않는다 — 지도 전체의 시세·
            // 제보가 사라진다.
            if (r == null) return;
            setState(() {
              _reports = r;
              _rebuild();
            });
            // 열려 있는 상세 창에도 방금 남긴 제보가 바로 보이게 다시 그린다.
            // (예전엔 창을 닫았다 열어야 보였다.)
            if (ctx.mounted) setSheetState(() {});
          },
          onShowOnMap: _isListView
              ? () {
                  Navigator.pop(context);
                  setState(() => _isListView = false);
                  _focusBuilding(b, openDetail: false);
                }
              : null,
          onEditBuilding: () => _openEditBuildingSheet(b, isDark, themeColor.value),
        ),
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _selectedId = null;
        _rebuild();
      });
    });
  }

  Future<void> _openFilterSheet(bool isDark) async {
    final result = await showModalBottomSheet<HousingFilter>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HousingFilterSheet(
        initial: _filter,
        isDark: isDark,
        countMatches: (f) =>
            _filterVerdicts(f).values.where((r) => housingPassesFilter(r.verdict, f)).length,
        countUnknown: (f) =>
            _filterVerdicts(f).values.where((r) => r.verdict == HousingFilterVerdict.unknown).length,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filter = result;
      _rebuild();
    });
    if (!_filter.isEmpty) _showFilterResults(isDark);
  }

  /// 조건에 맞는 원룸 목록. 지도에서 찾아 헤매는 대신 시세를 나란히 비교하고,
  /// 기숙사 비용과도 견줄 수 있게 한다.
  void _showFilterResults(bool isDark) {
    final verdicts = _filterVerdicts(_filter);
    final byId = {for (final b in _effectiveBuildings) b.id: b};
    List<({String name, BaseBuilding building, HousingPricePoint? best})> rowsOf(HousingFilterVerdict v) {
      final rows = [
        for (final e in verdicts.entries)
          if (e.value.verdict == v && byId[e.key] != null)
            (
              name: _resolvedKnown(e.key)?.name ?? byId[e.key]!.officialName ?? '이름 미확인 건물',
              building: byId[e.key]!,
              best: e.value.best,
            ),
      ];
      // 맞는 방 월 부담이 싼 순, 같으면 보증금이 싼 순. 시세 없는 건 뒤로.
      rows.sort((x, y) {
        final xm = x.best?.monthly(withMaintenance: _filter.includeMaintenance) ?? 1 << 30;
        final ym = y.best?.monthly(withMaintenance: _filter.includeMaintenance) ?? 1 << 30;
        if (xm != ym) return xm.compareTo(ym);
        return (x.best?.deposit ?? 1 << 30).compareTo(y.best?.deposit ?? 1 << 30);
      });
      return rows;
    }

    final matched = rowsOf(HousingFilterVerdict.match);
    final unknown = rowsOf(HousingFilterVerdict.unknown);
    final sub = isDark ? Colors.white38 : Colors.black45;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "조건에 맞는 원룸 ${matched.length}곳",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _openFilterSheet(isDark);
                    },
                    child: const Text("조건 수정"),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "학생 제보와 확인된 시세를 방마다 비교해요. 금액은 그 조건에 맞는 가장 싼 방이에요.",
                style: TextStyle(fontSize: 11.5, color: sub),
              ),
              const SizedBox(height: 14),
              _buildDormComparison(
                [for (final r in matched) if (_summaries[r.building.id] case final s?) s],
                isDark,
              ),
              const SizedBox(height: 14),
              if (matched.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    // 시세가 아직 적어서 0곳인 경우가 많다 — 그땐 금액 탓이 아니다.
                    unknown.isNotEmpty
                        ? "시세가 등록된 원룸 중엔 맞는 곳이 없어요.\n아래 시세를 모르는 원룸 ${unknown.length}곳도 확인해 보세요."
                        : "조건에 맞는 곳이 없어요.\n금액을 조금 올리거나 조건을 줄여보세요.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: sub),
                  ),
                )
              else
                ...matched.map((r) => _buildFilterResultRow(r.name, r.building, r.best, isDark, sheetCtx)),

              // 시세가 없어 판단할 수 없는 원룸
              if (unknown.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                if (_filter.includeUnknown) ...[
                  const SizedBox(height: 6),
                  Text(
                    "시세를 몰라 확인이 필요한 원룸 ${unknown.length}곳",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text("시세·정보가 아직 등록되지 않았어요. 직접 문의해 보세요.", style: TextStyle(fontSize: 11.5, color: sub)),
                  ...unknown.map((r) => _buildFilterResultRow(r.name, r.building, null, isDark, sheetCtx)),
                ] else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "시세를 몰라 뺀 원룸 ${unknown.length}곳",
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    subtitle: Text("시세가 등록되면 조건과 비교할 수 있어요.", style: TextStyle(fontSize: 11.5, color: sub)),
                    trailing: TextButton(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        setState(() {
                          _filter = _filter.copyWith(includeUnknown: true);
                          _rebuild();
                        });
                        _showFilterResults(isDark);
                      },
                      child: const Text("같이 보기"),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 결과 한 줄: 이름, 맞는 방(구조·출처), 월 부담·보증금. [best]가 없으면 시세 모름.
  Widget _buildFilterResultRow(
    String name,
    BaseBuilding building,
    HousingPricePoint? best,
    bool isDark,
    BuildContext sheetCtx,
  ) {
    final monthly = best?.monthly(withMaintenance: _filter.includeMaintenance);
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white38 : Colors.black45;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetCtx);
        _focusBuilding(building);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    best == null
                        ? displayAddress(building, _overrides[building.id])
                        : [
                            best.roomType?.label ?? '방 구조 모름',
                            best.fromReports ? '학생 제보' : '확인 시세${best.asOf != null && best.asOf!.isNotEmpty ? ' ${best.asOf}' : ''}',
                            if (_filter.includeMaintenance && !best.maintenanceKnown) '관리비 모름',
                          ].join(' · '),
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  monthly == null ? "시세 모름" : "월 $monthly만원",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: monthly == null ? sub : fg,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
                if (best != null)
                  Text(
                    "보증금 ${best.deposit}만원",
                    style: TextStyle(fontSize: 11, color: sub, fontFeatures: KnueTokens.tabularFigures),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 결과 창의 기숙사 비교 카드에서 고른 기숙사.
  int _filterDormIndex = 0;

  Widget _buildDormComparison(List<HousingSummary> matched, bool isDark) {
    final monthlies =
        matched.map((s) => s.avgMonthlyTotal).whereType<int>().toList()
          ..sort();
    final int? cheapest = monthlies.isEmpty ? null : monthlies.first;

    return StatefulBuilder(
      builder: (context, setCardState) {
        final currentDorm = kDormCosts[_filterDormIndex.clamp(0, kDormCosts.length - 1)];
        final currentDiff = cheapest == null ? null : cheapest - currentDorm.monthlyHousing;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.apartment_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "기숙사 비용과 비교",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 기숙사 선택 칩
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(kDormCosts.length, (idx) {
                    final d = kDormCosts[idx];
                    final isSel = idx == _filterDormIndex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(d.name, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          if (val) {
                            setCardState(() => _filterDormIndex = idx);
                            setState(() => _filterDormIndex = idx);
                          }
                        },
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),

              Text(
                "${currentDorm.name}: 월 ${currentDorm.monthlyHousing}만원 (주거비만) · 식비 포함 ${currentDorm.monthlyWithMeals}만원",
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontFeatures: KnueTokens.tabularFigures,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "한 학기 ${(currentDorm.semesterTotalWon / 10000).round()}만원 · ${currentDorm.days}일 기준",
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black45,
                  fontFeatures: KnueTokens.tabularFigures,
                ),
              ),
              if (currentDiff != null) ...[
                const SizedBox(height: 10),
                Text(
                  currentDiff <= 0
                      ? "조건에 맞는 가장 싼 곳이 ${currentDorm.name}보다 월 ${-currentDiff}만원 저렴해요."
                      : "조건에 맞는 가장 싼 곳도 ${currentDorm.name}보다 월 $currentDiff만원 비싸요.",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: currentDiff <= 0
                        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                        : (isDark ? Colors.orangeAccent : Colors.deepOrange),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "자취는 식비가 따로 들고 보증금도 묶여요. 주거비끼리만 견준 값이에요.",
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showHelp(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '자취방 지도 안내',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _line('건물 모양·층수·도로는 VWorld(국토교통부) 실측 공간 데이터입니다.', isDark),
                _line(
                  '우측 하단 나침반과 회전 버튼을 통해 360도 어느 방향에서든 시점을 돌려볼 수 있습니다.',
                  isDark,
                ),
                _line('하단 "목록 보기" 버튼을 누르면 원룸 목록을 시세순·거리순으로 정렬해 볼 수 있습니다.', isDark),
                _line('원하는 원룸의 하트 아이콘을 누르면 "찜한 곳"만 모아볼 수 있습니다.', isDark),
                _line(
                  '건물을 탭하면 정문/도서관 도보 시간, 보증금/월세 시세, 학생들의 실제 거주 후기를 확인하고 직접 제보할 수 있습니다.',
                  isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String t, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '· ',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
        ),
        Expanded(
          child: Text(
            t,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildViewModeToggle(bool isDark, Color themeClr) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _isListView = !_isListView;
          });
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isListView
                    ? Icons.map_rounded
                    : Icons.format_list_bulleted_rounded,
                size: 18,
                color: themeClr,
              ),
              const SizedBox(width: 8),
              Text(
                _isListView ? "지도 보기" : "목록 보기",
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultItem {
  final String name;
  final String subtitle;
  final Color color;
  final BaseBuilding building;
  const _SearchResultItem({
    required this.name,
    required this.subtitle,
    required this.color,
    required this.building,
  });
}

/// 편집 중인 외곽선. 손잡이 사이를 이어 지금 모양을 보여 준다.
class _ShapeOutlinePainter extends CustomPainter {
  final List<Offset> pts;
  final Color color;
  final double width;

  _ShapeOutlinePainter(this.pts, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_ShapeOutlinePainter old) =>
      old.pts != pts || old.width != width || old.color != color;
}
