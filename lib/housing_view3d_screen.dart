import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'housing_iso.dart';
import 'housing_view3d.dart';

/// 둘러보기가 그리는 범위(m). 캡처로 뜬 지도 본체에 여백을 조금 둔 것이다.
/// 이 밖은 건물도 드물고, 땅 그림을 키우면 메모리만 먹는다.
const Rect kView3World = Rect.fromLTRB(-620, -860, 1160, 800);

/// 땅 그림 해상도(미터당 픽셀). 1.5면 2670×2490(약 27MB). 2로 올리면 47MB라
/// 메모리가 적은 폰에서 위험하다.
const double kView3GroundPpm = 1.5;

/// 위에서 본 지도(건물 없이 바닥·도로만)를 그림 한 장으로 굽는다. 이 그림을
/// 언덕 격자에 입힌다. 앱의 지도 painter를 그대로 쓰므로 색·도로가 지도와 같다.
Future<ui.Image> renderView3Ground({
  required CampusBase base,
  required List<OsmRoad> osmRoads,
  required bool isDark,
  Rect world = kView3World,
  double ppm = kView3GroundPpm,
}) {
  // 평면 시점은 1m가 0.7071×scale 픽셀이다(IsoProjection).
  final proj = IsoProjection(scale: ppm / 0.7071, topDown: true);
  final size = Size(world.width * ppm, world.height * ppm);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Offset.zero & size, Paint()..color = mapBackgroundColor(isDark));
  HousingMapPainter(
    layer: HousingMapLayer.base,
    windowsVisible: false,
    buildings: const [],
    roads: projectRoads(base.roads, proj),
    terrain: projectTerrain(base.terrain, proj),
    landuse: projectLandUse(base.landuse, proj),
    osmRoads: projectOsmRoads(osmRoads, proj),
    isDark: isDark,
    origin: -proj.project(world.left, world.top),
    projection: proj,
  ).paint(canvas, size);
  return rec.endRecording().toImage(size.width.round(), size.height.round());
}

/// 지도에 그려진 건물을 둘러보기용으로 옮긴다(색·이름은 지도 그대로).
List<View3BuildingSpec> view3SpecsFrom(List<IsoBuilding> buildings, bool isDark) => [
      for (final b in buildings)
        View3BuildingSpec(
          building: b.building,
          color: view3RoofColor(b, isDark),
          tinted: b.highlighted || b.zoneColor != null,
          name: b.displayName,
          highlighted: b.highlighted,
        ),
    ];

/// 3D 둘러보기. 손가락으로 옮기고·돌리고·확대하고·기울인다.
class HousingView3DScreen extends StatefulWidget {
  final CampusBase base;
  final List<OsmRoad> osmRoads;
  final List<View3BuildingSpec> buildings;

  /// 처음 바라볼 곳(월드 좌표)과 방향(북쪽에서 시계 방향, 라디안).
  final Offset start;
  final double azimuth;

  /// 테스트용: 땅 그림을 굽지 않는다(테스트의 가짜 시간에서는 안 끝난다).
  final bool renderGround;

  const HousingView3DScreen({
    super.key,
    required this.base,
    required this.osmRoads,
    required this.buildings,
    required this.start,
    this.azimuth = 0,
    this.renderGround = true,
  });

  @override
  State<HousingView3DScreen> createState() => _HousingView3DScreenState();
}

class _HousingView3DScreenState extends State<HousingView3DScreen> {
  /// 실측 높이를 읽은 뒤에 만든다([_loadScene]).
  View3Scene? _sceneOrNull;
  View3Scene get _scene => _sceneOrNull!;
  final ValueNotifier<View3Camera> _camera = ValueNotifier(
    const View3Camera(x: 0, y: 0, z: 100, yaw: 0, pitch: -0.6),
  );

  ui.Image? _ground;
  bool? _groundDark;

  late Offset _target = _clampToWorld(widget.start);
  double _distance = 420;
  late double _azimuth = widget.azimuth;
  double _tilt = 38 * math.pi / 180;

  // 두 손가락 제스처의 직전 값(ScaleUpdateDetails는 시작부터의 누적값이다).
  double _lastScale = 1;
  double _lastRotation = 0;

  @override
  void initState() {
    super.initState();
    _loadScene();
  }

  /// 실제 땅 높이를 읽어 장면을 만든다. 못 읽으면 지도의 손 모델로 그린다
  /// (언덕이 실제와 다를 뿐 화면은 뜬다).
  Future<void> _loadScene() async {
    CampusDem? dem;
    try {
      dem = await CampusDem.load();
    } catch (e) {
      debugPrint('campus_dem.json 로드 실패: $e');
    }
    if (!mounted) return;
    setState(() {
      _sceneOrNull = View3Scene.build(
        world: kView3World,
        buildings: widget.buildings,
        roads: widget.osmRoads,
        elevation: dem?.exaggerated,
      );
    });
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.renderGround && _groundDark != isDark) {
      _groundDark = isDark;
      _bakeGround(isDark);
    }
  }

  Future<void> _bakeGround(bool isDark) async {
    try {
      final image = await renderView3Ground(
        base: widget.base,
        osmRoads: widget.osmRoads,
        isDark: isDark,
      );
      if (!mounted || _groundDark != isDark) {
        image.dispose();
        return;
      }
      final old = _ground;
      setState(() => _ground = image);
      old?.dispose();
    } catch (e) {
      // 그림을 못 구워도 맨땅 색으로는 그려진다.
      debugPrint('둘러보기 땅 그림 실패: $e');
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _ground?.dispose();
    super.dispose();
  }

  Offset _clampToWorld(Offset p) => Offset(
        p.dx.clamp(kView3World.left + 20, kView3World.right - 20),
        p.dy.clamp(kView3World.top + 20, kView3World.bottom - 20),
      );

  View3Camera _orbitCamera() => View3Camera.orbit(
        target: _target,
        targetZ: _scene.groundAt(_target.dx, _target.dy),
        distance: _distance,
        azimuth: _azimuth,
        tilt: _tilt,
      );

  void _sync() {
    if (_sceneOrNull == null) return;
    _camera.value = _orbitCamera();
  }

  // ── 제스처 ──

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
    _lastRotation = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_sceneOrNull == null) return;
    final cam = _camera.value;
    if (d.pointerCount >= 2) {
      // 비틀면 돌고, 벌리면 다가가고, 두 손가락을 위아래로 밀면 기운다.
      _azimuth -= d.rotation - _lastRotation;
      _lastRotation = d.rotation;
      if (d.scale > 0) {
        _distance = (_distance * _lastScale / d.scale).clamp(40.0, 2600.0);
        _lastScale = d.scale;
      }
      _tilt = (_tilt + d.focalPointDelta.dy * 0.25 * math.pi / 180)
          .clamp(12 * math.pi / 180, 88 * math.pi / 180);
    } else {
      // 한 손가락: 땅을 잡고 끄는 것처럼 옮긴다.
      final focal = (size.height / 2) / math.tan(30 * math.pi / 180);
      final mpp = _distance / focal;
      final along = d.focalPointDelta.dy * mpp / math.max(math.sin(_tilt), 0.35);
      _target = _clampToWorld(
        _target - cam.rightH * (d.focalPointDelta.dx * mpp) + cam.forwardH * along,
      );
    }
    _sync();
  }

  void _zoomBy(double factor) {
    _distance = (_distance * factor).clamp(40.0, 2600.0);
    _sync();
  }

  void _faceNorth() {
    _azimuth = 0;
    _sync();
  }

  // ── 화면 ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scene = _sceneOrNull;
    final chip = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.94);
    final fg = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: view3Backdrop(isDark).farGround,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (d) => _onScaleUpdate(d, size),
                  child: scene == null
                      ? const Center(child: CircularProgressIndicator())
                      : RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: View3Painter(
                        scene: scene,
                        camera: _camera,
                        ground: _ground,
                        isDark: isDark,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 닫기 · 나침반
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _roundButton(
                    icon: Icons.close_rounded,
                    tooltip: '지도로 돌아가기',
                    bg: chip,
                    fg: fg,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<View3Camera>(
                    valueListenable: _camera,
                    builder: (_, cam, _) => _roundButton(
                      tooltip: '북쪽 보기',
                      bg: chip,
                      fg: fg,
                      onTap: _faceNorth,
                      child: Transform.rotate(
                        angle: -cam.yaw,
                        child: const Icon(
                          Icons.navigation_rounded,
                          size: 20,
                          color: Color(0xFFFF3B30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 확대·축소
          Positioned(
              right: 12,
              bottom: 96,
              child: SafeArea(
                child: Column(
                  children: [
                    _roundButton(
                      icon: Icons.add_rounded,
                      tooltip: '확대',
                      bg: chip,
                      fg: fg,
                      onTap: () => _zoomBy(0.75),
                    ),
                    const SizedBox(height: 8),
                    _roundButton(
                      icon: Icons.remove_rounded,
                      tooltip: '축소',
                      bg: chip,
                      fg: fg,
                      onTap: () => _zoomBy(1.33),
                    ),
                  ],
                ),
              ),
            ),

          // 조작 안내
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: chip.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '한 손가락: 이동 · 두 손가락: 회전·확대·기울이기',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.8)),
                  ),
                ),
              ),
            ),
          ),

          // 도로는 OpenStreetMap 데이터(ODbL) — 출처 표기는 라이선스 조건이다.
          Positioned(
            right: 6,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
  }

  Widget _roundButton({
    IconData? icon,
    Widget? child,
    required String tooltip,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(child: child ?? Icon(icon, size: 22, color: fg)),
          ),
        ),
      ),
    );
  }
}
