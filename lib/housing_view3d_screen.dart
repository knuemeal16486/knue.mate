import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

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

  /// 한 손가락/마우스 왼쪽 드래그 기본 동작: false=이동(팬), true=회전·기울이기(오빗).
  /// 웹·데스크톱이나 한 손 조작에서도 3D 회전·기울이기를 쉽게 쓸 수 있게 한다.
  bool _orbitDragMode = false;

  /// 우클릭·휠클릭으로 드래그 중인지(데스크톱/웹 오빗 조작).
  bool _secondaryDragging = false;
  Offset _lastSecondaryPos = Offset.zero;

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
      // 라우트 전환 직후 첫 프레임이 먼저 그려진 뒤 바닥 텍스처를 굽는다(버벅임 방지).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _groundDark == isDark) {
          _bakeGround(isDark);
        }
      });
    }
  }

  Future<void> _bakeGround(bool isDark) async {
    try {
      // 웹(CanvasKit)은 2048px 초과 오프스크린 텍스처가 느리거나 실패할 수 있어
      // 1.0 ppm(1780×1660)으로 안전하고 빠르게 굽는다.
      final image = await renderView3Ground(
        base: widget.base,
        osmRoads: widget.osmRoads,
        isDark: isDark,
        ppm: kIsWeb ? 1.0 : kView3GroundPpm,
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

  // ── 제스처 (터치 + 마우스 휠·우클릭·트랙패드 핀치 모두 지원) ──

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
    _lastRotation = 0;
  }

  void _orbitBy(Offset delta) {
    _azimuth += delta.dx * 0.0065;
    _tilt = (_tilt + delta.dy * 0.0055).clamp(12 * math.pi / 180, 88 * math.pi / 180);
    _sync();
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_sceneOrNull == null || _secondaryDragging) return;
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
      _sync();
      return;
    }

    // Shift/Alt 키를 누른 채 끌거나 [회전] 모드가 켜져 있으면 한 손가락/좌클릭으로도 회전·기울이기.
    final kb = HardwareKeyboard.instance;
    final orbitActive = _orbitDragMode || kb.isShiftPressed || kb.isAltPressed;
    if (orbitActive) {
      _orbitBy(d.focalPointDelta);
      return;
    }

    // 기본 한 손가락/좌클릭 드래그: 땅을 잡고 끄는 것처럼 이동.
    final focal = (size.height / 2) / math.tan(30 * math.pi / 180);
    final mpp = _distance / focal;
    final along = d.focalPointDelta.dy * mpp / math.max(math.sin(_tilt), 0.35);
    _target = _clampToWorld(
      _target - cam.rightH * (d.focalPointDelta.dx * mpp) + cam.forwardH * along,
    );
    _sync();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_sceneOrNull == null) return;
    if (event is PointerScrollEvent) {
      // 마우스 휠 / 트랙패드 스크롤로 부드럽게 확대·축소
      final dy = event.scrollDelta.dy;
      if (dy.abs() < 0.01) return;
      final factor = math.exp(dy * 0.0018).clamp(0.75, 1.35);
      _zoomBy(factor);
    } else if (event is PointerScaleEvent) {
      if (event.scale > 0) {
        _zoomBy((1 / event.scale).clamp(0.75, 1.35));
      }
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    // 마우스 우클릭 또는 휠클릭 드래그 → 3D 회전·기울이기
    final isSecondary = (e.buttons & kSecondaryMouseButton) != 0 ||
        (e.buttons & kMiddleMouseButton) != 0;
    if (isSecondary) {
      _secondaryDragging = true;
      _lastSecondaryPos = e.localPosition;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_secondaryDragging || _sceneOrNull == null) return;
    final delta = e.localPosition - _lastSecondaryPos;
    _lastSecondaryPos = e.localPosition;
    _orbitBy(delta);
  }

  void _onPointerUp(PointerEvent _) {
    _secondaryDragging = false;
  }

  void _zoomBy(double factor) {
    _distance = (_distance * factor).clamp(40.0, 2600.0);
    _sync();
  }

  void _tiltBy(double deltaDeg) {
    _tilt = (_tilt + deltaDeg * math.pi / 180)
        .clamp(12 * math.pi / 180, 88 * math.pi / 180);
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
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _onPointerSignal,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  child: GestureDetector(
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
                  ),
                );
              },
            ),
          ),

          // 닫기 · 나침반
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
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
          ),

          // 우측 조작 HUD (이동/회전 전환 · 기울기 · 확대/축소)
          // mainAxisSize.min이 빠지면 Positioned 안에서 화면 전체 높이로 늘어나
          // 버튼이 화면 위로 밀려나고 나침반 클릭까지 가로막는다.
          Positioned(
            right: 12,
            bottom: 84,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _roundButton(
                    icon: _orbitDragMode
                        ? Icons.threed_rotation_rounded
                        : Icons.pan_tool_alt_rounded,
                    tooltip: _orbitDragMode ? '이동 모드로 전환' : '회전·기울기 모드로 전환',
                    bg: _orbitDragMode ? const Color(0xFF007AFF) : chip,
                    fg: _orbitDragMode ? Colors.white : fg,
                    onTap: () => setState(() => _orbitDragMode = !_orbitDragMode),
                  ),
                  const SizedBox(height: 8),
                  _roundButton(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: '시야 높이기',
                    bg: chip,
                    fg: fg,
                    onTap: () => _tiltBy(10),
                  ),
                  const SizedBox(height: 6),
                  _roundButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: '시야 낮추기',
                    bg: chip,
                    fg: fg,
                    onTap: () => _tiltBy(-10),
                  ),
                  const SizedBox(height: 10),
                  _roundButton(
                    icon: Icons.add_rounded,
                    tooltip: '확대',
                    bg: chip,
                    fg: fg,
                    onTap: () => _zoomBy(0.75),
                  ),
                  const SizedBox(height: 6),
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
              top: false,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: chip.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    kIsWeb
                        ? (_orbitDragMode
                            ? '드래그: 3D 회전·기울이기 · 휠: 확대/축소'
                            : '드래그: 이동 · Shift+드래그/우클릭: 회전·기울이기 · 휠: 확대/축소')
                        : (_orbitDragMode
                            ? '한 손가락: 3D 회전·기울이기 · 두 손가락: 확대/축소'
                            : '한 손가락: 이동 · 두 손가락: 회전·확대·기울이기'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.85)),
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
