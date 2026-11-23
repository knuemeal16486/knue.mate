// 3D 둘러보기 — 원근 투영으로 그리는 지도.
//
// 기존 3D 지도(housing_iso.dart)는 시점마다 건물 모양을 미리 만들어 두는
// 아이소메트릭이라, 손가락을 따라 매 프레임 돌리거나 골목 눈높이로 내려갈 수
// 없다. 여기는 카메라 하나(위치·방향)로 매 프레임 전부 다시 투영한다:
//
//   · 땅  = 언덕 높이를 가진 격자에 위에서 본 지도 그림을 입힌다(drawVertices).
//   · 건물 = 벽·지붕 삼각형을 먼 것부터 칠한다(화가 알고리즘).
//
// 좌표: x 동쪽(+), y 남쪽(+), z 위(+), 단위 m — 지도 데이터 그대로.
// 화면과 무관한 계산(카메라·자르기·삼각분할)은 순수 함수라 테스트한다.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'housing_iso.dart';
import 'ui_utils.dart' show KnueTokens;

/// 이보다 가까운 것은 잘라 낸다(카메라 뒤로 넘어간 점은 투영이 뒤집힌다).
const double kView3Near = 0.4;

/// 언덕 높이를 실제보다 과장하는 배율. 실제 비탈은 대부분 2~8%라 그대로
/// 그리면 평지처럼 보인다(지형을 입체로 보여 주는 지도들이 흔히 쓰는 방법).
/// 건물 높이는 과장하지 않는다.
const double kView3ReliefScale = 1.6;

/// 실제 땅 높이(해발 m) 격자. `tool/fetch_dem.dart`가 SRTM에서 뽑아
/// `assets/housing/campus_dem.json`으로 구워 둔다.
///
/// 지도([CampusElevation])의 언덕은 손으로 놓은 봉우리 5개라 원룸촌이 평지로
/// 나오고 봉우리 자리도 실제와 달랐다. 둘러보기는 이 실측 격자를 쓴다.
class CampusDem {
  final double minX, minY, step;
  final int nx, ny;

  /// 행 우선(북→남, 서→동) 높이(m).
  final Float32List heights;

  CampusDem({
    required this.minX,
    required this.minY,
    required this.step,
    required this.nx,
    required this.ny,
    required this.heights,
  }) : assert(heights.length == nx * ny);

  factory CampusDem.fromJson(Map<String, dynamic> j) {
    final h = j['h'] as List;
    return CampusDem(
      minX: (j['minX'] as num).toDouble(),
      minY: (j['minY'] as num).toDouble(),
      step: (j['step'] as num).toDouble(),
      nx: j['nx'] as int,
      ny: j['ny'] as int,
      // 0.1m 단위 정수로 저장돼 있다.
      heights: Float32List.fromList([for (final v in h) (v as num) / 10]),
    );
  }

  static Future<CampusDem> load() async => CampusDem.fromJson(
        jsonDecode(await rootBundle.loadString('assets/housing/campus_dem.json'))
            as Map<String, dynamic>,
      );

  /// 둘러보기에 넘기는 높이 — 실제 높이에 [kView3ReliefScale]을 곱한 것.
  double exaggerated(double x, double y) => at(x, y) * kView3ReliefScale;

  /// (x, y)의 높이. 격자 사이는 선형 보간하고, 격자 밖은 가장자리 값이다.
  double at(double x, double y) {
    final fx = ((x - minX) / step).clamp(0.0, nx - 1.0);
    final fy = ((y - minY) / step).clamp(0.0, ny - 1.0);
    final i = math.min(fx.floor(), nx - 2), j = math.min(fy.floor(), ny - 2);
    final ax = fx - i, ay = fy - j;
    final a = heights[j * nx + i], b = heights[j * nx + i + 1];
    final c = heights[(j + 1) * nx + i], d = heights[(j + 1) * nx + i + 1];
    return (a * (1 - ax) + b * ax) * (1 - ay) + (c * (1 - ax) + d * ax) * ay;
  }
}

/// 카메라. [yaw]는 북쪽에서 시계 방향(라디안), [pitch]는 위가 +.
@immutable
class View3Camera {
  final double x, y, z, yaw, pitch;

  const View3Camera({
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    required this.pitch,
  });

  /// [target]을 [distance]m 떨어져 내려다보는 카메라. [tilt]는 지평선에서
  /// 내려다보는 각(라디안, 90°면 바로 위).
  factory View3Camera.orbit({
    required Offset target,
    required double targetZ,
    required double distance,
    required double azimuth,
    required double tilt,
  }) {
    final cp = math.cos(-tilt), sp = math.sin(-tilt);
    final fx = cp * math.sin(azimuth), fy = -cp * math.cos(azimuth), fz = sp;
    return View3Camera(
      x: target.dx - fx * distance,
      y: target.dy - fy * distance,
      z: targetZ - fz * distance,
      yaw: azimuth,
      pitch: -tilt,
    );
  }

  /// 바라보는 방향의 수평 성분(단위 벡터).
  Offset get forwardH => Offset(math.sin(yaw), -math.cos(yaw));

  /// 오른쪽(수평, 단위 벡터).
  Offset get rightH => Offset(math.cos(yaw), math.sin(yaw));
}

/// 지도(아이소메트릭)의 회전값을 둘러보기 방위로 옮긴다 — 지도에서 화면
/// 위쪽이던 방향을 그대로 바라보며 시작하려고. 지도는 회전 0일 때 북서쪽이
/// 화면 위고, 평면 시점(위에서 보기)은 북쪽이 위다.
double view3AzimuthFromMap(double mapRotation, {bool topDown = false}) =>
    (topDown ? 0.0 : -math.pi / 4) - mapRotation;

/// 한 프레임 동안 쓰는 투영. 삼각함수를 한 번만 계산해 둔다.
class View3Projector {
  final View3Camera cam;
  final Size size;

  /// 초점 거리(픽셀). 세로 화각 [fovY] 기준.
  final double focal;
  final double _rx, _ry;
  final double _fx, _fy, _fz;
  final double _ux, _uy, _uz;

  View3Projector(this.cam, this.size, {double fovY = 60 * math.pi / 180})
      : focal = (size.height / 2) / math.tan(fovY / 2),
        _rx = math.cos(cam.yaw),
        _ry = math.sin(cam.yaw),
        _fx = math.cos(cam.pitch) * math.sin(cam.yaw),
        _fy = -math.cos(cam.pitch) * math.cos(cam.yaw),
        _fz = math.sin(cam.pitch),
        _ux = -math.sin(cam.pitch) * math.sin(cam.yaw),
        _uy = math.sin(cam.pitch) * math.cos(cam.yaw),
        _uz = math.cos(cam.pitch);

  /// 카메라 기준 오른쪽 거리.
  double camX(double x, double y, double z) =>
      (x - cam.x) * _rx + (y - cam.y) * _ry;

  /// 카메라 기준 위쪽 거리.
  double camY(double x, double y, double z) =>
      (x - cam.x) * _ux + (y - cam.y) * _uy + (z - cam.z) * _uz;

  /// 카메라 앞쪽 거리(깊이). [kView3Near]보다 작으면 화면에 못 그린다.
  double camZ(double x, double y, double z) =>
      (x - cam.x) * _fx + (y - cam.y) * _fy + (z - cam.z) * _fz;

  double screenX(double cx, double cz) => size.width / 2 + focal * cx / cz;
  double screenY(double cy, double cz) => size.height / 2 - focal * cy / cz;

  /// 월드 점 → 화면. 카메라 뒤면 null.
  Offset? project(double x, double y, double z) {
    final cz = camZ(x, y, z);
    if (cz < kView3Near) return null;
    return Offset(screenX(camX(x, y, z), cz), screenY(camY(x, y, z), cz));
  }

  /// 지평선의 화면 y. 하늘과 땅을 여기서 가른다.
  double get horizonY => size.height / 2 + focal * math.tan(cam.pitch);
}

/// 둘러보기에 넘기는 건물 하나(지도 화면이 색·이름을 정해 준다).
@immutable
class View3BuildingSpec {
  final BaseBuilding building;

  /// 지붕 색. 벽은 여기서 어둡게 낸다.
  final Color color;

  /// 색을 칠한 건물인지(원룸 구역·관리자 색). 벽도 그 색을 띤다.
  final bool tinted;
  final String? name;
  final bool highlighted;

  const View3BuildingSpec({
    required this.building,
    required this.color,
    this.tinted = false,
    this.name,
    this.highlighted = false,
  });
}

/// 미리 계산해 둔 건물 하나.
class View3Building {
  final View3BuildingSpec spec;

  /// 바깥 법선이 (dy, -dx)가 되도록 방향을 맞춘 바닥 꼭짓점(끝점 중복 없음).
  final List<Offset> ring;

  /// 지붕 삼각형(ring 인덱스 3개씩).
  final List<int> roof;
  final double baseZ, topZ;

  /// 꼭짓점마다 벽이 내려가는 높이([ring]과 같은 길이). 가장 낮은 모서리의
  /// **그려지는 땅**(평평한 삼각형 격자)보다 조금 아래까지 내려, 비탈에서도
  /// 벽 밑으로 틈이 뜨지 않는다. [baseZ](층·창문 기준)보다 낮다.
  final List<double> footZ;
  final Offset center;
  final Rect bounds;

  View3Building({
    required this.spec,
    required this.ring,
    required this.roof,
    required this.baseZ,
    required this.topZ,
    required this.footZ,
    required this.center,
    required this.bounds,
  });

  int get floors => spec.building.floors;
}

/// 가까이서 또렷하게 그리는 길 한 줄. 땅 그림은 미터당 1.5픽셀이라 눈높이로
/// 내려가면 길 가장자리가 번진다 — 카메라 근처 길만 도형으로 덧그린다.
class View3Road {
  /// 중심선 점마다 왼쪽·오른쪽 가장자리(x, y)와 높이. 바깥 띠(연석)는
  /// 조금 더 넓다.
  final Float32List left, right, leftOuter, rightOuter, z;
  final Rect bounds;
  final String kind;

  View3Road({
    required this.left,
    required this.right,
    required this.leftOuter,
    required this.rightOuter,
    required this.z,
    required this.bounds,
    required this.kind,
  });

  int get length => z.length;

  /// 중심선을 폭 [OsmRoad.widthM]의 띠로 편다. 긴 구간은 [step]m마다 쪼개
  /// 언덕을 따라 휘게 하고, 꺾이는 곳은 양쪽 방향의 평균으로 이어 틈이 없다.
  static View3Road? build(
    OsmRoad road,
    double Function(double x, double y) elevation, {
    double step = 12,
    double edge = 0.2,
  }) {
    final pts = <Offset>[];
    for (var i = 0; i < road.points.length; i++) {
      final p = road.points[i];
      if (pts.isNotEmpty) {
        final a = pts.last;
        final d = (p - a).distance;
        if (d < 0.05) continue;
        final n = (d / step).ceil();
        for (var k = 1; k < n; k++) {
          pts.add(Offset.lerp(a, p, k / n)!);
        }
      }
      pts.add(p);
    }
    if (pts.length < 2) return null;
    final n = pts.length;
    final hw = road.widthM / 2;
    final l = Float32List(n * 2), r = Float32List(n * 2);
    final lo = Float32List(n * 2), ro = Float32List(n * 2);
    final z = Float32List(n);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    Offset unit(Offset v) => v.distance == 0 ? Offset.zero : v / v.distance;
    for (var i = 0; i < n; i++) {
      final prev = pts[i == 0 ? 0 : i - 1], next = pts[i == n - 1 ? n - 1 : i + 1];
      final here = pts[i];
      final d0 = unit(here - prev), d1 = unit(next - here);
      var dir = unit(d0 + d1);
      if (dir == Offset.zero) dir = d1 == Offset.zero ? d0 : d1;
      // 꺾일수록 띠가 좁아 보이지 않게 넓힌다(뾰족한 꺾임은 2배까지만).
      final cosHalf = (d0 == Offset.zero || d1 == Offset.zero)
          ? 1.0
          : math.sqrt(((1 + d0.dx * d1.dx + d0.dy * d1.dy) / 2).clamp(0.25, 1.0));
      final normal = Offset(-dir.dy, dir.dx) / cosHalf;
      void put(Float32List list, Offset p) {
        list[i * 2] = p.dx;
        list[i * 2 + 1] = p.dy;
      }

      put(l, here + normal * hw);
      put(r, here - normal * hw);
      put(lo, here + normal * (hw + edge));
      put(ro, here - normal * (hw + edge));
      z[i] = elevation(here.dx, here.dy) + 0.06;
      minX = math.min(minX, here.dx);
      maxX = math.max(maxX, here.dx);
      minY = math.min(minY, here.dy);
      maxY = math.max(maxY, here.dy);
    }
    return View3Road(
      left: l,
      right: r,
      leftOuter: lo,
      rightOuter: ro,
      z: z,
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY).inflate(hw + edge),
      kind: road.kind,
    );
  }
}

/// 다각형의 부호 있는 넓이(신발끈 공식).
double signedArea(List<Offset> ring) {
  var a = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i], q = ring[(i + 1) % ring.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

/// 끝점 중복·겹친 점을 빼고, 넓이가 +가 되는 방향으로 맞춘다.
List<Offset> normalizeRing(List<Offset> ring) {
  final out = <Offset>[];
  for (final p in ring) {
    if (out.isEmpty || (out.last - p).distanceSquared > 1e-6) out.add(p);
  }
  if (out.length > 1 && (out.first - out.last).distanceSquared < 1e-6) {
    out.removeLast();
  }
  return signedArea(out) < 0 ? out.reversed.toList() : out;
}

/// 단순 다각형을 삼각형으로 나눈다(귀 자르기). [ring]은 [normalizeRing]을
/// 거친 것이어야 한다. 인덱스 3개씩 돌려준다.
///
/// 건물 바닥은 ㄱ·ㄷ자가 흔해서 부채꼴로 나누면 바깥으로 삐져나온다.
/// 모양이 꼬여 귀를 못 찾으면 남은 부분만 부채꼴로 채운다(구멍보다는 낫다).
List<int> triangulate(List<Offset> ring) {
  final n = ring.length;
  if (n < 3) return const [];
  final idx = List<int>.generate(n, (i) => i);
  final out = <int>[];

  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  bool inside(Offset p, Offset a, Offset b, Offset c) =>
      cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0;

  var guard = 0;
  while (idx.length > 3 && guard < n * n) {
    var cut = false;
    for (var i = 0; i < idx.length; i++) {
      final ia = idx[(i + idx.length - 1) % idx.length];
      final ib = idx[i];
      final ic = idx[(i + 1) % idx.length];
      final a = ring[ia], b = ring[ib], c = ring[ic];
      if (cross(a, b, c) <= 1e-9) continue; // 오목한 꼭짓점
      var blocked = false;
      for (final k in idx) {
        if (k == ia || k == ib || k == ic) continue;
        if (inside(ring[k], a, b, c)) {
          blocked = true;
          break;
        }
      }
      if (blocked) continue;
      out..add(ia)..add(ib)..add(ic);
      idx.removeAt(i);
      cut = true;
      break;
    }
    if (!cut) break;
    guard++;
  }
  for (var i = 1; i + 1 < idx.length; i++) {
    out..add(idx[0])..add(idx[i])..add(idx[i + 1]);
  }
  return out;
}

/// 점이 다각형 안인지(짝홀 규칙).
bool pointInRing(Offset p, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// 둘러보기 장면 — 땅 격자와 건물. 한 번 만들어 두고 매 프레임 투영만 한다.
class View3Scene {
  /// 땅 격자가 덮는 범위(위에서 본 지도 그림도 이 범위다).
  final Rect world;

  /// 격자 한 칸(m).
  final double cell;
  final int nx, ny;

  /// 격자 꼭짓점 높이((nx+1)×(ny+1), 행 우선).
  final Float32List heights;

  /// 격자 꼭짓점 음영(0~255). 해를 등진 비탈이 어둡다.
  final Uint8List shade;
  final List<View3Building> buildings;

  /// 가까이서 덧그리는 길([View3Road]).
  final List<View3Road> roads;
  final double Function(double x, double y) _elevation;

  View3Scene._(
    this.world,
    this.cell,
    this.nx,
    this.ny,
    this.heights,
    this.shade,
    this.buildings,
    this.roads,
    this._elevation,
  );

  /// 땅 높이(m).
  double groundAt(double x, double y) => _elevation(x, y);

  /// **그려지는** 땅의 높이 — 격자 칸을 대각선으로 가른 평평한 삼각형 위.
  ///
  /// [groundAt]은 실측 격자를 부드럽게 보간한 값이라, 20m 칸의 삼각형과는
  /// 휜 땅에서 수십 cm 어긋난다. 땅에 붙어 보여야 하는 것(벽 밑동, 길)은
  /// 이 높이에 맞춘다.
  double meshHeightAt(double x, double y) =>
      _meshHeight(world, cell, nx, ny, heights, x, y);

  static double _meshHeight(
    Rect world,
    double cell,
    int nx,
    int ny,
    Float32List heights,
    double x,
    double y,
  ) {
    final gx = ((x - world.left) / cell).clamp(0.0, nx.toDouble());
    final gy = ((y - world.top) / cell).clamp(0.0, ny.toDouble());
    final i = math.min(gx.floor(), nx - 1), j = math.min(gy.floor(), ny - 1);
    final fx = gx - i, fy = gy - j;
    final cols = nx + 1;
    final h00 = heights[j * cols + i], h10 = heights[j * cols + i + 1];
    final h01 = heights[(j + 1) * cols + i];
    final h11 = heights[(j + 1) * cols + i + 1];
    // 땅을 그릴 때와 같은 대각선(왼쪽 위 ↔ 오른쪽 아래)으로 가른다.
    return fx >= fy
        ? h00 + (h10 - h00) * fx + (h11 - h10) * fy
        : h00 + (h11 - h01) * fx + (h01 - h00) * fy;
  }

  /// 벽 밑동을 그려지는 땅보다 이만큼 더 내린다(m). 벽 가운데서 땅이 조금 더
  /// 꺼져 있어도 틈이 안 보이게.
  static const double kFootSink = 0.6;

  /// [elevation]은 (x, y)의 땅 높이(m) — 앱은 실측 격자([CampusDem.at])를
  /// 넘긴다. 안 넘기면 지도와 같은 손 모델이다(실측을 못 읽었을 때).
  factory View3Scene.build({
    required Rect world,
    required List<View3BuildingSpec> buildings,
    List<OsmRoad> roads = const [],
    double cell = 20,
    double floorHeight = 3,
    double Function(double x, double y)? elevation,
  }) {
    final elev = elevation ?? CampusElevation.elevationAt;
    final nx = (world.width / cell).ceil();
    final ny = (world.height / cell).ceil();
    final heights = Float32List((nx + 1) * (ny + 1));
    final shade = Uint8List((nx + 1) * (ny + 1));
    for (var j = 0; j <= ny; j++) {
      for (var i = 0; i <= nx; i++) {
        final x = world.left + i * cell, y = world.top + j * cell;
        heights[j * (nx + 1) + i] = elev(x, y);
        // 해는 북서쪽. 북서로 내려가는 비탈(해를 보는 쪽)은 그대로 두고,
        // 남동으로 내려가는 비탈을 어둡게 한다. 곱해서 입히므로 밝게는 못 한다.
        const d = 6.0;
        final gx = (elev(x + d, y) - elev(x - d, y)) / (2 * d);
        final gy = (elev(x, y + d) - elev(x, y - d)) / (2 * d);
        final away = -(gx + gy) / math.sqrt2; // 남동쪽으로 내려가는 정도
        final s = (1 - 1.4 * math.max(0.0, away)).clamp(0.68, 1.0);
        shade[j * (nx + 1) + i] = (s * 255).round();
      }
    }

    final out = <View3Building>[];
    for (final spec in buildings) {
      final ring = normalizeRing(spec.building.ring);
      if (ring.length < 3 || spec.building.floors < 1) continue;
      var minX = ring.first.dx, maxX = minX;
      var minY = ring.first.dy, maxY = minY;
      // 비탈에 선 건물이 한쪽이 뜨지 않게 가장 낮은 모서리에 맞춘다.
      var baseZ = double.infinity;
      for (final p in ring) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
        baseZ = math.min(baseZ, elev(p.dx, p.dy));
      }
      final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      final groundTop = elev(center.dx, center.dy);
      out.add(View3Building(
        spec: spec,
        ring: ring,
        roof: triangulate(ring),
        baseZ: baseZ,
        topZ: groundTop + spec.building.floors * floorHeight,
        footZ: List.filled(
          ring.length,
          [
                baseZ,
                for (final p in ring)
                  _meshHeight(world, cell, nx, ny, heights, p.dx, p.dy),
              ].reduce(math.min) -
              kFootSink,
        ),
        center: center,
        bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
      ));
    }
    final strips = <View3Road>[];
    for (final r in roads) {
      final strip = View3Road.build(r, elev);
      if (strip != null && strip.bounds.overlaps(world)) strips.add(strip);
    }
    return View3Scene._(world, cell, nx, ny, heights, shade, out, strips, elev);
  }

  /// [eye]에서 [target]을 볼 때 다른 건물([except] 제외)에 가려지는지.
  /// 이름표가 앞 건물 벽을 뚫고 보이지 않게 한다. 눈→목표 선이 그 건물
  /// 벽을 지나는 자리에서 지붕보다 낮으면 가려진 것이다.
  bool sightBlocked(
    Offset eye,
    double eyeZ,
    Offset target,
    double targetZ, {
    View3Building? except,
  }) {
    final seg = Rect.fromPoints(eye, target);
    final d = target - eye;
    for (final b in buildings) {
      if (identical(b, except) || !b.bounds.overlaps(seg)) continue;
      final ring = b.ring;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], e = ring[(i + 1) % ring.length] - ring[i];
        final den = d.dx * e.dy - d.dy * e.dx;
        if (den.abs() < 1e-9) continue;
        final w = a - eye;
        final t = (w.dx * e.dy - w.dy * e.dx) / den;
        final u = (w.dx * d.dy - w.dy * d.dx) / den;
        if (t <= 0.02 || t >= 0.98 || u < 0 || u > 1) continue;
        if (eyeZ + (targetZ - eyeZ) * t < b.topZ) return true;
      }
    }
    return false;
  }
}

/// 삼각형을 모아 두는 버퍼. 프레임마다 다시 쓰고, 모자라면 두 배로 늘린다.
class _TriBuffer {
  Float32List pos = Float32List(6 * 4096);
  Float32List uv = Float32List(6 * 4096);
  Int32List col = Int32List(3 * 4096);
  int n = 0; // 꼭짓점 수

  void clear() => n = 0;

  void _grow() {
    pos = Float32List(pos.length * 2)..setRange(0, pos.length, pos);
    uv = Float32List(uv.length * 2)..setRange(0, uv.length, uv);
    col = Int32List(col.length * 2)..setRange(0, col.length, col);
  }

  void add(double sx, double sy, double u, double v, int color) {
    if (n * 2 + 2 > pos.length) _grow();
    pos[n * 2] = sx;
    pos[n * 2 + 1] = sy;
    uv[n * 2] = u;
    uv[n * 2 + 1] = v;
    col[n] = color;
    n++;
  }

  ui.Vertices? vertices({required bool textured}) {
    if (n == 0) return null;
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(pos, 0, n * 2),
      textureCoordinates: textured ? Float32List.sublistView(uv, 0, n * 2) : null,
      colors: Int32List.sublistView(col, 0, n),
    );
  }
}

/// 카메라 좌표의 삼각형 하나를 가까운 면에서 잘라 화면 삼각형으로 넣는다.
/// 꼭짓점마다 (오른쪽, 위, 깊이, u, v, 색). 돌려주는 값은 넣은 삼각형 수 —
/// 테스트가 자르기 규칙(0·1·2개)을 확인한다.
int clipAndEmit(
  View3Projector p,
  void Function(double sx, double sy, double u, double v, int color) emit,
  List<double> a,
  List<double> b,
  List<double> c,
  int ca,
  int cb,
  int cc,
) {
  final ina = a[2] >= kView3Near, inb = b[2] >= kView3Near, inc = c[2] >= kView3Near;
  final count = (ina ? 1 : 0) + (inb ? 1 : 0) + (inc ? 1 : 0);
  if (count == 0) return 0;

  void out(List<double> v, int color) =>
      emit(p.screenX(v[0], v[2]), p.screenY(v[1], v[2]), v[3], v[4], color);

  if (count == 3) {
    out(a, ca);
    out(b, cb);
    out(c, cc);
    return 1;
  }

  // 안쪽 점 [i]와 바깥 점 [o] 사이, 가까운 면과 만나는 점.
  List<double> cut(List<double> i, List<double> o) {
    final t = (kView3Near - i[2]) / (o[2] - i[2]);
    return [
      i[0] + (o[0] - i[0]) * t,
      i[1] + (o[1] - i[1]) * t,
      kView3Near,
      i[3] + (o[3] - i[3]) * t,
      i[4] + (o[4] - i[4]) * t,
    ];
  }

  // 안쪽 점이 맨 앞에 오도록 돌린다(감는 방향은 그대로).
  var v0 = a, v1 = b, v2 = c;
  var c0 = ca, c1 = cb, c2 = cc;
  var i0 = ina, i1 = inb;
  if (count == 1) {
    while (!i0) {
      final tv = v0, tc = c0;
      v0 = v1;
      c0 = c1;
      v1 = v2;
      c1 = c2;
      v2 = tv;
      c2 = tc;
      i0 = i1;
      i1 = v1[2] >= kView3Near;
    }
    out(v0, c0);
    out(cut(v0, v1), c0);
    out(cut(v0, v2), c0);
    return 1;
  }
  // 둘이 안쪽: 바깥 점이 맨 뒤(v2)에 오게 돌린다.
  while (v2[2] >= kView3Near) {
    final tv = v0, tc = c0;
    v0 = v1;
    c0 = c1;
    v1 = v2;
    c1 = c2;
    v2 = tv;
    c2 = tc;
  }
  final m1 = cut(v1, v2), m0 = cut(v0, v2);
  out(v0, c0);
  out(v1, c1);
  out(m1, c1);
  out(v0, c0);
  out(m1, c1);
  out(m0, c0);
  return 2;
}

int _argb(Color c) => c.toARGB32();

int _lerpArgb(int a, int b, double t) {
  int ch(int shift) {
    final x = (a >> shift) & 0xFF, y = (b >> shift) & 0xFF;
    return (x + (y - x) * t).round() & 0xFF;
  }

  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// 둘러보기에서 쓰는 건물 지붕 색 — 지도([HousingMapPainter])와 같은 규칙.
Color view3RoofColor(IsoBuilding b, bool isDark) {
  if (b.highlighted) return const Color(0xFF03C75A);
  final zone = b.zoneColor;
  if (zone != null) {
    return isDark ? Color.lerp(zone, Colors.black, 0.35)! : zone;
  }
  if (b.building.isCampus) return campusUseColor(b.building.use, isDark);
  return isDark ? const Color(0xFF2A3340) : const Color(0xFFFFFFFF);
}

/// 하늘 위·아래 색과, 지도 그림 밖 먼 땅 색.
({Color skyTop, Color skyLow, Color farGround}) view3Backdrop(bool isDark) => isDark
    ? (
        skyTop: const Color(0xFF0B1220),
        skyLow: const Color(0xFF26303F),
        farGround: mapBackgroundColor(true),
      )
    : (
        skyTop: const Color(0xFF8EC5F2),
        skyLow: const Color(0xFFE6F1FA),
        farGround: mapBackgroundColor(false),
      );

class View3Painter extends CustomPainter {
  final View3Scene scene;
  final ValueNotifier<View3Camera> camera;

  /// 위에서 본 지도 그림([View3Scene.world] 범위). 아직 없으면 맨땅 색.
  final ui.Image? ground;
  final bool isDark;

  /// 이름표를 보여 줄 거리(m)와 개수.
  final double labelRange;
  final int maxLabels;

  /// 창문을 그릴 거리(m). 멀면 점으로 뭉개지고 무겁기만 하다.
  final double windowRange;

  /// 길을 도형으로 덧그릴 거리(m). 그보다 멀면 땅 그림으로 충분하다.
  final double roadRange;

  View3Painter({
    required this.scene,
    required this.camera,
    required this.isDark,
    this.ground,
    this.labelRange = 700,
    this.maxLabels = 40,
    this.windowRange = 260,
    this.roadRange = 240,
  }) : super(repaint: camera);

  static final _TriBuffer _groundBuf = _TriBuffer();
  static final _TriBuffer _solidBuf = _TriBuffer();
  static final Map<String, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = View3Projector(camera.value, size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintBackdrop(canvas, size, p);
    _paintGround(canvas, size, p);
    _paintRoads(canvas, size, p);
    _paintBuildings(canvas, size, p);
    _paintLabels(canvas, size, p);
    canvas.restore();
  }

  void _paintBackdrop(Canvas canvas, Size size, View3Projector p) {
    final c = view3Backdrop(isDark);
    final hy = p.horizonY.clamp(-size.height, size.height * 2).toDouble();
    final sky = Rect.fromLTRB(0, 0, size.width, math.max(hy, 0));
    if (!sky.isEmpty) {
      canvas.drawRect(
        sky,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, hy - size.height * 0.9),
            Offset(0, hy),
            [c.skyTop, c.skyLow],
          ),
      );
    }
    if (hy < size.height) {
      // 지평선 가까이는 하늘빛이 살짝 도는 먼 땅.
      canvas.drawRect(
        Rect.fromLTRB(0, math.max(hy, 0), size.width, size.height),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, hy),
            Offset(0, hy + size.height * 0.25),
            [Color.lerp(c.farGround, c.skyLow, 0.85)!, c.farGround],
          ),
      );
    }
  }

  void _paintGround(Canvas canvas, Size size, View3Projector p) {
    final s = scene;
    final buf = _groundBuf..clear();
    final cols = s.nx + 1;
    final count = cols * (s.ny + 1);
    // 격자 꼭짓점을 카메라 좌표로 한 번에.
    final cx = Float32List(count), cy = Float32List(count), cz = Float32List(count);
    for (var j = 0; j <= s.ny; j++) {
      final y = s.world.top + j * s.cell;
      for (var i = 0; i <= s.nx; i++) {
        final k = j * cols + i;
        final x = s.world.left + i * s.cell, z = s.heights[k];
        cx[k] = p.camX(x, y, z);
        cy[k] = p.camY(x, y, z);
        cz[k] = p.camZ(x, y, z);
      }
    }
    final image = ground;
    final ppmX = image == null ? 0.0 : image.width / s.world.width;
    final ppmY = image == null ? 0.0 : image.height / s.world.height;
    final bare = _argb(mapBackgroundColor(isDark));

    List<double> vert(int k, int i, int j) => [
          cx[k],
          cy[k],
          cz[k],
          i * s.cell * ppmX,
          j * s.cell * ppmY,
        ];
    int color(int k) {
      final g = s.shade[k];
      if (image != null) return 0xFF000000 | (g << 16) | (g << 8) | g;
      return _lerpArgb(0xFF000000, bare, g / 255);
    }

    void cellAt(int i, int j) {
      final k00 = j * cols + i, k10 = k00 + 1;
      final k01 = k00 + cols, k11 = k01 + 1;
      final z0 = cz[k00], z1 = cz[k10], z2 = cz[k01], z3 = cz[k11];
      if (z0 < kView3Near && z1 < kView3Near && z2 < kView3Near && z3 < kView3Near) {
        return;
      }
      if (z0 >= kView3Near && z1 >= kView3Near && z2 >= kView3Near && z3 >= kView3Near) {
        // 화면 밖 칸은 건너뛴다.
        final x0 = p.screenX(cx[k00], z0), x1 = p.screenX(cx[k10], z1);
        final x2 = p.screenX(cx[k01], z2), x3 = p.screenX(cx[k11], z3);
        if (x0 < 0 && x1 < 0 && x2 < 0 && x3 < 0) return;
        final w = size.width;
        if (x0 > w && x1 > w && x2 > w && x3 > w) return;
        final y0 = p.screenY(cy[k00], z0), y1 = p.screenY(cy[k10], z1);
        final y2 = p.screenY(cy[k01], z2), y3 = p.screenY(cy[k11], z3);
        if (y0 < 0 && y1 < 0 && y2 < 0 && y3 < 0) return;
        final h = size.height;
        if (y0 > h && y1 > h && y2 > h && y3 > h) return;
      }
      final a = vert(k00, i, j), b = vert(k10, i + 1, j);
      final c = vert(k01, i, j + 1), d = vert(k11, i + 1, j + 1);
      clipAndEmit(p, buf.add, a, b, d, color(k00), color(k10), color(k11));
      clipAndEmit(p, buf.add, a, d, c, color(k00), color(k11), color(k01));
    }

    // 먼 칸부터: 카메라가 있는 칸을 향해 양쪽에서 좁혀 온다. 높이 격자는 이
    // 순서면 정렬 없이도 앞 언덕이 뒤 언덕을 가린다.
    final ic = ((p.cam.x - s.world.left) / s.cell).floor().clamp(0, s.nx - 1);
    final jc = ((p.cam.y - s.world.top) / s.cell).floor().clamp(0, s.ny - 1);
    void row(int j) {
      for (var i = 0; i < ic; i++) {
        cellAt(i, j);
      }
      for (var i = s.nx - 1; i >= ic; i--) {
        cellAt(i, j);
      }
    }

    for (var j = 0; j < jc; j++) {
      row(j);
    }
    for (var j = s.ny - 1; j >= jc; j--) {
      row(j);
    }

    final verts = buf.vertices(textured: image != null);
    if (verts == null) return;
    final paint = Paint();
    if (image != null) {
      paint.shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    }
    canvas.drawVertices(
      verts,
      image != null ? BlendMode.modulate : BlendMode.dst,
      paint,
    );
    verts.dispose();
  }

  /// 카메라 근처 길을 또렷한 띠로 덧그린다. 색은 지도([HousingMapPainter])와 같다.
  void _paintRoads(Canvas canvas, Size size, View3Projector p) {
    final cam = p.cam;
    // 높이 떠 있으면 어느 길도 범위 안에 안 든다 — 통째로 건너뛴다.
    if (cam.z - scene.groundAt(cam.x, cam.y) > roadRange) return;
    final buf = _solidBuf..clear();
    final reach = Rect.fromCircle(center: Offset(cam.x, cam.y), radius: roadRange);
    final range2 = roadRange * roadRange;
    final near = [
      for (final r in scene.roads)
        if (r.bounds.overlaps(reach)) r,
    ];

    void strip(View3Road r, Float32List l, Float32List rt, int color) {
      List<double>? pl, pr;
      var prevNear = false;
      for (var i = 0; i < r.length; i++) {
        final mx = (l[i * 2] + rt[i * 2]) / 2 - cam.x;
        final my = (l[i * 2 + 1] + rt[i * 2 + 1]) / 2 - cam.y;
        final isNear = mx * mx + my * my < range2;
        final z = r.z[i];
        final cl = [
          p.camX(l[i * 2], l[i * 2 + 1], z),
          p.camY(l[i * 2], l[i * 2 + 1], z),
          p.camZ(l[i * 2], l[i * 2 + 1], z),
          0.0,
          0.0,
        ];
        final cr = [
          p.camX(rt[i * 2], rt[i * 2 + 1], z),
          p.camY(rt[i * 2], rt[i * 2 + 1], z),
          p.camZ(rt[i * 2], rt[i * 2 + 1], z),
          0.0,
          0.0,
        ];
        if (pl != null && pr != null && (isNear || prevNear)) {
          clipAndEmit(p, buf.add, pl, pr, cr, color, color, color);
          clipAndEmit(p, buf.add, pl, cr, cl, color, color, color);
        }
        pl = cl;
        pr = cr;
        prevNear = isNear;
      }
    }

    bool pedestrian(View3Road r) =>
        r.kind == 'walk' || r.kind == 'path' || r.kind == 'steps';
    // 가장자리(연석)를 전부 먼저, 그 위에 노면을 — 교차로에서 노면이 이어진다.
    for (final r in near) {
      strip(
        r,
        r.leftOuter,
        r.rightOuter,
        pedestrian(r)
            ? (isDark ? 0xFF192A1D : 0xFFB5CEB9)
            : (isDark ? 0xFF2B3744 : 0xFFB8C8D5),
      );
    }
    for (final r in near) {
      strip(
        r,
        r.left,
        r.right,
        pedestrian(r)
            ? (isDark ? 0xFF223628 : 0xFFE1EFE4)
            : r.kind == 'major'
                ? (isDark ? 0xFF6B5820 : 0xFFFFE682)
                : (isDark ? 0xFF2C323B : 0xFFFFFFFF),
      );
    }
    final verts = buf.vertices(textured: false);
    if (verts == null) return;
    canvas.drawVertices(verts, BlendMode.dst, Paint());
    verts.dispose();
  }

  void _paintBuildings(Canvas canvas, Size size, View3Projector p) {
    final buf = _solidBuf..clear();
    final cam = p.cam;
    final order = <(double, View3Building)>[];
    for (final b in scene.buildings) {
      final dx = b.center.dx - cam.x, dy = b.center.dy - cam.y;
      final d2 = dx * dx + dy * dy;
      // 완전히 뒤에 있는 건물은 뺀다(가까운 건 벽이 화면에 걸칠 수 있다).
      final ahead = p.camZ(b.center.dx, b.center.dy, (b.baseZ + b.topZ) / 2);
      final reach = b.bounds.longestSide + (b.topZ - b.baseZ);
      if (ahead < -reach) continue;
      order.add((d2, b));
    }
    order.sort((a, b) => b.$1.compareTo(a.$1));

    // 해는 북서쪽(지도와 같다). 벽이 해를 볼수록 밝다.
    const sunX = -0.7071, sunY = -0.7071;
    final lightWall = isDark ? 0xFF2A323D : 0xFFF3F6FA;
    final darkWall = isDark ? 0xFF171C23 : 0xFFCFD8E3;
    final glass = isDark ? 0xFF0C1016 : 0xFF6A7F96;
    final windowRange2 = windowRange * windowRange;

    List<double> v(double x, double y, double z) =>
        [p.camX(x, y, z), p.camY(x, y, z), p.camZ(x, y, z), 0, 0];

    for (final (d2, b) in order) {
      final ring = b.ring;
      final n = ring.length;
      final roofColor = _argb(b.spec.color);
      final floorH = (b.topZ - b.baseZ) / b.floors;

      // 보이는 벽만, 먼 벽부터.
      final walls = <(double, int)>[];
      for (var i = 0; i < n; i++) {
        final a = ring[i], c = ring[(i + 1) % n];
        final nx = c.dy - a.dy, ny = -(c.dx - a.dx);
        if ((cam.x - a.dx) * nx + (cam.y - a.dy) * ny <= 0) continue;
        final mx = (a.dx + c.dx) / 2 - cam.x, my = (a.dy + c.dy) / 2 - cam.y;
        walls.add((mx * mx + my * my, i));
      }
      walls.sort((x, y) => y.$1.compareTo(x.$1));

      for (final (_, i) in walls) {
        final a = ring[i], c = ring[(i + 1) % n];
        final ex = c.dx - a.dx, ey = c.dy - a.dy;
        final len = math.sqrt(ex * ex + ey * ey);
        if (len < 0.05) continue;
        final lit = ((ey * sunX - ex * sunY) / len + 1) / 2;
        final wall = b.spec.tinted
            ? _lerpArgb(roofColor, 0xFF000000, 0.26 - 0.18 * lit)
            : _lerpArgb(darkWall, lightWall, lit);
        final a0 = v(a.dx, a.dy, b.footZ[i]), a1 = v(a.dx, a.dy, b.topZ);
        final c0 = v(c.dx, c.dy, b.footZ[(i + 1) % n]), c1 = v(c.dx, c.dy, b.topZ);
        if (a0[2] < kView3Near && a1[2] < kView3Near && c0[2] < kView3Near && c1[2] < kView3Near) {
          continue;
        }
        // 아래로 갈수록 살짝 어둡게 — 흰 벽이 흰 땅에 묻히지 않고 땅에 선 것처럼 보인다.
        final foot = _lerpArgb(wall, 0xFF000000, isDark ? 0.18 : 0.10);
        clipAndEmit(p, buf.add, a0, c0, c1, foot, foot, wall);
        clipAndEmit(p, buf.add, a0, c1, a1, foot, wall, wall);
        // 지붕 턱(파라펫). 가까운 건물만 — 벽과 지붕·하늘의 경계가 또렷해진다.
        if (d2 < windowRange2 && b.topZ - b.baseZ > 2.5) {
          final cap = _lerpArgb(wall, 0xFF000000, isDark ? 0.30 : 0.16);
          final a2 = v(a.dx, a.dy, b.topZ - 0.35), c2 = v(c.dx, c.dy, b.topZ - 0.35);
          clipAndEmit(p, buf.add, a2, c2, c1, cap, cap, cap);
          clipAndEmit(p, buf.add, a2, c1, a1, cap, cap, cap);
        }

        if (d2 < windowRange2) {
          final win = _lerpArgb(wall, glass, isDark ? 0.5 : 0.55);
          for (final w in wallWindows(len, b.floors, floorH)) {
            final x0 = a.dx + ex * w.t0, y0 = a.dy + ey * w.t0;
            final x1 = a.dx + ex * w.t1, y1 = a.dy + ey * w.t1;
            // 땅에 묻힌 층(비탈)은 창을 내지 않는다.
            if (b.baseZ + w.z0 < scene.groundAt(x0, y0) + 0.3) continue;
            final p0 = v(x0, y0, b.baseZ + w.z0), p1 = v(x1, y1, b.baseZ + w.z0);
            final p2 = v(x1, y1, b.baseZ + w.z1), p3 = v(x0, y0, b.baseZ + w.z1);
            clipAndEmit(p, buf.add, p0, p1, p2, win, win, win);
            clipAndEmit(p, buf.add, p0, p2, p3, win, win, win);
          }
        }
      }

      // 지붕은 위에서 볼 때만 보인다.
      if (cam.z > b.topZ) {
        final rv = [for (final q in ring) v(q.dx, q.dy, b.topZ)];
        for (var t = 0; t + 2 < b.roof.length; t += 3) {
          clipAndEmit(
            p,
            buf.add,
            rv[b.roof[t]],
            rv[b.roof[t + 1]],
            rv[b.roof[t + 2]],
            roofColor,
            roofColor,
            roofColor,
          );
        }
      }
    }

    final verts = buf.vertices(textured: false);
    if (verts == null) return;
    canvas.drawVertices(verts, BlendMode.dst, Paint());
    verts.dispose();
  }

  void _paintLabels(Canvas canvas, Size size, View3Projector p) {
    if (maxLabels <= 0) return;
    final cam = p.cam;
    // 높이 올라가면 그만큼 멀리까지 이름을 보여 준다(멀리서 전체를 볼 때).
    final range = math.max(
      labelRange,
      (cam.z - scene.groundAt(cam.x, cam.y)) * 2.2,
    );
    final near = <(double, View3Building)>[];
    for (final b in scene.buildings) {
      final name = b.spec.name;
      if (name == null || name.isEmpty) continue;
      final d = (b.center - Offset(cam.x, cam.y)).distance;
      if (d > range && !b.spec.highlighted) continue;
      near.add((b.spec.highlighted ? -1 : d, b));
    }
    near.sort((a, b) => a.$1.compareTo(b.$1));

    final taken = <Rect>[];
    for (final (_, b) in near) {
      if (taken.length >= maxLabels) break;
      // 지붕보다 낮은 데서 올려다볼 땐 이름표를 눈높이 조금 위(벽)에 단다 —
      // 지붕 위에 달면 가까운 건물 이름이 화면 위로 나가 버린다.
      final anchorZ = cam.z < b.topZ
          ? math.min(b.topZ + 1.5, cam.z + 3.5)
          : b.topZ + 1.5;
      final at = p.project(b.center.dx, b.center.dy, anchorZ);
      if (at == null) continue;
      if (at.dx < -40 || at.dx > size.width + 40 || at.dy < 0 || at.dy > size.height) {
        continue;
      }
      final hi = b.spec.highlighted;
      final tp = _labels.putIfAbsent('${hi ? 1 : 0}${isDark ? 1 : 0}|${b.spec.name}', () {
        return TextPainter(
          text: TextSpan(
            text: b.spec.name,
            style: TextStyle(
              color: hi
                  ? Colors.white
                  : (isDark ? Colors.white : const Color(0xFF222831)),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              fontFamily: KnueTokens.fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
      });
      final rect = Rect.fromCenter(
        center: at.translate(0, -tp.height / 2 - 4),
        width: tp.width + 12,
        height: tp.height + 6,
      );
      if (taken.any((r) => r.inflate(3).overlaps(rect))) continue;
      if (scene.sightBlocked(
        Offset(cam.x, cam.y),
        cam.z,
        b.center,
        anchorZ,
        except: b,
      )) {
        continue;
      }
      taken.add(rect);
      final pill = RRect.fromRectAndRadius(rect, const Radius.circular(9));
      canvas.drawRRect(
        pill,
        Paint()
          ..color = hi
              ? const Color(0xFF03C75A)
              : (isDark ? const Color(0xE61C1C1E) : const Color(0xF2FFFFFF)),
      );
      if (!hi) {
        canvas.drawRRect(
          pill,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = isDark ? Colors.white24 : const Color(0x33000000),
        );
      }
      tp.paint(canvas, rect.topLeft + const Offset(6, 3));
    }
  }

  @override
  bool shouldRepaint(View3Painter old) =>
      old.scene != scene ||
      old.ground != ground ||
      old.isDark != isDark ||
      old.labelRange != labelRange ||
      old.maxLabels != maxLabels ||
      old.windowRange != windowRange ||
      old.roadRange != roadRange;
}
