import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'stall_align.dart';

/// 캠퍼스 내 녹지·수림 구역 종류 (위성사진 실사 기반).
enum CampusGreenKind {
  /// 짙은 상록 소나무숲 (청람산림, 원룸촌 경계, 동쪽 능선 등).
  pineForest,

  /// 혼효림·구릉지 숲 (청람동산 중앙 언덕, 대운동장 서쪽 사면 등).
  woodland,

  /// 교내 잔디광장·정원·가로 녹지대.
  lawn,
}

/// 위성사진에서 도출한 캠퍼스 녹지 구역 다각형 (월드 좌표, 단위 m).
class CampusGreenZone {
  final String name;
  final CampusGreenKind kind;
  final List<Offset> ring;

  const CampusGreenZone(this.name, this.kind, this.ring);
}

/// 수목 종류.
enum CampusTreeKind {
  /// 상록 소나무/침엽수 (짙은 에메랄드-포레스트 톤).
  pine,

  /// 느티나무/활엽수 (맑은 내추럴 그린 톤).
  broadleaf,

  /// 완만한 올리브/세이지 톤 활엽수 (숲의 자연스러운 명암 변화).
  olive,

  /// 가로수/정원수 (정돈된 원형 캐노피).
  street,
}

/// 월드 좌표(m)에 배치된 수목 한 그루.
class CampusTree {
  final Offset position;
  final double radiusM;
  final CampusTreeKind kind;
  final int variant;

  const CampusTree({
    required this.position,
    required this.radiusM,
    required this.kind,
    this.variant = 0,
  });
}

/// 정문 로터리 중앙 원형 화단 (campus_roads.json 로터리 원형 도로 중심 실측).
const Offset kRoundaboutCenter = Offset(342.92, 86.69);
const double kRoundaboutIslandRadius = 13.8;

/// 대운동장(400m 트랙 안쪽 천연잔디) 내 규격 축구장 치수 (fac[0]/green[8] 실측 정합).
const Offset kMainStadiumCenter = Offset(616.1, -272.1);
const double kMainStadiumAngle = 0.8915;
const double kMainStadiumPitchLength = 92.0;
const double kMainStadiumPitchWidth = 54.0;

/// 위성사진(Google Earth 실사)을 바탕으로 정리한 한국교원대 캠퍼스 녹지·산림 구역.
///
/// 모든 다각형은 포장면·도로·건물 아래에 깔리므로 도로·광장·건물을 가리지 않고
/// 빈 캠퍼스 대지를 실제 산림·잔디·정원 지형으로 자연스럽게 채운다.
const List<CampusGreenZone> kCampusGreenZones = [
  // ── 1. 상록 소나무숲 (Pine Forest) ──────────────────────────────────
  CampusGreenZone('남쪽 청람산림 서부', CampusGreenKind.pineForest, [
    Offset(145, 212),
    Offset(208, 188),
    Offset(252, 248),
    Offset(322, 238),
    Offset(370, 295),
    Offset(348, 362),
    Offset(292, 355),
    Offset(235, 326),
    Offset(186, 322),
    Offset(138, 266),
  ]),
  CampusGreenZone('남쪽 청람산림 중앙·동부', CampusGreenKind.pineForest, [
    Offset(332, 224),
    Offset(412, 198),
    Offset(478, 214),
    Offset(536, 244),
    Offset(600, 264),
    Offset(652, 270),
    Offset(632, 336),
    Offset(542, 346),
    Offset(476, 398),
    Offset(392, 428),
    Offset(336, 396),
    Offset(318, 314),
  ]),
  CampusGreenZone('서쪽 경계 소나무숲', CampusGreenKind.pineForest, [
    Offset(152, -248),
    Offset(218, -238),
    Offset(242, -132),
    Offset(252, -38),
    Offset(202, 28),
    Offset(174, 112),
    Offset(124, 146),
    Offset(110, 96),
    Offset(144, 18),
    Offset(168, -78),
    Offset(152, -172),
  ]),
  CampusGreenZone('동쪽 능선 소나무숲', CampusGreenKind.pineForest, [
    Offset(748, -82),
    Offset(796, -54),
    Offset(824, 30),
    Offset(830, 164),
    Offset(850, 264),
    Offset(814, 294),
    Offset(736, 294),
    Offset(674, 284),
    Offset(668, 220),
    Offset(724, 182),
    Offset(736, 94),
    Offset(722, 10),
    Offset(750, -32),
  ]),
  CampusGreenZone('북서쪽 연수원·부설고 배후 산림', CampusGreenKind.pineForest, [
    Offset(-180, -340),
    Offset(-115, -520),
    Offset(-20, -695),
    Offset(116, -680),
    Offset(154, -596),
    Offset(166, -492),
    Offset(86, -430),
    Offset(64, -335),
    Offset(42, -256),
    Offset(-110, -258),
  ]),
  CampusGreenZone('북동쪽 기숙사 배후 수림', CampusGreenKind.pineForest, [
    Offset(206, -644),
    Offset(346, -624),
    Offset(486, -644),
    Offset(524, -618),
    Offset(504, -566),
    Offset(426, -526),
    Offset(340, -526),
    Offset(296, -546),
    Offset(230, -546),
  ]),
  CampusGreenZone('대운동장 북동쪽 수림띠', CampusGreenKind.pineForest, [
    Offset(614, -386),
    Offset(686, -322),
    Offset(728, -252),
    Offset(726, -176),
    Offset(696, -166),
    Offset(676, -212),
    Offset(666, -286),
    Offset(610, -346),
  ]),
  CampusGreenZone('남동쪽 테니스장·학군단 남쪽 사면', CampusGreenKind.pineForest, [
    Offset(462, 464),
    Offset(586, 468),
    Offset(696, 430),
    Offset(804, 366),
    Offset(780, 420),
    Offset(656, 496),
    Offset(522, 524),
    Offset(426, 514),
  ]),

  // ── 2. 구릉지 혼효림 (Woodland) ─────────────────────────────────────
  CampusGreenZone('북중앙 청람동산 구릉숲', CampusGreenKind.woodland, [
    Offset(312, -512),
    Offset(396, -506),
    Offset(426, -444),
    Offset(434, -352),
    Offset(474, -266),
    Offset(516, -206),
    Offset(446, -176),
    Offset(366, -180),
    Offset(316, -226),
    Offset(316, -346),
    Offset(316, -440),
  ]),
  CampusGreenZone('대운동장 남서쪽 완경사 구릉', CampusGreenKind.woodland, [
    Offset(486, -254),
    Offset(540, -240),
    Offset(580, -186),
    Offset(550, -156),
    Offset(486, -166),
    Offset(456, -210),
  ]),
  CampusGreenZone('남서쪽 황새생태공원 배후 사면', CampusGreenKind.woodland, [
    Offset(142, 356),
    Offset(206, 426),
    Offset(316, 474),
    Offset(406, 490),
    Offset(366, 540),
    Offset(246, 514),
    Offset(146, 456),
  ]),
  CampusGreenZone('부설고·연수원 사이 경사 녹지', CampusGreenKind.woodland, [
    Offset(196, -334),
    Offset(254, -330),
    Offset(254, -246),
    Offset(196, -246),
  ]),

  // ── 3. 교내 잔디광장·정원·가로 녹지 (Lawn) ──────────────────────────
  CampusGreenZone('정문 진입로 북서 가로녹지', CampusGreenKind.lawn, [
    Offset(-24, 250),
    Offset(244, 118),
    Offset(237, 102),
    Offset(-31, 234),
  ]),
  CampusGreenZone('정문 진입로 남동 가로녹지', CampusGreenKind.lawn, [
    Offset(-14, 274),
    Offset(254, 142),
    Offset(261, 156),
    Offset(-7, 288),
  ]),
  CampusGreenZone('교수회관·미래도서관 원형 정원', CampusGreenKind.lawn, [
    Offset(342, -110),
    Offset(438, -108),
    Offset(442, -40),
    Offset(355, -34),
    Offset(336, -68),
  ]),
  CampusGreenZone('중앙 잔디광장', CampusGreenKind.lawn, [
    Offset(450, -102),
    Offset(528, -98),
    Offset(535, -10),
    Offset(485, 25),
    Offset(442, -15),
  ]),
  CampusGreenZone('자연·응용·음악관 중앙 정원', CampusGreenKind.lawn, [
    Offset(598, 128),
    Offset(634, 112),
    Offset(664, 174),
    Offset(628, 190),
  ]),
  CampusGreenZone('학생회관·미술관 남쪽 정원', CampusGreenKind.lawn, [
    Offset(418, 156),
    Offset(496, 176),
    Offset(476, 214),
    Offset(406, 194),
  ]),
  CampusGreenZone('교원문화관 앞 광장 화단', CampusGreenKind.lawn, [
    Offset(318, 112),
    Offset(362, 102),
    Offset(370, 126),
    Offset(326, 136),
  ]),
  CampusGreenZone('기숙사·대운동장 사이 녹지', CampusGreenKind.lawn, [
    Offset(492, -326),
    Offset(542, -352),
    Offset(558, -320),
    Offset(508, -294),
  ]),
  CampusGreenZone('황새생태연구원 앞 잔디공원', CampusGreenKind.lawn, [
    Offset(236, 412),
    Offset(280, 430),
    Offset(266, 458),
    Offset(222, 440),
  ]),
];

/// 정문 로터리 중앙 원형 화단 다각형.
List<Offset> roundaboutIslandRing([int segments = 24]) => [
      for (var i = 0; i < segments; i++)
        Offset(
          kRoundaboutCenter.dx +
              kRoundaboutIslandRadius * math.cos(i * 2 * math.pi / segments),
          kRoundaboutCenter.dy +
              kRoundaboutIslandRadius * math.sin(i * 2 * math.pi / segments),
        ),
    ];

/// 점이 다각형 안인지 (짝홀 규칙).
bool pointInPolygon(Offset p, List<Offset> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// 점 [p]에서 선분 [a]-[b]까지의 최단 거리 제곱.
double _distToSegSq(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final lenSq = dx * dx + dy * dy;
  if (lenSq < 1e-9) return (p - a).distanceSquared;
  final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq).clamp(0.0, 1.0);
  final px = a.dx + dx * t, py = a.dy + dy * t;
  final ex = p.dx - px, ey = p.dy - py;
  return ex * ex + ey * ey;
}

/// 점 [p]가 다각형 안이거나 변에서 [margin]m 이내인지.
bool _nearPolygon(Offset p, List<Offset> poly, Rect bounds, double margin) {
  if (p.dx < bounds.left - margin ||
      p.dx > bounds.right + margin ||
      p.dy < bounds.top - margin ||
      p.dy > bounds.bottom + margin) {
    return false;
  }
  if (pointInPolygon(p, poly)) return true;
  if (margin <= 0) return false;
  final m2 = margin * margin;
  for (var i = 0; i < poly.length; i++) {
    if (_distToSegSq(p, poly[i], poly[(i + 1) % poly.length]) <= m2) {
      return true;
    }
  }
  return false;
}

Rect _ringBounds(List<Offset> poly) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in poly) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// 결정적 해시(0..1). 호출할 때마다 동일한 수목 배치를 보장한다.
double _hash01(int a, int b, int salt) {
  var h = (a * 374761393 + b * 668265263 + salt * 1442695041) & 0x7FFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF;
  h = h ^ (h >> 16);
  return (h & 0xFFFF) / 65536.0;
}

/// 캠퍼스 내 수목(산림 군락·가로수·로터리 화단·정원수)을 위성사진 기반으로 결정적 생성.
///
/// 모든 수목은 건물·도로·주차장·운동장·코트·수면과 겹치지 않도록 자동 필터링된다.
/// [CampusBase.load] 시 1회 계산되므로 렌더링 중 추가 비용이 없다.
List<CampusTree> generateCampusTrees({
  required List<List<Offset>> campusOutline,
  required List<List<Offset>> buildingRings,
  required List<({String kind, double widthM, List<Offset> points})> osmRoads,
  required List<({Offset center, double length, double width, double angle})>
      courts,
  required List<List<Offset>> sportsFacilities,
  required List<({Offset center, double length, double width, double angle})>
      stallBoxes,
  required List<List<Offset>> waterAreas,
  List<CampusGreenZone> zones = kCampusGreenZones,
}) {
  // 1. 충돌 회피 대상 사전 계산 (바운딩 박스 캐싱)
  final bldChecks = [
    for (final r in buildingRings)
      if (r.length >= 3) (ring: r, bounds: _ringBounds(r)),
  ];
  final facChecks = [
    for (final r in sportsFacilities)
      if (r.length >= 3) (ring: r, bounds: _ringBounds(r)),
  ];
  final waterChecks = [
    for (final r in waterAreas)
      if (r.length >= 3) (ring: r, bounds: _ringBounds(r)),
  ];

  // 도로 선분 + 반폭 + 바운딩 박스
  final roadChecks = <({
    Rect bounds,
    double halfW,
    bool isCar,
    List<Offset> pts,
  })>[];
  for (final r in osmRoads) {
    if (r.points.length < 2) continue;
    final isCar = r.kind == 'road' || r.kind == 'major';
    final hw = osmRoadDrawnHalfWidth(r.kind, r.widthM);
    roadChecks.add((
      bounds: _ringBounds(r.points),
      halfW: hw,
      isCar: isCar,
      pts: r.points,
    ));
  }

  // 코트·주차 상자 체크
  bool inOrientedBox(
    Offset p,
    ({Offset center, double length, double width, double angle}) b,
    double margin,
  ) {
    final c = math.cos(b.angle), s = math.sin(b.angle);
    final dx = p.dx - b.center.dx, dy = p.dy - b.center.dy;
    final u = dx * c + dy * s, v = -dx * s + dy * c;
    return u.abs() <= b.length / 2 + margin && v.abs() <= b.width / 2 + margin;
  }

  final outlinePoly = campusOutline.isNotEmpty ? campusOutline.first : null;
  final outlineBounds =
      outlinePoly != null ? _ringBounds(outlinePoly) : Rect.zero;

  bool isBlocked(Offset p, double rM, {bool allowOutsideCampus = false}) {
    if (!allowOutsideCampus && outlinePoly != null) {
      if (!outlineBounds.contains(p) || !pointInPolygon(p, outlinePoly)) {
        return true;
      }
    }
    final bldMargin = rM * 0.55 + 1.8;
    for (final b in bldChecks) {
      if (_nearPolygon(p, b.ring, b.bounds, bldMargin)) return true;
    }
    for (final f in facChecks) {
      if (_nearPolygon(p, f.ring, f.bounds, 2.5)) return true;
    }
    for (final w in waterChecks) {
      if (_nearPolygon(p, w.ring, w.bounds, 2.0)) return true;
    }
    for (final c in courts) {
      if (inOrientedBox(p, c, 2.5)) return true;
    }
    for (final s in stallBoxes) {
      if (inOrientedBox(p, s, 2.0)) return true;
    }
    for (final rd in roadChecks) {
      final margin = rd.halfW + (rd.isCar ? rM * 0.45 + 1.6 : 1.5);
      if (p.dx < rd.bounds.left - margin ||
          p.dx > rd.bounds.right + margin ||
          p.dy < rd.bounds.top - margin ||
          p.dy > rd.bounds.bottom + margin) {
        continue;
      }
      final m2 = margin * margin;
      for (var i = 0; i + 1 < rd.pts.length; i++) {
        if (_distToSegSq(p, rd.pts[i], rd.pts[i + 1]) <= m2) return true;
      }
    }
    return false;
  }

  // 공간 해시 그리드 (16m 셀)로 수목 간 최소 간격 보장
  const cellM = 16.0;
  final placedGrid = <int, List<CampusTree>>{};
  final trees = <CampusTree>[];

  int cellKey(int cx, int cy) => ((cx + 500) << 12) ^ (cy + 500);

  bool tooClose(Offset p, double minDist) {
    final cx = (p.dx / cellM).floor();
    final cy = (p.dy / cellM).floor();
    final d2 = minDist * minDist;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final bucket = placedGrid[cellKey(cx + dx, cy + dy)];
        if (bucket == null) continue;
        for (final t in bucket) {
          if ((t.position - p).distanceSquared < d2) return true;
        }
      }
    }
    return false;
  }

  void addTree(
    Offset p,
    double radiusM,
    CampusTreeKind kind,
    int variant, {
    double minGap = 6.5,
    bool skipBlocked = false,
    bool allowOutsideCampus = false,
  }) {
    if (!skipBlocked &&
        isBlocked(p, radiusM, allowOutsideCampus: allowOutsideCampus)) {
      return;
    }
    if (tooClose(p, minGap)) return;
    final tree = CampusTree(
      position: p,
      radiusM: radiusM,
      kind: kind,
      variant: variant,
    );
    trees.add(tree);
    final cx = (p.dx / cellM).floor();
    final cy = (p.dy / cellM).floor();
    (placedGrid[cellKey(cx, cy)] ??= []).add(tree);
  }

  // ── A. 정문 로터리 중앙 원형 화단 (부드럽게 뭉친 중앙 수관 클러스터) ──
  addTree(
    kRoundaboutCenter,
    5.4,
    CampusTreeKind.pine,
    0,
    minGap: 1.5,
    skipBlocked: true,
  );
  for (var i = 0; i < 4; i++) {
    final ang = i * math.pi / 2 + 0.4;
    addTree(
      Offset(
        kRoundaboutCenter.dx + 4.4 * math.cos(ang),
        kRoundaboutCenter.dy + 4.4 * math.sin(ang),
      ),
      3.9,
      i.isEven ? CampusTreeKind.pine : CampusTreeKind.broadleaf,
      i,
      minGap: 1.5,
      skipBlocked: true,
    );
  }

  // ── B. 정문 진입로 & 교내 주요 도로 가로수 (여유롭고 정갈한 간격) ─────
  void plantAvenue(
    List<Offset> spine, {
    double spacing = 26.0,
    double offsetM = 7.4,
    double radiusM = 2.6,
    bool allowOutside = false,
  }) {
    var accum = spacing * 0.5;
    for (var i = 0; i + 1 < spine.length; i++) {
      final a = spine[i], b = spine[i + 1];
      final d = b - a;
      final segLen = d.distance;
      if (segLen < 1.0) continue;
      final dir = d / segLen;
      final norm = Offset(-dir.dy, dir.dx);
      var dist = accum;
      while (dist <= segLen) {
        final base = a + dir * dist;
        for (final side in [-1.0, 1.0]) {
          final p = base + norm * (side * offsetM);
          final h = _hash01(p.dx.round(), p.dy.round(), 17);
          addTree(
            p,
            radiusM + (h - 0.5) * 0.4,
            CampusTreeKind.street,
            (h * 4).floor(),
            minGap: 11.0,
            allowOutsideCampus: allowOutside,
          );
        }
        dist += spacing;
      }
      accum = dist - segLen;
    }
  }

  // 정문 진입로 (정문 → 로터리) 양옆 가로수길
  plantAvenue(
    const [Offset(-20, 267), Offset(135, 190), Offset(300, 108)],
    spacing: 24.0,
    offsetM: 7.5,
    radiusM: 2.7,
    allowOutside: true,
  );
  // 중앙 학술대로 (로터리 → 미래도서관 → 교양학관)
  plantAvenue(
    const [Offset(375, 70), Offset(485, 16), Offset(595, -52)],
    spacing: 32.0,
    offsetM: 7.2,
    radiusM: 2.5,
  );

  // ── C. 산림·구릉 구역: 점처럼 흩뿌리지 않고 구름형 숲 군락(Grove)으로 뭉쳐 배치 ──
  //
  // 작은 점을 균일하게 찍으면 도트 무늬처럼 번잡해 보인다. 군락 중심마다
  // 3~5개의 둥근 수관을 겹쳐 놓으면 하나의 부드러운 구름형 숲 덩어리로 합쳐진다.
  for (var zi = 0; zi < zones.length; zi++) {
    final z = zones[zi];
    final bounds = _ringBounds(z.ring);
    final double groveStep;
    switch (z.kind) {
      case CampusGreenKind.pineForest:
        groveStep = 34.0;
      case CampusGreenKind.woodland:
        groveStep = 44.0;
      case CampusGreenKind.lawn:
        groveStep = 48.0;
    }

    var row = 0;
    for (var y = bounds.top + groveStep * 0.4;
        y <= bounds.bottom;
        y += groveStep * 0.88) {
      final rowShift = (row.isOdd ? groveStep * 0.5 : 0.0);
      row++;
      for (var x = bounds.left + rowShift; x <= bounds.right; x += groveStep) {
        final gx = x.round(), gy = y.round();
        final jx = (_hash01(gx, gy, zi * 11 + 1) - 0.5) * groveStep * 0.78;
        final jy = (_hash01(gx, gy, zi * 11 + 2) - 0.5) * groveStep * 0.78;
        final center = Offset(x + jx, y + jy);
        if (!pointInPolygon(center, z.ring)) continue;

        final roll = _hash01(gx, gy, zi * 11 + 3);
        if (z.kind == CampusGreenKind.lawn && roll > 0.35) continue;
        if (z.kind == CampusGreenKind.woodland && roll > 0.65) continue;
        if (z.kind == CampusGreenKind.pineForest && roll > 0.82) continue;

        final speciesRoll = _hash01(gx, gy, zi * 11 + 4);
        final sizeRoll = _hash01(gx, gy, zi * 11 + 5);
        final shapeRoll = _hash01(gx, gy, zi * 11 + 6);
        final CampusTreeKind kind;
        final int lobes;
        final double baseR;
        switch (z.kind) {
          case CampusGreenKind.pineForest:
            kind = speciesRoll < 0.65
                ? CampusTreeKind.pine
                : (speciesRoll < 0.88
                    ? CampusTreeKind.broadleaf
                    : CampusTreeKind.olive);
            // 대칭 네잎클로버 반복을 피하기 위해 크기와 덩어리 구성을 비대칭·불규칙하게 변주
            lobes = shapeRoll < 0.25 ? 1 : (shapeRoll < 0.65 ? 2 : 3);
            baseR = 4.6 + sizeRoll * 5.2;
          case CampusGreenKind.woodland:
            kind = speciesRoll < 0.35
                ? CampusTreeKind.pine
                : (speciesRoll < 0.72
                    ? CampusTreeKind.broadleaf
                    : CampusTreeKind.olive);
            lobes = shapeRoll < 0.4 ? 1 : 2;
            baseR = 4.2 + sizeRoll * 4.4;
          case CampusGreenKind.lawn:
            kind = CampusTreeKind.street;
            lobes = 0;
            baseR = 2.8 + sizeRoll * 1.4;
        }

        // 중심 수관 + 비대칭 보조 수관으로 자연스러운 숲 덩어리 형성
        if (isBlocked(center, baseR)) continue;
        addTree(center, baseR, kind, 0, minGap: 2.5);
        final baseAngle = _hash01(gx, gy, zi * 11 + 19) * math.pi * 2;
        for (var k = 0; k < lobes; k++) {
          final a = baseAngle +
              k * (1.35 + _hash01(gx, gy, zi * 11 + 20 + k) * 1.15);
          final dist =
              baseR * (0.48 + _hash01(gx, gy, zi * 11 + 30 + k) * 0.44);
          final lobePos = Offset(
            center.dx + dist * math.cos(a),
            center.dy + dist * math.sin(a),
          );
          if (!pointInPolygon(lobePos, z.ring)) continue;
          final lobeR =
              baseR * (0.52 + _hash01(gx, gy, zi * 11 + 40 + k) * 0.42);
          addTree(lobePos, lobeR, kind, k + 1, minGap: 2.0);
        }
      }
    }
  }

  // ── D. 주요 정원·광장 포인트 조경수 (절제된 소수 배치) ────────────────
  const signatureTrees = <(Offset, double, CampusTreeKind)>[
    // 교수회관·미래도서관 앞 원형 정원
    (Offset(378, -76), 3.6, CampusTreeKind.broadleaf),
    (Offset(412, -74), 3.5, CampusTreeKind.street),
    // 자연과학관·응용과학관·음악관·제3대학 중앙 정원
    (Offset(614, 134), 3.4, CampusTreeKind.street),
    (Offset(640, 162), 3.4, CampusTreeKind.broadleaf),
    // 대운동장 북서쪽 트랙 입구 수목 클러스터
    (Offset(576, -328), 4.8, CampusTreeKind.pine),
    (Offset(571, -333), 3.9, CampusTreeKind.pine),
  ];
  for (var i = 0; i < signatureTrees.length; i++) {
    final (pos, r, kind) = signatureTrees[i];
    addTree(pos, r, kind, i, minGap: 3.0);
  }

  return trees;
}
