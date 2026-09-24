import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'constants.dart';
import 'housing_admin_screen.dart';
import 'housing_detail_sheet.dart';
import 'housing_filter_sheet.dart';
import 'housing_iso.dart';
import 'housing_list_view.dart';
import 'housing_model.dart';
import 'housing_service.dart';
import 'ui_utils.dart';

/// 자취방 지도.
///
/// OpenStreetMap 타일을 쓰지 않고 건물을 직접 360도 2.5D 아이소메트릭으로 그린다.
/// 건물 모양·층수·도로는 VWorld(국토교통부) 실측 데이터를 기반으로 로컬 에셋에
/// 내장되어 있어 네트워크 대기 없이 즉각 로드된다.
class HousingScreen extends StatefulWidget {
  const HousingScreen({super.key});

  @override
  State<HousingScreen> createState() => _HousingScreenState();
}

class _HousingScreenState extends State<HousingScreen>
    with SingleTickerProviderStateMixin {
  CampusBase _base = CampusBase.empty;

  /// OSM 도로 중심선(ODbL). 화면 하단에 출처를 표기한다.
  List<OsmRoad> _osmRoads = const [];
  IsoOsmRoads _isoOsmRoads = IsoOsmRoads.empty;
  bool _loading = true;

  double _rotationAngle = 0.0; // radian (0 ~ 2*PI)

  /// 교내 건물에 번호를 찍을지. 지붕 색을 눈으로 검수하라고 켜 둔다.
  /// 우측 HUD의 핀 버튼으로 끈다.
  bool _showBuildingNumbers = true;
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
  Map<String, HousingSummary> _summaries = const {};

  /// 관리자가 바로잡은 건물 정보. 있으면 학생 제보 다수결보다 우선한다.
  Map<String, HousingBuildingOverride> _overrides = const {};

  /// "내 조건 찾기"로 건 조건. 비어 있으면 아무것도 안 거른다.
  HousingFilter _filter = const HousingFilter();

  /// 퀵 필터: 월 35만원 이하
  bool _quickMaxRent35 = false;

  /// 퀵 필터: 원룸/1.5룸만
  bool _quickRoomTypes = false;

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

  /// 조건에 맞는 건물 id. 지도에서 강조하고, 결과 목록의 근거가 된다.
  Set<String> get _matchingBuildingIds {
    if (_filter.isEmpty) return const {};
    return {
      for (final e in _summaries.entries)
        if (housingMatchesFilter(e.value, _filter)) e.key,
    };
  }

  final TransformationController _transformController =
      TransformationController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transformController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 지도 데이터는 tool/fetch_vworld.js로 미리 받아 에셋에 구워둔다.
    // 런타임에 VWorld를 부르지 않는 이유:
    //  - 지도를 열 때마다 네트워크를 기다리지 않는다
    //  - API 키가 앱에 들어가지 않는다
    //  - 쿼터·장애에 영향받지 않는다
    // 데이터를 갱신하려면 VWORLD_KEY=... node tool/fetch_vworld.js 를 다시 돌린다.
    final base = await CampusBase.load();
    final osm = await CampusBase.loadOsmRoads();
    final customBuildings = await HousingService.fetchCustomBuildings();
    final combinedBuildings = [
      ...base.buildings,
      ...customBuildings.where((cb) => !base.buildings.any((b) => b.id == cb.id)),
    ];
    final mergedBase = CampusBase(
      buildings: combinedBuildings,
      roads: base.roads,
      terrain: base.terrain,
      landuse: base.landuse,
    );

    if (!mounted) return;
    setState(() {
      _base = mergedBase;
      _osmRoads = osm;
      _loading = false;
      _rebuild();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMap();
    });

    final results = await Future.wait([
      HousingService.fetchSummaries(),
      HousingService.fetchOverrides(),
      HousingService.fetchFavorites(),
    ]);
    if (!mounted) return;
    setState(() {
      _summaries = results[0] as Map<String, HousingSummary>;
      _overrides = results[1] as Map<String, HousingBuildingOverride>;
      _favoriteIds = results[2] as Set<String>;
      _rebuild();
    });
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
    if (override != null) return override.toOneRoomName();
    final oneRoomId = _summaries[buildingId]?.oneRoomId;
    return oneRoomId == null ? null : kOneRoomNameById[oneRoomId];
  }

  void _centerMap() {
    if (_canvas == Size.zero || _viewportSize == Size.zero) return;

    // 뷰포트 크기에 맞춰 캔버스가 잘리지 않고 전체가 완벽히 들어오도록 스케일 계산
    final fitScale =
        math
            .min(
              _viewportSize.width / _canvas.width,
              _viewportSize.height / _canvas.height,
            )
            .clamp(0.15, 2.5) *
        0.95;

    final tx = (_viewportSize.width - _canvas.width * fitScale) / 2;
    final ty = (_viewportSize.height - _canvas.height * fitScale) / 2;

    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(fitScale);
  }

  void _centerOnTarget() {
    if (_viewportSize == Size.zero) return;
    final proj = IsoProjection(scale: _scale, rotation: _rotationAngle);

    Offset targetPt;
    if (_selectedId != null) {
      final b = _base.buildings.firstWhere(
        (elem) => elem.id == _selectedId,
        orElse: () => _base.buildings.first,
      );
      targetPt = proj.project(b.center.dx, b.center.dy) + _origin;
    } else {
      // 캠퍼스 중심점 (본부-도서관 사이)
      targetPt = proj.project(250, 45) + _origin;
    }

    final currentScale = _transformController.value.getMaxScaleOnAxis().clamp(
      0.4,
      3.5,
    );
    final tx = (_viewportSize.width / 2) - (targetPt.dx * currentScale);
    final ty = (_viewportSize.height * 0.45) - (targetPt.dy * currentScale);

    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(currentScale);
  }

  void _zoomBy(double factor) {
    if (_viewportSize == Size.zero) return;
    final matrix = _transformController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.1, 7.0);
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
    final proj = IsoProjection(scale: _scale, rotation: _rotationAngle);

    // 무엇을 칠하고 어떤 이름표를 달지는 housingMapStyle이 정한다 — 지도
    final matches = Set<String>.from(_matchingBuildingIds);
    if (_onlyFavorites) {
      if (matches.isEmpty) {
        matches.addAll(_favoriteIds);
      } else {
        matches.retainAll(_favoriteIds);
      }
    }

    final style = housingMapStyle(
      _base.buildings,
      summaries: _summaries,
      overrides: _overrides,
      matches: matches,
    );

    _buildings = layoutBuildings(
      _base.buildings,
      proj,
      selectedId: _selectedId,
      oneRoomIds: style.oneRoomIds,
      zoneColors: style.zoneColors,
      displayNames: style.displayNames,
    );
    _roadPaths = projectRoads(_base.roads, proj);
    _isoOsmRoads = projectOsmRoads(_osmRoads, proj);
    _isoTerrain = projectTerrain(_base.terrain, proj);
    _landuse = projectLandUse(_base.landuse, proj);

    final b = boundsOf(_buildings, _roadPaths);
    _origin = Offset(-b.left + 80, -b.top + 80);
    _canvas = Size(b.width + 160, b.height + 160);
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

  void _onTapMap(Offset local) {
    final hit = hitTestBuilding(_buildings, local - _origin);
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

    final proj = IsoProjection(scale: _scale, rotation: _rotationAngle);
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

  void _focusZone(HousingZone? zone) {
    setState(() {
      _selectedZone = zone;
      _rebuild();
    });

    if (zone == null) {
      _centerMap();
      return;
    }

    final proj = IsoProjection(scale: _scale, rotation: _rotationAngle);
    final zoneBuildings = <BaseBuilding>[];
    for (final b in _base.buildings) {
      final s = _summaries[b.id];
      if (s != null && s.oneRoomId != null) {
        final known = kOneRoomNameById[s.oneRoomId];
        if (known != null && known.zone == zone) {
          zoneBuildings.add(b);
        }
      }
    }

    if (zoneBuildings.isNotEmpty) {
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      for (final b in zoneBuildings) {
        final pt = proj.project(b.center.dx, b.center.dy) + _origin;
        if (pt.dx < minX) minX = pt.dx;
        if (pt.dx > maxX) maxX = pt.dx;
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dy > maxY) maxY = pt.dy;
      }
      final cx = (minX + maxX) / 2;
      final cy = (minY + maxY) / 2;
      final size = MediaQuery.of(context).size;
      const targetScale = 1.35;
      final tx = (size.width / 2) - (cx * targetScale);
      final ty = (size.height * 0.35) - (cy * targetScale);

      _transformController.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(targetScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
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
          body: _loading
              ? const Center(child: CircularProgressIndicator())
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
                                    buildings: _base.buildings,
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
                            top: 10,
                            left: 12,
                            right: 12,
                            child: _buildSearchBar(isDark),
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

                          // 지도/목록 모드 전환 플로팅 토글 버튼 (하단 중앙)
                          if (_isListView || _peekBuilding == null)
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
                const Expanded(
                  child: Text(
                    "🛠️ 개발자 모드 ON: 지도의 건물을 탭해 이름·색상·정보를 수정하거나 상단 [+]로 건물을 추가하세요.",
                    style: TextStyle(
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
        return Container(
          width: double.infinity,
          color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.construction_rounded, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "자취방 구하기는 지속적으로 개발 중이에요. 건물 정보가 정확하지 않을 수 있어요",
                  style: TextStyle(color: Colors.blue, fontSize: 13),
                ),
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
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: const InputDecoration(
                    hintText: "원룸 이름 검색 (예: 다솜빌, 해오름, 대현)",
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
                    setState(() => _searchQuery = '');
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

        // 검색 결과 드롭다운
        if (_searchQuery.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                ),
              ],
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
                  title: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _focusBuilding(item.building);
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
              if (_hasActiveFilters) _buildResetFilterChip(isDark),
              _buildZoneChip('전체', null, isDark),
              _buildFavoriteChip(isDark),
              _buildQuickFilterChip('월 35 이하', _quickMaxRent35, isDark, onTap: _toggleQuickMaxRent35),
              _buildQuickFilterChip('원룸/1.5룸', _quickRoomTypes, isDark, onTap: _toggleQuickRoomTypes),
              ...HousingZone.values.map(
                (z) => _buildZoneChip(z.label, z, isDark, dotColor: z.color),
              ),
            ],
          ),
        ),
      ],
    );
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

  List<_SearchResultItem> _getMatchingSearchResults() {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    final results = <_SearchResultItem>[];

    // 1. 교원대 캠퍼스 건물 검색
    for (final b in _base.buildings.where((elem) => elem.isCampus)) {
      final name = b.officialName ?? b.id;
      if (name.toLowerCase().contains(q)) {
        results.add(
          _SearchResultItem(
            name: name,
            subtitle: '교원대 캠퍼스 · 지상 ${b.floors}층',
            color: const Color(0xFF3F51B5),
            building: b,
          ),
        );
      }
    }

    // 2. 원룸 검색
    for (final item in kOneRoomNames) {
      if (item.name.toLowerCase().contains(q)) {
        final b = _base.buildings.firstWhere(
          (elem) => _summaries[elem.id]?.oneRoomId == item.id,
          orElse: () => _base.buildings.firstWhere(
            (elem) => !elem.isCampus,
            orElse: () => _base.buildings.first,
          ),
        );
        results.add(
          _SearchResultItem(
            name: item.name,
            subtitle: '${item.zone.label} · ${item.builtYear ?? 0}년 준공',
            color: item.zone.color,
            building: b,
          ),
        );
      }
    }

    // 3. 관리자가 덮어쓴 이름 검색 — kOneRoomNames에 없는 새 이름도 찾을 수 있게.
    final alreadyMatched = results.map((r) => r.building.id).toSet();
    for (final entry in _overrides.entries) {
      if (alreadyMatched.contains(entry.key)) continue;
      final o = entry.value;
      if (!o.name.toLowerCase().contains(q)) continue;
      BaseBuilding? b;
      for (final elem in _base.buildings) {
        if (elem.id == entry.key) {
          b = elem;
          break;
        }
      }
      if (b == null) continue;
      results.add(
        _SearchResultItem(
          name: o.name,
          subtitle: '${o.zone.label} · ${o.builtYear ?? 0}년 준공',
          color: o.zone.color,
          building: b,
        ),
      );
    }

    return results.take(8).toList();
  }

  Widget _buildZoneChip(
    String label,
    HousingZone? zone,
    bool isDark, {
    Color? dotColor,
  }) {
    final isSelected = _selectedZone == zone;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          _focusZone(isSelected ? null : zone);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? (dotColor ?? const Color(0xFF007AFF))
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
              if (dotColor != null && !isSelected) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
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

  Widget _buildRotationControls(bool isDark, Color themeClr) {
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
          _hudIconButton(
            icon: Icons.rotate_right_rounded,
            tooltip: "45° 시점 회전",
            onTap: () => _rotateBy(math.pi / 4),
            isDark: isDark,
          ),
          const SizedBox(height: 4),

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

          // 건물 번호 토글
          _hudIconButton(
            icon: _showBuildingNumbers ? Icons.pin_drop_rounded : Icons.pin_drop_outlined,
            tooltip: _showBuildingNumbers ? "건물 번호 끄기" : "건물 번호 켜기",
            onTap: () =>
                setState(() => _showBuildingNumbers = !_showBuildingNumbers),
            isDark: isDark,
          ),
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
    final distGate = walkingDistanceMeters(b.center, CampusLandmark.mainGate);
    final distLib = walkingDistanceMeters(b.center, CampusLandmark.library);
    final monthly = s.medianMonthlyTotal ?? s.medianRent;

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
                    if (known != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: known.zone.color.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: known.zone.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              known.zone.label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: known.zone.color,
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
                        if (s.medianDeposit != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '보증금 ${s.medianDeposit}만',
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

                // 하단: 도보 시간 뱃지 & 상세보기
                Row(
                  children: [
                    if (!b.isCampus) ...[
                      _peekBadge(
                        Icons.directions_walk_rounded,
                        '정문 ${walkingMinutes(distGate)}분',
                        isDark ? Colors.blueAccent : Colors.blue.shade700,
                        isDark,
                      ),
                      const SizedBox(width: 6),
                      _peekBadge(
                        Icons.menu_book_rounded,
                        '도서관 ${walkingMinutes(distLib)}분',
                        isDark ? Colors.purpleAccent : Colors.purple.shade700,
                        isDark,
                      ),
                    ] else ...[
                      _peekBadge(
                        Icons.school_rounded,
                        '캠퍼스 시설 · 지상 ${b.floors}층',
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
                        showToast(context, "비밀번호가 일치하지 않습니다.");
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

  void _openEditBuildingSheet(BaseBuilding b, bool isDark, Color themeClr) {
    final existing = _overrides[b.id];
    final known = _resolvedKnown(b.id);
    final nameCtrl = TextEditingController(text: existing?.name ?? known?.name ?? b.officialName ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? b.addressLabel);
    final phoneCtrl = TextEditingController(text: existing?.landlordPhone ?? '');
    final floorCtrl = TextEditingController(text: (existing?.floors ?? b.floors).toString());
    final yearCtrl = TextEditingController(text: (existing?.builtYear ?? known?.builtYear ?? '').toString());
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    HousingZone selectedZone = existing?.zone ?? known?.zone ?? HousingZone.values.first;
    Color? selectedColor = existing?.customColor;

    final colorPresets = const [
      Color(0xFF03C75A), // 네이버 그린
      Color(0xFF2196F3), // 블루
      Color(0xFFFFA000), // 앰버
      Color(0xFF9C27B0), // 퍼플
      Color(0xFFFF5722), // 딥오렌지
      Color(0xFF009688), // 틸/에메랄드
      Color(0xFFE91E63), // 핑크
      Color(0xFF607D8B), // 블루그레이
      Color(0xFF3F51B5), // 인디고
      Color(0xFF795548), // 브라운
      Color(0xFF424242), // 다크 차콜
    ];

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
                      onTap: () => setSheetState(() => selectedColor = null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selectedColor == null
                              ? const Color(0xFF03C75A).withValues(alpha: 0.15)
                              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedColor == null ? const Color(0xFF03C75A) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          "기본 색상",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selectedColor == null ? FontWeight.bold : FontWeight.normal,
                            color: selectedColor == null ? const Color(0xFF03C75A) : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                    ...colorPresets.map((clr) {
                      final isSel = selectedColor != null && selectedColor!.value == clr.value;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = clr),
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
                          child: isSel ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
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
                          await HousingService.deleteCustomBuilding(b.id);
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          setState(() {
                            _base.buildings.removeWhere((elem) => elem.id == b.id);
                            _overrides.remove(b.id);
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
                          final colorHex = selectedColor != null
                              ? '#${selectedColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}'
                              : null;
                          final override = HousingBuildingOverride(
                            buildingId: b.id,
                            name: name,
                            zone: selectedZone,
                            address: addrCtrl.text.trim().isNotEmpty ? addrCtrl.text.trim() : null,
                            landlordPhone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                            floors: int.tryParse(floorCtrl.text.trim()) ?? b.floors,
                            builtYear: int.tryParse(yearCtrl.text.trim()),
                            note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                            customColorHex: colorHex,
                          );

                          await HousingService.setOverride(override);
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          setState(() {
                            _overrides[b.id] = override;
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

    final colorPresets = const [
      Color(0xFF03C75A),
      Color(0xFF2196F3),
      Color(0xFFFFA000),
      Color(0xFF9C27B0),
      Color(0xFFFF5722),
      Color(0xFF009688),
      Color(0xFFE91E63),
      Color(0xFF607D8B),
    ];

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
                        child: isSel ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
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

                await HousingService.saveCustomBuilding(building: newBuilding, override: override);
                if (!mounted) return;
                Navigator.pop(ctx);
                setState(() {
                  _base.buildings.add(newBuilding);
                  _overrides[newId] = override;
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
        if (_viewportSize != newViewport) {
          final isFirstLayout = _viewportSize == Size.zero;
          _viewportSize = newViewport;
          if (isFirstLayout) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerMap();
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
    return InteractiveViewer(
      transformationController: _transformController,
      constrained: false,
      minScale: 0.05,
      maxScale: 8.0,
      boundaryMargin: const EdgeInsets.all(4000),
      clipBehavior: Clip.hardEdge,
      child: GestureDetector(
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
            showBuildingNumbers: _showBuildingNumbers,
            // 이름표를 화면 고정 크기로 그리려면 지금 배율을 알아야 한다.
            view: _transformController,
          ),
        ),
      ),
    );
  }



  void _showDetail(BaseBuilding b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HousingDetailSheet(
        building: b,
        summary: _summaries[b.id] ?? HousingSummary.empty,
        known: _resolvedKnown(b.id),
        edited: _overrides[b.id],
        isDark: isDark,
        isFavorite: _favoriteIds.contains(b.id),
        onToggleFavorite: () => _toggleFavorite(b.id),
        onReported: () async {
          final s = await HousingService.fetchSummaries();
          if (!mounted) return;
          setState(() {
            _summaries = s;
            _rebuild();
          });
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
            _summaries.values.where((s) => housingMatchesFilter(s, f)).length,
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
    final matches = _matchingBuildingIds;
    final rows =
        <({String name, HousingSummary summary, BaseBuilding building})>[];
    for (final b in _base.buildings) {
      if (!matches.contains(b.id)) continue;
      final s = _summaries[b.id];
      if (s == null) continue;
      rows.add((
        name: _resolvedKnown(b.id)?.name ?? b.officialName ?? '이름 미확인 건물',
        summary: s,
        building: b,
      ));
    }
    // 월 부담이 싼 순. 같으면 보증금이 싼 순.
    rows.sort((a, b) {
      final am = a.summary.medianMonthlyTotal ?? 1 << 30;
      final bm = b.summary.medianMonthlyTotal ?? 1 << 30;
      if (am != bm) return am.compareTo(bm);
      return (a.summary.medianDeposit ?? 1 << 30).compareTo(
        b.summary.medianDeposit ?? 1 << 30,
      );
    });

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
                      "조건에 맞는 원룸 ${rows.length}곳",
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
                "제보가 있는 건물만 비교할 수 있어요. 시세는 제보 중앙값이에요.",
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              const SizedBox(height: 14),
              _buildDormComparison(rows.map((r) => r.summary).toList(), isDark),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    "조건에 맞는 곳이 없어요.\n금액을 조금 올리거나 조건을 줄여보세요.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                )
              else
                ...rows.map(
                  (r) => _buildFilterResultRow(
                    r.name,
                    r.summary,
                    r.building,
                    isDark,
                    sheetCtx,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterResultRow(
    String name,
    HousingSummary s,
    BaseBuilding building,
    bool isDark,
    BuildContext sheetCtx,
  ) {
    final monthly = s.medianMonthlyTotal;
    final known = _resolvedKnown(building.id);
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
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: known?.zone.color ?? Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (s.roomTypes.isNotEmpty)
                        s.roomTypes.map((t) => t.label).join('/'),
                      "제보 ${s.reportCount}건",
                      if (s.isThin) "참고용",
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  monthly == null ? "-" : "월 $monthly만원",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
                Text(
                  s.medianDeposit == null ? "" : "보증금 ${s.medianDeposit}만원",
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black45,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _filterDormIndex = 0;

  /// 기숙사와의 비교 카드. 자취는 식비가 따로 나가므로 **주거비끼리** 견준다.
  Widget _buildDormComparison(List<HousingSummary> matched, bool isDark) {
    final monthlies =
        matched.map((s) => s.medianMonthlyTotal).whereType<int>().toList()
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
