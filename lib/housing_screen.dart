import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'constants.dart';
import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_service.dart';
import 'ui_utils.dart';
import 'geo_utils.dart';
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
  /// 원룸으로 볼 만한 건물의 최소 조건 (3층 이상, 면적 50㎡ 이상)
  static const _minFloors = 3;
  static const _minArea = 50.0;

  CampusBase _base = CampusBase.empty;
  bool _loading = true;

  double _rotationAngle = 0.0; // radian (0 ~ 2*PI)

  /// 교내 건물에 번호를 찍을지. 지붕 색을 눈으로 검수하라고 켜 둔다.
  /// 우측 HUD의 핀 버튼으로 끈다.
  bool _showBuildingNumbers = true;
  double _scale = 2.2;

  List<IsoBuilding> _buildings = const [];
  CombinedRoads _roadPaths = CombinedRoads.empty;
  IsoTerrain _isoTerrain = IsoTerrain.empty;
  IsoLandUse _landuse = IsoLandUse.empty;
  Offset _origin = Offset.zero;
  Size _canvas = Size.zero;
  Size _viewportSize = Size.zero;

  String? _selectedId;
  HousingZone? _selectedZone;
  String _searchQuery = '';
  Map<String, HousingSummary> _summaries = const {};

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
    if (!mounted) return;
    setState(() {
      _base = base;
      _loading = false;
      _rebuild();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMap();
    });

    final s = await HousingService.fetchSummaries();
    if (!mounted) return;
    setState(() {
      _summaries = s;
      _rebuild();
    });
  }

  void _centerMap() {
    if (_canvas == Size.zero || _viewportSize == Size.zero) return;

    // 뷰포트 크기에 맞춰 캔버스가 잘리지 않고 전체가 완벽히 들어오도록 스케일 계산
    final fitScale = math.min(
      _viewportSize.width / _canvas.width,
      _viewportSize.height / _canvas.height,
    ).clamp(0.15, 2.5) * 0.95;

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

    final currentScale = _transformController.value.getMaxScaleOnAxis().clamp(0.4, 3.5);
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
    final tx = center.dx - (center.dx - matrix.getTranslation().x) * scaleChange;
    final ty = center.dy - (center.dy - matrix.getTranslation().y) * scaleChange;

    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale);
  }

  bool _looksLikeOneRoom(BaseBuilding b) =>
      // 교내 건물은 층수·면적이 원룸 조건에 걸려도 원룸일 리 없다.
      // (실제 층수를 넣고 나서 다정관·호연관 같은 동이 여기 걸리기 시작했다)
      !b.isCampus &&
      (_summaries.containsKey(b.id) ||
          (b.floors >= _minFloors && b.footprintArea >= _minArea));

  void _rebuild() {
    final proj = IsoProjection(scale: _scale, rotation: _rotationAngle);

    final oneRoomIds = <String>{};
    final zoneColors = <String, Color>{};
    final displayNames = <String, String>{};

    for (final b in _base.buildings) {
      if (_looksLikeOneRoom(b)) {
        oneRoomIds.add(b.id);
      }

      final s = _summaries[b.id];
      if (s != null && s.oneRoomId != null) {
        final known = kOneRoomNameById[s.oneRoomId];
        if (known != null) {
          zoneColors[b.id] = known.zone.color;
          displayNames[b.id] = known.name;
        }
      }
    }

    final selectedZoneBuildings = <String>{};
    if (_selectedZone != null) {
      for (final b in _base.buildings) {
        final s = _summaries[b.id];
        if (s != null && s.oneRoomId != null) {
          final known = kOneRoomNameById[s.oneRoomId];
          if (known != null && known.zone == _selectedZone) {
            selectedZoneBuildings.add(b.id);
          }
        }
      }
    }

    _buildings = layoutBuildings(
      _base.buildings,
      proj,
      selectedId: _selectedId,
      oneRoomIds: oneRoomIds,
      zoneColors: zoneColors,
      displayNames: displayNames,
    );
    _roadPaths = projectRoads(_base.roads, proj);
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
    if (hit == null) return;
    _focusBuilding(hit, openDetail: true);
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
            flexibleSpace:
                AppleAppBarFlexibleSpace(themeColor: color, isDark: isDark),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                onPressed: () => _showHelp(isDark),
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: "지도 안내",
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    // 메인 지도
                    Positioned.fill(
                      child: Column(
                        children: [
                          Expanded(child: _buildMap(isDark)),
                          _buildFooter(isDark),
                        ],
                      ),
                    ),

                    // 상단 검색 & 구역 필터 바
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: _buildSearchBar(isDark),
                    ),

                    // 360도 회전 나침반 & 방위각 컨트롤러 HUD (우측 하단)
                    Positioned(
                      bottom: 42,
                      right: 14,
                      child: _buildRotationControls(isDark, color),
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
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  size: 20, color: isDark ? Colors.white60 : Colors.black45),
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
                  child: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
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
                  title: Text(item.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(item.subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54)),
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
              _buildZoneChip('전체', null, isDark),
              ...HousingZone.values.map(
                (z) => _buildZoneChip(z.label, z, isDark, dotColor: z.color),
              ),
            ],
          ),
        ),
      ],
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
        results.add(_SearchResultItem(
          name: name,
          subtitle: '교원대 캠퍼스 · 지상 ${b.floors}층',
          color: const Color(0xFF3F51B5),
          building: b,
        ));
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
        results.add(_SearchResultItem(
          name: item.name,
          subtitle: '${item.zone.label} · ${item.builtYear ?? 0}년 준공',
          color: item.zone.color,
          building: b,
        ));
      }
    }

    return results.take(8).toList();
  }

  Widget _buildZoneChip(String label, HousingZone? zone, bool isDark,
      {Color? dotColor}) {
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: -_rotationAngle,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.navigation_rounded,
                            size: 18, color: Color(0xFFFF3B30)),
                        Text(
                          '$deg°',
                          style: TextStyle(
                            fontSize: 7.5,
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
          const SizedBox(height: 8),

          // 회전 시계방향 / 반시계방향 버튼
          _hudIconButton(
            icon: Icons.rotate_left_rounded,
            tooltip: "시점 왼쪽으로 45° 회전",
            onTap: () => _rotateBy(-math.pi / 4),
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _hudIconButton(
            icon: Icons.rotate_right_rounded,
            tooltip: "시점 오른쪽으로 45° 회전",
            onTap: () => _rotateBy(math.pi / 4),
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _hudIconButton(
            icon: Icons.add_rounded,
            tooltip: "확대",
            onTap: () => _zoomBy(1.3),
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _hudIconButton(
            icon: Icons.remove_rounded,
            tooltip: "축소",
            onTap: () => _zoomBy(0.77),
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _hudIconButton(
            icon: Icons.my_location_rounded,
            tooltip: "중심으로 맞춤",
            onTap: _centerMap,
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _hudIconButton(
            icon: _showBuildingNumbers
                ? Icons.pin_rounded
                : Icons.pin_outlined,
            tooltip: _showBuildingNumbers ? "건물 번호 끄기" : "건물 번호 켜기",
            onTap: () =>
                setState(() => _showBuildingNumbers = !_showBuildingNumbers),
            isDark: isDark,
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
          child: Icon(icon,
              size: 18, color: isDark ? Colors.white70 : Colors.black87),
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
          child: InteractiveViewer(
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
                  showBuildingNumbers: _showBuildingNumbers,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(bool isDark) {
    final named = _summaries.values.where((s) => s.oneRoomId != null).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: isDark ? const Color(0xFF161618) : Colors.white,
      child: Text(
        '건물 ${_base.buildings.length}동 · 확인된 원룸 $named동 · '
        '나침반과 회전 버튼으로 360° 시점 회전 가능',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white38 : Colors.black38,
          fontFeatures: KnueTokens.tabularFigures,
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
      builder: (_) => _DetailSheet(
        building: b,
        summary: _summaries[b.id] ?? HousingSummary.empty,
        isDark: isDark,
        onReported: () async {
          final s = await HousingService.fetchSummaries();
          if (!mounted) return;
          setState(() {
            _summaries = s;
            _rebuild();
          });
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _selectedId = null;
        _rebuild();
      });
    });
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
                Text('자취방 지도 안내',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
                const SizedBox(height: 12),
                _line('건물 모양·층수·도로는 VWorld(국토교통부) 실측 공간 데이터입니다.', isDark),
                _line('우측 하단 나침반과 회전 버튼을 통해 360도 어느 방향에서든 시점을 돌려볼 수 있습니다.', isDark),
                _line('상단 검색창과 구역 칩을 누르면 원하는 원룸으로 즉시 이동합니다.', isDark),
                _line('건물을 탭하면 층수, 준공연도, 보증금/월세 시세(중앙값)를 확인하고 직접 제보할 수 있습니다.', isDark),
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
            Text('· ',
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            Expanded(
              child: Text(t,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: isDark ? Colors.white70 : Colors.black87,
                  )),
            ),
          ],
        ),
      );
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

// ═══════════════════════════════════════════════════════════════════════
// 건물 상세 바텀시트
// ═══════════════════════════════════════════════════════════════════════

class _DetailSheet extends StatefulWidget {
  final BaseBuilding building;
  final HousingSummary summary;
  final bool isDark;
  final Future<void> Function() onReported;

  const _DetailSheet({
    required this.building,
    required this.summary,
    required this.isDark,
    required this.onReported,
  });

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _already = false;

  @override
  void initState() {
    super.initState();
    HousingService.hasReported(widget.building.id).then((v) {
      if (mounted) setState(() => _already = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final b = widget.building;
    final s = widget.summary;
    final known = s.oneRoomId == null ? null : kOneRoomNameById[s.oneRoomId];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      known?.name ?? b.officialName ?? '이름 미확인 건물',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  if (b.isCampus)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F51B5).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF3F51B5).withValues(alpha: 0.4),
                            width: 0.8),
                      ),
                      child: const Text(
                        '교원대 캠퍼스',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3F51B5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  b.addressLabel,
                  '지상 ${b.floors}층',
                  if (known?.builtYear != null) '${known!.builtYear}년 준공',
                  if (known?.note != null) known!.note!,
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontFeatures: KnueTokens.tabularFigures,
                ),
              ),
              if (known != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: known.zone.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      known.zone.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: known.zone.color,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              if (!b.isCampus) ...[
                _priceBlock(s, isDark),
                if (s.topFeatures.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: s.topFeatures
                        .map((f) => Chip(
                              label: Text(f,
                                  style: const TextStyle(fontSize: 11.5)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _already ? null : _openForm,
                    icon: Icon(
                      _already
                          ? Icons.check_rounded
                          : Icons.add_comment_outlined,
                      size: 18,
                    ),
                    label: Text(_already
                        ? '이미 제보함'
                        : known == null
                            ? '이 건물 이름·시세 알려주기'
                            : '내가 아는 시세 알려주기'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school_rounded,
                          size: 20, color: Color(0xFF3F51B5)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '한국교원대학교 교육·행정 및 학생 편의 시설입니다.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceBlock(HousingSummary s, bool isDark) {
    if (!s.hasData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.help_outline_rounded,
                size: 26, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 8),
            Text('아직 제보가 없어요',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black54,
                )),
            const SizedBox(height: 3),
            Text('살아봤다면 아래에서 알려주세요',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white38 : Colors.black38,
                )),
          ],
        ),
      );
    }

    final d = s.medianDeposit;
    final m = s.medianRent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _priceItem('보증금', d == null ? '-' : '$d만원', isDark),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          _priceItem('월세', m == null ? '-' : '$m만원', isDark),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          _priceItem('제보', '${s.reportCount}건', isDark),
        ],
      ),
    );
  }

  Widget _priceItem(String label, String value, bool isDark) => Column(
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white54 : Colors.black54,
              )),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
                fontFeatures: KnueTokens.tabularFigures,
              )),
        ],
      );

  void _openForm() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReportSheet(
        building: widget.building,
        isDark: widget.isDark,
        onSubmitted: () async {
          setState(() => _already = true);
          await widget.onReported();
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 제보 입력 폼 바텀시트
// ═══════════════════════════════════════════════════════════════════════

class _ReportSheet extends StatefulWidget {
  final BaseBuilding building;
  final bool isDark;
  final Future<void> Function() onSubmitted;

  const _ReportSheet({
    required this.building,
    required this.isDark,
    required this.onSubmitted,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _form = GlobalKey<FormState>();
  final _deposit = TextEditingController();
  final _rent = TextEditingController();
  final _fee = TextEditingController();
  String? _selectedOneRoomId;
  final Set<String> _features = {};
  bool _submitting = false;

  static const _featureOptions = [
    '풀옵션',
    '엘리베이터',
    '주차 가능',
    '베란다',
    '복층',
    '심야전기',
    '도시가스',
    '햇빛 잘 듦',
    '방음 양호',
    '벌레 적음',
  ];

  @override
  void dispose() {
    _deposit.dispose();
    _rent.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final report = HousingReport(
        buildingId: widget.building.id,
        deposit: int.parse(_deposit.text.trim()),
        monthlyRent: int.parse(_rent.text.trim()),
        maintenanceFee: _fee.text.trim().isEmpty
            ? null
            : int.tryParse(_fee.text.trim()),
        features: _features.toList(),
        oneRoomId: _selectedOneRoomId,
        reportedAt: DateTime.now(),
      );
      await HousingService.submit(report);
      if (!mounted) return;
      Navigator.pop(context); // 폼 닫기
      await widget.onSubmitted();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제보가 등록되었습니다. 감사합니다!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제보 등록에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('원룸 이름·시세 제보',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      )),
                  const SizedBox(height: 14),

                  // 이름 선택
                  DropdownButtonFormField<String>(
                    value: _selectedOneRoomId,
                    decoration: const InputDecoration(
                      labelText: '원룸 이름 (알고 있다면)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('목록에 없음 / 모름'),
                      ),
                      ...kOneRoomNames.map((r) => DropdownMenuItem(
                            value: r.id,
                            child: Text('${r.name} (${r.zone.label})'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedOneRoomId = v),
                  ),
                  const SizedBox(height: 12),

                  // 보증금 / 월세
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _deposit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '보증금 (만원)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return '입력 필요';
                            if (int.tryParse(v.trim()) == null) return '숫자만';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _rent,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '월세 (만원)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return '입력 필요';
                            if (int.tryParse(v.trim()) == null) return '숫자만';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 관리비
                  TextFormField(
                    controller: _fee,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '관리비 (만원, 선택)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 특징 선택 태그
                  Text('특징 (선택)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      )),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _featureOptions.map((f) {
                      final selected = _features.contains(f);
                      return FilterChip(
                        label: Text(f, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _features.add(f);
                            } else {
                              _features.remove(f);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // 제출 버튼
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('제보하기',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
