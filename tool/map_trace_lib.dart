// 네이버지도 캡처 → 월드 좌표 추출에 쓰는 공용 루틴.
//
// 좌표계: 월드 x=동쪽(+), y=남쪽(+), 단위 m. 원점 (127.3544, 36.6092).
// 캡처는 정북 기준이라 회전이 없다 → px→월드는 (배율, 평행이동)만 있으면 된다.
//
// 격자를 0.3 m/셀까지 잘게 쓰기 때문에 자료구조가 중요하다:
//  - 마스크는 [Uint8List]다. List<bool>은 VM에서 원소당 8바이트라 2천만 셀에
//    160MB를 먹는다.
//  - 연결요소는 **라벨 배열 하나**로 관리한다. 요소마다 전체 크기 마스크를
//    만들면 100개짜리에 2GB가 필요하다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class Mask {
  final int w, h;
  final Uint8List bits;
  Mask(this.w, this.h) : bits = Uint8List(w * h);
  Mask._(this.w, this.h, this.bits);

  bool at(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && bits[y * w + x] != 0;
  void set(int x, int y) {
    if (x >= 0 && y >= 0 && x < w && y < h) bits[y * w + x] = 1;
  }

  int get count {
    var n = 0;
    for (var i = 0; i < bits.length; i++) {
      if (bits[i] != 0) n++;
    }
    return n;
  }

  Mask clone() => Mask._(w, h, Uint8List.fromList(bits));

  Mask operator &(Mask o) {
    final m = Mask(w, h);
    for (var i = 0; i < bits.length; i++) {
      m.bits[i] = (bits[i] != 0 && o.bits[i] != 0) ? 1 : 0;
    }
    return m;
  }

  Mask operator |(Mask o) {
    final m = Mask(w, h);
    for (var i = 0; i < bits.length; i++) {
      m.bits[i] = (bits[i] != 0 || o.bits[i] != 0) ? 1 : 0;
    }
    return m;
  }

  Mask get inverted {
    final m = Mask(w, h);
    for (var i = 0; i < bits.length; i++) {
      m.bits[i] = bits[i] == 0 ? 1 : 0;
    }
    return m;
  }

  /// [f]배 축소하되 블록의 [minFrac] 이상이 켜져 있을 때만 켠다.
  /// OR 축소와 달리 흩뿌려진 오분류 픽셀이 덩어리로 뭉치지 않는다.
  Mask shrinkMajority(int f, double minFrac) {
    final mw = (w / f).ceil(), mh = (h / f).ceil();
    final m = Mask(mw, mh);
    final need = (f * f * minFrac).ceil();
    final cnt = Int32List(mw * mh);
    for (var y = 0; y < h; y++) {
      final row = y * w, dst = (y ~/ f) * mw;
      for (var x = 0; x < w; x++) {
        if (bits[row + x] != 0) cnt[dst + (x ~/ f)]++;
      }
    }
    for (var i = 0; i < cnt.length; i++) {
      if (cnt[i] >= need) m.bits[i] = 1;
    }
    return m;
  }

  /// 거친 격자를 원래 해상도로 되돌린다.
  Mask upscaleTo(int tw, int th, int f) {
    final o = Mask(tw, th);
    for (var j = 0; j < th; j++) {
      final sy = j ~/ f;
      if (sy >= h) break;
      final src = sy * w, dst = j * tw;
      for (var i = 0; i < tw; i++) {
        final sx = i ~/ f;
        if (sx < w && bits[src + sx] != 0) o.bits[dst + i] = 1;
      }
    }
    return o;
  }
}

// ───────────────────────── 형태학 ─────────────────────────
// 체비쇼프 거리 기준 분리형 연산이라 반지름과 무관하게 O(픽셀수)다.

Mask dilate(Mask m, int r) => _spanY(_spanX(m, r), r);

Mask erode(Mask m, int r) => dilate(m.inverted, r).inverted;

Mask closeM(Mask m, int r) => erode(dilate(m, r), r);

Mask openM(Mask m, int r) => dilate(erode(m, r), r);

Mask _spanX(Mask m, int r) {
  final o = Mask(m.w, m.h);
  for (var y = 0; y < m.h; y++) {
    final row = y * m.w;
    var last = -1 << 30;
    for (var x = 0; x < m.w; x++) {
      if (m.bits[row + x] != 0) last = x;
      if (x - last <= r) o.bits[row + x] = 1;
    }
    last = 1 << 30;
    for (var x = m.w - 1; x >= 0; x--) {
      if (m.bits[row + x] != 0) last = x;
      if (last - x <= r) o.bits[row + x] = 1;
    }
  }
  return o;
}

Mask _spanY(Mask m, int r) {
  final o = Mask(m.w, m.h);
  for (var x = 0; x < m.w; x++) {
    var last = -1 << 30;
    for (var y = 0; y < m.h; y++) {
      if (m.bits[y * m.w + x] != 0) last = y;
      if (y - last <= r) o.bits[y * m.w + x] = 1;
    }
    last = 1 << 30;
    for (var y = m.h - 1; y >= 0; y--) {
      if (m.bits[y * m.w + x] != 0) last = y;
      if (last - y <= r) o.bits[y * m.w + x] = 1;
    }
  }
  return o;
}

/// 마스크의 구멍(테두리와 이어지지 않은 배경)을 메운다.
Mask fillHoles(Mask m) {
  final outside = Uint8List(m.w * m.h);
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= m.w || y >= m.h) return;
    final i = y * m.w + x;
    if (m.bits[i] != 0 || outside[i] != 0) return;
    outside[i] = 1;
    stack.add(i);
  }

  for (var x = 0; x < m.w; x++) {
    push(x, 0);
    push(x, m.h - 1);
  }
  for (var y = 0; y < m.h; y++) {
    push(0, y);
    push(m.w - 1, y);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % m.w, y = p ~/ m.w;
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }
  final o = Mask(m.w, m.h);
  for (var i = 0; i < m.bits.length; i++) {
    o.bits[i] = (m.bits[i] != 0 || outside[i] == 0) ? 1 : 0;
  }
  return o;
}

// ───────────────────────── 연결요소 ─────────────────────────

/// 라벨 배열 하나로 표현한 연결요소들. 요소마다 전체 마스크를 만들지 않는다.
class Labeling {
  final int w, h;

  /// 0 = 없음, 1..[count] = 요소 번호.
  final Int32List labels;
  final List<int> area = [];
  final List<int> minX = [], minY = [], maxX = [], maxY = [];
  Labeling(this.w, this.h) : labels = Int32List(w * h);
  int get count => area.length;

  /// [id]번 요소를 제 경계상자 크기로 오려낸 마스크. 여백 [pad]셀.
  Mask crop(int id, {int pad = 0}) {
    final i = id - 1;
    final x0 = math.max(0, minX[i] - pad), y0 = math.max(0, minY[i] - pad);
    final x1 = math.min(w - 1, maxX[i] + pad), y1 = math.min(h - 1, maxY[i] + pad);
    final m = Mask(x1 - x0 + 1, y1 - y0 + 1);
    for (var y = y0; y <= y1; y++) {
      final src = y * w, dst = (y - y0) * m.w;
      for (var x = x0; x <= x1; x++) {
        if (labels[src + x] == id) m.bits[dst + (x - x0)] = 1;
      }
    }
    return m;
  }

  /// [crop]으로 얻은 마스크의 (0,0)이 전체 격자에서 놓이는 자리.
  List<int> cropOrigin(int id, {int pad = 0}) => [
        math.max(0, minX[id - 1] - pad),
        math.max(0, minY[id - 1] - pad),
      ];
}

/// 4-이웃 연결요소. [minArea]보다 작은 덩어리는 라벨을 지운다.
Labeling label4(Mask m, {int minArea = 1}) {
  final L = Labeling(m.w, m.h);
  final stack = <int>[];
  final drop = <int>[];
  var next = 0;
  for (var s = 0; s < m.bits.length; s++) {
    if (m.bits[s] == 0 || L.labels[s] != 0) continue;
    next++;
    L.labels[s] = next;
    stack
      ..clear()
      ..add(s);
    var area = 0;
    var mnx = m.w, mxx = -1, mny = m.h, mxy = -1;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % m.w, y = p ~/ m.w;
      area++;
      if (x < mnx) mnx = x;
      if (x > mxx) mxx = x;
      if (y < mny) mny = y;
      if (y > mxy) mxy = y;
      void probe(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= m.w || ny >= m.h) return;
        final i = ny * m.w + nx;
        if (m.bits[i] == 0 || L.labels[i] != 0) return;
        L.labels[i] = next;
        stack.add(i);
      }

      probe(x + 1, y);
      probe(x - 1, y);
      probe(x, y + 1);
      probe(x, y - 1);
    }
    L.area.add(area);
    L.minX.add(mnx);
    L.maxX.add(mxx);
    L.minY.add(mny);
    L.maxY.add(mxy);
    if (area < minArea) drop.add(next);
  }
  if (drop.isNotEmpty) {
    final kill = Uint8List(next + 1);
    for (final d in drop) {
      kill[d] = 1;
    }
    for (var i = 0; i < L.labels.length; i++) {
      if (L.labels[i] != 0 && kill[L.labels[i]] != 0) L.labels[i] = 0;
    }
  }
  return L;
}

/// 씨앗 라벨을 [域] 안으로 넓혀 영역을 남김없이 나눠 갖는다 (다중 시작 BFS).
///
/// 건물을 뗄 때 쓴다. 요소마다 따로 부풀리면 옆 동과 **겹쳐서** 지도에 건물이
/// 포개져 보인다. 여기서는 한 셀이 한 라벨에만 속하므로 겹칠 수가 없다.
void growInto(Labeling L, Mask domain) {
  final q = <int>[];
  for (var i = 0; i < L.labels.length; i++) {
    if (L.labels[i] != 0) q.add(i);
  }
  var head = 0;
  while (head < q.length) {
    final p = q[head++];
    final lab = L.labels[p];
    final x = p % L.w, y = p ~/ L.w;
    void probe(int nx, int ny) {
      if (nx < 0 || ny < 0 || nx >= L.w || ny >= L.h) return;
      final i = ny * L.w + nx;
      if (domain.bits[i] == 0 || L.labels[i] != 0) return;
      L.labels[i] = lab;
      q.add(i);
      final k = lab - 1;
      L.area[k]++;
      if (nx < L.minX[k]) L.minX[k] = nx;
      if (nx > L.maxX[k]) L.maxX[k] = nx;
      if (ny < L.minY[k]) L.minY[k] = ny;
      if (ny > L.maxY[k]) L.maxY[k] = ny;
    }

    probe(x + 1, y);
    probe(x - 1, y);
    probe(x, y + 1);
    probe(x, y - 1);
  }
}

// ───────────────────────── 외곽선 ─────────────────────────

const _nb8 = [
  [1, 0], [1, 1], [0, 1], [-1, 1],
  [-1, 0], [-1, -1], [0, -1], [1, -1],
];

/// Moore 이웃 추적. 마스크에서 가장 위·왼쪽 점부터 시계방향으로 돈다.
List<List<int>> contour(Mask m) {
  var sx = -1, sy = -1;
  outer:
  for (var y = 0; y < m.h; y++) {
    for (var x = 0; x < m.w; x++) {
      if (m.bits[y * m.w + x] != 0) {
        sx = x;
        sy = y;
        break outer;
      }
    }
  }
  if (sx < 0) return [];
  final out = <List<int>>[];
  var cx = sx, cy = sy, dir = 6;
  for (var guard = 0; guard < 2000000; guard++) {
    out.add([cx, cy]);
    var found = false;
    for (var k = 0; k < 8; k++) {
      final d = (dir + 6 + k) % 8;
      final nx = cx + _nb8[d][0], ny = cy + _nb8[d][1];
      if (m.at(nx, ny)) {
        cx = nx;
        cy = ny;
        dir = d;
        found = true;
        break;
      }
    }
    if (!found) break;
    if (cx == sx && cy == sy && out.length > 2) break;
  }
  return out;
}

class Pt {
  final double x, y;
  const Pt(this.x, this.y);
}

double polyArea(List<Pt> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

List<Pt> polyCenterBox(List<Pt> r) {
  var mnx = 1e9, mxx = -1e9, mny = 1e9, mxy = -1e9;
  for (final p in r) {
    mnx = math.min(mnx, p.x);
    mxx = math.max(mxx, p.x);
    mny = math.min(mny, p.y);
    mxy = math.max(mxy, p.y);
  }
  return [Pt((mnx + mxx) / 2, (mny + mxy) / 2), Pt(mxx - mnx, mxy - mny)];
}

List<Pt> simplify(List<Pt> pts, double eps) {
  if (pts.length < 3) return pts;
  final keep = Uint8List(pts.length);
  keep[0] = 1;
  keep[pts.length - 1] = 1;
  final stack = <List<int>>[
    [0, pts.length - 1]
  ];
  while (stack.isNotEmpty) {
    final s = stack.removeLast();
    final a = pts[s[0]], b = pts[s[1]];
    var best = -1.0, bi = -1;
    final dx = b.x - a.x, dy = b.y - a.y;
    final den = math.sqrt(dx * dx + dy * dy);
    for (var i = s[0] + 1; i < s[1]; i++) {
      final p = pts[i];
      final d = den < 1e-9
          ? math.sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y))
          : ((dx * (a.y - p.y) - (a.x - p.x) * dy).abs() / den);
      if (d > best) {
        best = d;
        bi = i;
      }
    }
    if (best > eps && bi > 0) {
      keep[bi] = 1;
      stack
        ..add([s[0], bi])
        ..add([bi, s[1]]);
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i] != 0) pts[i]
  ];
}

bool pip(List<Pt> poly, double x, double y) {
  var c = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.y > y) != (b.y > y) &&
        x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
      c = !c;
    }
  }
  return c;
}

/// 다각형들을 [w]x[h] 격자에 채운다. 격자 (i,j) = 월드 (ox+i*res, oy+j*res).
Mask rasterize(List<List<List<double>>> polys, int w, int h, double ox,
    double oy, double res) {
  final m = Mask(w, h);
  for (final ring in polys) {
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in ring) {
      minY = math.min(minY, p[1]);
      maxY = math.max(maxY, p[1]);
    }
    final j0 = math.max(0, ((minY - oy) / res).floor());
    final j1 = math.min(h - 1, ((maxY - oy) / res).ceil());
    for (var j = j0; j <= j1; j++) {
      final yw = oy + j * res;
      final xs = <double>[];
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], b = ring[(i + 1) % ring.length];
        if ((a[1] <= yw) != (b[1] <= yw)) {
          xs.add(a[0] + (yw - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final i0 = math.max(0, ((xs[k] - ox) / res).ceil());
        final i1 = math.min(w - 1, ((xs[k + 1] - ox) / res).floor());
        for (var i = i0; i <= i1; i++) {
          m.bits[j * w + i] = 1;
        }
      }
    }
  }
  return m;
}

bool near(img.Pixel p, int r, int g, int b, int tol) =>
    (p.r - r).abs() <= tol && (p.g - g).abs() <= tol && (p.b - b).abs() <= tol;

/// campus_base.json 로드.
Map<String, dynamic> loadBase() =>
    jsonDecode(File('assets/housing/campus_base.json').readAsStringSync());

// ───────────────────── 매끈한 경계 추출 ─────────────────────
//
// [contour]는 셀 한가운데를 잇는 계단 모양을 낸다. 0.3m 격자라도 도로 가장자리가
// 삐죽삐죽해 보이는 이유다. 여기서는 마스크를 흐린 뒤 **0.5 등고선**을 따서
// 셀 사이를 보간한 점을 얻는다. 실제 도로처럼 곡선이 살아난다.

/// 이진 마스크를 실수 밭으로 바꿔 [passes]번 상자흐림한다.
/// 반지름 [r] 상자흐림을 여러 번 하면 가우시안에 수렴한다.
Float32List blurField(Mask m, int r, int passes) {
  var f = Float32List(m.w * m.h);
  for (var i = 0; i < f.length; i++) {
    f[i] = m.bits[i].toDouble();
  }
  final tmp = Float32List(f.length);
  for (var p = 0; p < passes; p++) {
    // 가로
    for (var y = 0; y < m.h; y++) {
      final row = y * m.w;
      var sum = 0.0;
      for (var x = 0; x <= r && x < m.w; x++) {
        sum += f[row + x];
      }
      for (var x = 0; x < m.w; x++) {
        final lo = x - r, hi = x + r;
        tmp[row + x] = sum / (math.min(hi, m.w - 1) - math.max(lo, 0) + 1);
        if (hi + 1 < m.w) sum += f[row + hi + 1];
        if (lo >= 0) sum -= f[row + lo];
      }
    }
    // 세로
    for (var x = 0; x < m.w; x++) {
      var sum = 0.0;
      for (var y = 0; y <= r && y < m.h; y++) {
        sum += tmp[y * m.w + x];
      }
      for (var y = 0; y < m.h; y++) {
        final lo = y - r, hi = y + r;
        f[y * m.w + x] = sum / (math.min(hi, m.h - 1) - math.max(lo, 0) + 1);
        if (hi + 1 < m.h) sum += tmp[(hi + 1) * m.w + x];
        if (lo >= 0) sum -= tmp[lo * m.w + x];
      }
    }
  }
  return f;
}

/// 마칭 스퀘어. [f]의 [level] 등고선을 닫힌 고리들로 낸다.
/// 좌표는 셀 단위(실수)라 계단이 아니라 보간된 위치다.
List<List<Pt>> marchingSquares(Float32List f, int w, int h, double level) {
  // 격자 변마다 번호를 붙여 교차점을 한 번만 만든다. 그래야 조각을 이을 때
  // 부동소수 비교 없이 정확히 맞물린다.
  final pos = <int, Pt>{};
  // 조각(segment) 목록과, 마디마다 닿아 있는 조각 번호.
  // 마디가 아니라 **조각**을 따라 걸어야 한다. 등고선이 대각선으로 맞물리는
  // 자리에서는 한 마디에 조각이 넷 붙는데, 마디를 소비하며 걸으면 거기서
  // 고리가 끊겨 부지 경계가 조각조각 났다.
  final segs = <List<int>>[];
  final adj = <int, List<int>>{};
  double v(int x, int y) => f[y * w + x];
  int hid(int x, int y) => (y * w + x) * 2;
  int vid(int x, int y) => (y * w + x) * 2 + 1;

  Pt lerpH(int x, int y) {
    final a = v(x, y), b = v(x + 1, y);
    final t = (level - a) / (b - a);
    return Pt(x + t.clamp(0.0, 1.0), y.toDouble());
  }

  Pt lerpV(int x, int y) {
    final a = v(x, y), b = v(x, y + 1);
    final t = (level - a) / (b - a);
    return Pt(x.toDouble(), y + t.clamp(0.0, 1.0));
  }

  void link(int e1, Pt p1, int e2, Pt p2) {
    pos[e1] = p1;
    pos[e2] = p2;
    final id = segs.length;
    segs.add([e1, e2]);
    (adj[e1] ??= []).add(id);
    (adj[e2] ??= []).add(id);
  }

  for (var y = 0; y < h - 1; y++) {
    for (var x = 0; x < w - 1; x++) {
      final a = v(x, y) > level, b = v(x + 1, y) > level;
      final c = v(x + 1, y + 1) > level, d = v(x, y + 1) > level;
      var idx = (a ? 1 : 0) | (b ? 2 : 0) | (c ? 4 : 0) | (d ? 8 : 0);
      if (idx == 0 || idx == 15) continue;
      final top = hid(x, y), bottom = hid(x, y + 1);
      final left = vid(x, y), right = vid(x + 1, y);
      Pt pt() => lerpH(x, y);
      Pt pb() => lerpH(x, y + 1);
      Pt pl() => lerpV(x, y);
      Pt pr() => lerpV(x + 1, y);
      // 안장(5, 10)은 네 모서리 평균으로 어느 쪽이 이어지는지 정한다
      if (idx == 5 || idx == 10) {
        final mid = (v(x, y) + v(x + 1, y) + v(x + 1, y + 1) + v(x, y + 1)) / 4;
        final joined = mid > level;
        if (idx == 5) {
          if (joined) {
            link(left, pl(), top, pt());
            link(right, pr(), bottom, pb());
          } else {
            link(top, pt(), right, pr());
            link(bottom, pb(), left, pl());
          }
        } else {
          if (joined) {
            link(top, pt(), right, pr());
            link(bottom, pb(), left, pl());
          } else {
            link(left, pl(), top, pt());
            link(right, pr(), bottom, pb());
          }
        }
        continue;
      }
      switch (idx) {
        case 1:
        case 14:
          link(left, pl(), top, pt());
          break;
        case 2:
        case 13:
          link(top, pt(), right, pr());
          break;
        case 3:
        case 12:
          link(left, pl(), right, pr());
          break;
        case 4:
        case 11:
          link(right, pr(), bottom, pb());
          break;
        case 6:
        case 9:
          link(top, pt(), bottom, pb());
          break;
        case 7:
        case 8:
          link(bottom, pb(), left, pl());
          break;
      }
    }
  }

  final done = Uint8List(segs.length);
  final loops = <List<Pt>>[];
  for (var s0 = 0; s0 < segs.length; s0++) {
    if (done[s0] != 0) continue;
    final startNode = segs[s0][0];
    var cur = startNode;
    final loop = <Pt>[];
    while (true) {
      var pick = -1;
      for (final sid in adj[cur]!) {
        if (done[sid] == 0) {
          pick = sid;
          break;
        }
      }
      if (pick < 0) break;
      done[pick] = 1;
      loop.add(pos[cur]!);
      cur = segs[pick][0] == cur ? segs[pick][1] : segs[pick][0];
      if (cur == startNode) break;
    }
    if (loop.length >= 8) loops.add(loop);
  }
  return loops;
}

/// 차이킨 모서리 깎기. 닫힌 고리를 부드럽게 만든다.
List<Pt> chaikin(List<Pt> pts, int iters) {
  var cur = pts;
  for (var k = 0; k < iters; k++) {
    final out = <Pt>[];
    for (var i = 0; i < cur.length; i++) {
      final a = cur[i], b = cur[(i + 1) % cur.length];
      out.add(Pt(a.x * 0.75 + b.x * 0.25, a.y * 0.75 + b.y * 0.25));
      out.add(Pt(a.x * 0.25 + b.x * 0.75, a.y * 0.25 + b.y * 0.75));
    }
    cur = out;
  }
  return cur;
}

/// 마스크 경계를 매끈한 폴리곤으로. 좌표는 셀 단위.
///
/// [blurR]·[blurN]으로 흐린 정도를, [round]로 모서리를 얼마나 둥글릴지 정한다.
/// 건물은 각이 살아야 하니 [round]를 0으로 두고, 도로·운동장처럼 실제로
/// 곡선인 것은 2쯤 준다.
List<List<Pt>> traceSmooth(
  Mask m, {
  int blurR = 2,
  int blurN = 2,
  int round = 2,
  double preEps = 0.55,
  double postEps = 0.30,
  int minPts = 8,
  double minLoopArea = 0,
}) {
  // 도형이 마스크 테두리에 닿아 있으면 등고선이 닫히지 못해 고리가 조각난다.
  // (교원대 부지가 딱 그랬다 — 84ha 한 덩어리가 17ha짜리 네 조각으로 나왔다)
  // 항상 빈 여백을 둘러서 닫히게 만든다.
  final b = blurR * blurN + 2;
  final pm = Mask(m.w + b * 2, m.h + b * 2);
  for (var y = 0; y < m.h; y++) {
    final src = y * m.w, dst = (y + b) * pm.w + b;
    for (var x = 0; x < m.w; x++) {
      pm.bits[dst + x] = m.bits[src + x];
    }
  }
  final f = blurField(pm, blurR, blurN);
  final loops = marchingSquares(f, pm.w, pm.h, 0.5);
  final out = <List<Pt>>[];
  for (final l0 in loops) {
    final l = [for (final p in l0) Pt(p.x - b, p.y - b)];
    var p = simplify(l, preEps);
    if (p.length < 4) continue;
    if (round > 0) p = simplify(chaikin(p, round), postEps);
    if (p.length >= minPts && polyArea(p) >= minLoopArea) out.add(p);
  }
  out.sort((a, b) => polyArea(b).compareTo(polyArea(a)));
  return out;
}

// ───────────────────── 건물 외곽 직각화 ─────────────────────
//
// 등고선을 그대로 쓰면 건물이 흐물흐물하다. 특히 붙어 있는 두 동 사이는
// 물확산으로 나눈 자리라 경계가 지그재그다(둘레²/면적 지수가 300까지 나왔다).
// 실제 건물은 거의 직각이므로, 주 방향을 찾아 변을 거기에 맞춰 세운다.

/// [poly]의 주 방향(라디안, 0~π/2). 변 길이로 가중한 4배각 평균이라
/// 90° 회전에 불변이다.
double dominantAngle(List<Pt> poly) {
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.4) continue;
    final ang = math.atan2(dy, dx);
    sx += len * math.cos(4 * ang);
    sy += len * math.sin(4 * ang);
  }
  if (sx == 0 && sy == 0) return 0;
  return math.atan2(sy, sx) / 4;
}

class _Line {
  double dx, dy; // 단위 방향
  double px, py; // 지나는 점
  double w; // 길이 가중치
  _Line(this.dx, this.dy, this.px, this.py, this.w);
}

/// 건물 외곽을 직각 형태로 다듬는다.
///
/// [snapDeg] 안쪽으로 주 방향(또는 그 직각)에 가까운 변은 그 방향으로 세운다.
/// 그보다 많이 틀어진 변은 비스듬한 건물일 수 있으니 원래 방향을 둔다.
/// 결과 면적이 [maxAreaDrift] 넘게 달라지면 손대지 않은 원본을 돌려준다 —
/// 이상한 모양을 억지로 만드는 것보다 낫다.
List<Pt> regularize(
  List<Pt> poly, {
  double snapDeg = 32,
  double minEdge = 1.4,
  double maxAreaDrift = 0.28,
}) {
  regularizeTried++;
  if (poly.length < 4) return poly;
  final theta = dominantAngle(poly);
  final snapRad = snapDeg * math.pi / 180;

  // 1) 변마다 방향을 정한다
  final lines = <_Line>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    var ang = math.atan2(dy, dx);
    final k = ((ang - theta) / (math.pi / 2)).round();
    final target = theta + k * math.pi / 2;
    var diff = ang - target;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    if (diff.abs() <= snapRad) ang = target;
    lines.add(_Line(math.cos(ang), math.sin(ang), (a.x + b.x) / 2,
        (a.y + b.y) / 2, len));
  }
  if (lines.length < 4) return poly;

  // 2) 이어지는 같은 방향 변을 하나로 합친다 (길이 가중 평균 위치)
  List<_Line> mergeRun(List<_Line> src) {
    final out = <_Line>[];
    for (final l in src) {
      if (out.isNotEmpty) {
        final p = out.last;
        final cross = (p.dx * l.dy - p.dy * l.dx).abs();
        // 나란하고, 두 선이 실제로 같은 직선 위에 있을 때만 합친다
        final off = ((l.px - p.px) * -p.dy + (l.py - p.py) * p.dx).abs();
        if (cross < 0.05 && off < 1.2) {
          final w = p.w + l.w;
          p.px = (p.px * p.w + l.px * l.w) / w;
          p.py = (p.py * p.w + l.py * l.w) / w;
          p.w = w;
          continue;
        }
      }
      out.add(l);
    }
    // 고리이므로 처음과 끝도 검사
    while (out.length > 4) {
      final f = out.first, e = out.last;
      final cross = (e.dx * f.dy - e.dy * f.dx).abs();
      final off = ((f.px - e.px) * -e.dy + (f.py - e.py) * e.dx).abs();
      if (cross >= 0.05 || off >= 1.2) break;
      final w = f.w + e.w;
      f.px = (f.px * f.w + e.px * e.w) / w;
      f.py = (f.py * f.w + e.py * e.w) / w;
      f.w = w;
      out.removeLast();
    }
    return out;
  }

  var ls = mergeRun(lines);
  if (ls.length < 4) return poly;

  // 3) 이웃한 두 직선의 교점이 꼭짓점이 된다
  List<Pt>? cornersOf(List<_Line> src) {
    final out = <Pt>[];
    for (var i = 0; i < src.length; i++) {
      final a = src[i], b = src[(i + 1) % src.length];
      final den = a.dx * b.dy - a.dy * b.dx;
      if (den.abs() < 1e-4) return null; // 나란한 이웃 → 포기
      final t = ((b.px - a.px) * b.dy - (b.py - a.py) * b.dx) / den;
      out.add(Pt(a.px + a.dx * t, a.py + a.dy * t));
    }
    return out;
  }

  // 나란한 이웃이 생기면 교점이 없다. 그때 통째로 포기하면 **물결치거나
  // 톱니진 원본이 그대로 나간다.** 나란한 이웃은 둘 중 하나가 군더더기이므로
  // (같은 방향인데 사이에 잇는 변이 없다) 짧은 쪽을 빼고 다시 구한다.
  //
  // 이 처리가 [cornersOf]를 부르는 **모든 자리**에 필요하다. 예전엔 맨 처음
  // 한 번만 했는데, 짧은 변을 걷어내는 4)에서 훨씬 자주 터진다 — 계단은
  // 0°/90°가 번갈아 나와서 하나 걸러 지우면 남은 직선이 전부 나란해지기
  // 때문이다. 거기서 break로 빠져나가는 바람에 minEdge가 계단에 대해
  // 아예 안 먹었다(1.0이든 2.5든 결과가 똑같았던 이유).
  List<_Line>? resolved;
  List<Pt>? solve(List<_Line> src) {
    var cur = src;
    for (var guard = 0; guard < 80; guard++) {
      final got = cornersOf(cur);
      if (got != null) {
        resolved = cur;
        return got;
      }
      if (cur.length <= 4) return null;
      var drop = -1;
      var dropW = double.infinity;
      for (var i = 0; i < cur.length; i++) {
        final a = cur[i], b = cur[(i + 1) % cur.length];
        if ((a.dx * b.dy - a.dy * b.dx).abs() >= 1e-4) continue;
        final j = (i + 1) % cur.length;
        final cand = a.w <= b.w ? i : j;
        if (cur[cand].w < dropW) {
          dropW = cur[cand].w;
          drop = cand;
        }
      }
      if (drop < 0) return null;
      cur = [...cur]..removeAt(drop);
    }
    return null;
  }

  var pts = solve(ls);
  if (pts == null) {
    regularizeNoCorners++;
    return poly;
  }
  ls = resolved!;

  // 4) 너무 짧은 변은 그 직선을 빼고 다시 계산한다.
  //
  // 한 번에 하나씩 빼면 어림도 없다 — 물확산 경계의 지그재그는 짧은 변이
  // 수십 개라서 통째로 걷어내야 한다. 대신 이웃한 두 개를 같은 판에
  // 빼면 도형이 무너지므로 하나 걸러 하나씩 뺀다.
  for (var pass = 0; pass < 40; pass++) {
    if (ls.length <= 4) break;
    final kill = <int>[];
    var lastKilled = -9;
    for (var i = 0; i < pts!.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final len = math.sqrt(
          (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
      if (len >= minEdge) continue;
      final idx = (i + 1) % ls.length;
      if (idx == lastKilled + 1 || idx == lastKilled) continue;
      kill.add(idx);
      lastKilled = idx;
    }
    if (kill.isEmpty) break;
    kill.sort((a, b) => b.compareTo(a));
    final next = [...ls];
    for (final k in kill) {
      if (next.length <= 4) break;
      next.removeAt(k);
    }
    final np = solve(next);
    if (np == null) break;
    ls = resolved!;
    pts = np;
  }

  final before = polyArea(poly), after = polyArea(pts!);
  if (before <= 0 || (after - before).abs() / before > maxAreaDrift) {
    regularizeGaveUp++;
    return poly;
  }
  return pts;
}

/// 폴리곤의 굽이를 펴서 곧은 구간을 곧게 만든다.
///
/// [regularize]와 달리 90°로 세우지 않는다. 도로는 직각이 아니라 제멋대로
/// 각도의 **곧은 구간 + 진짜 곡선**으로 이뤄져 있기 때문이다.
///
/// 흐린 뒤 등고선을 따면 래스터의 ±1셀 잡음이 매끈한 **물결**로 바뀐다.
/// 도로가 흐물흐물해 보이던 정체가 그거다. 여기서는 방향이 [mergeDeg] 안쪽으로
/// 비슷한 이웃 변을 한 직선으로 합쳐 잡음을 없애고, 그보다 크게 꺾이는 곳
/// (진짜 모서리·곡선)은 그대로 둔다.
List<Pt> straighten(
  List<Pt> poly, {
  double mergeDeg = 11,
  double maxOffset = 1.1,
  double minEdge = 1.6,
  double maxAreaDrift = 0.15,
}) {
  straightenTried++;
  if (poly.length < 5) return poly;
  final mergeRad = mergeDeg * math.pi / 180;

  var lines = <_Line>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    lines.add(_Line(dx / len, dy / len, (a.x + b.x) / 2, (a.y + b.y) / 2, len));
  }
  if (lines.length < 5) return poly;

  bool tryMerge(_Line p, _Line l) {
    final dot = (p.dx * l.dx + p.dy * l.dy).clamp(-1.0, 1.0);
    if (math.acos(dot.abs()) > mergeRad) return false;
    // 두 변이 같은 직선 위에 있어야 한다 — 나란하기만 한 반대편 변까지
    // 합치면 도형이 무너진다.
    if (((l.px - p.px) * -p.dy + (l.py - p.py) * p.dx).abs() > maxOffset) {
      return false;
    }
    final w = p.w + l.w;
    // 길이로 가중해 방향과 위치를 섞는다. 짧은 잡음 변이 긴 직선을 못 흔든다.
    final sign = dot < 0 ? -1.0 : 1.0;
    final nx = p.dx * p.w + l.dx * l.w * sign;
    final ny = p.dy * p.w + l.dy * l.w * sign;
    final nl = math.sqrt(nx * nx + ny * ny);
    if (nl < 1e-9) return false;
    p.dx = nx / nl;
    p.dy = ny / nl;
    p.px = (p.px * p.w + l.px * l.w) / w;
    p.py = (p.py * p.w + l.py * l.w) / w;
    p.w = w;
    return true;
  }

  // 여러 번 훑는다 — 합치고 나면 새로 이웃이 된 변끼리 또 합쳐질 수 있다.
  for (var pass = 0; pass < 4; pass++) {
    final out = <_Line>[];
    var changed = false;
    for (final l in lines) {
      if (out.isNotEmpty && tryMerge(out.last, l)) {
        changed = true;
        continue;
      }
      out.add(l);
    }
    while (out.length > 4 && tryMerge(out.first, out.last)) {
      out.removeLast();
      changed = true;
    }
    lines = out;
    if (!changed || lines.length < 5) break;
  }
  if (lines.length < 4) return poly;

  List<Pt>? cornersOf(List<_Line> src) {
    final out = <Pt>[];
    for (var i = 0; i < src.length; i++) {
      final a = src[i], b = src[(i + 1) % src.length];
      final den = a.dx * b.dy - a.dy * b.dx;
      if (den.abs() < 5e-3) return null;
      final t = ((b.px - a.px) * b.dy - (b.py - a.py) * b.dx) / den;
      out.add(Pt(a.px + a.dx * t, a.py + a.dy * t));
    }
    return out;
  }

  var pts = cornersOf(lines);
  if (pts == null) return poly;

  for (var pass = 0; pass < 30; pass++) {
    if (lines.length <= 5) break;
    final kill = <int>[];
    var last = -9;
    for (var i = 0; i < pts!.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final len =
          math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
      if (len >= minEdge) continue;
      final idx = (i + 1) % lines.length;
      if (idx == last || idx == last + 1) continue;
      kill.add(idx);
      last = idx;
    }
    if (kill.isEmpty) break;
    kill.sort((a, b) => b.compareTo(a));
    final next = [...lines];
    for (final k in kill) {
      if (next.length <= 5) break;
      next.removeAt(k);
    }
    final np = cornersOf(next);
    if (np == null) break;
    lines = next;
    pts = np;
  }

  final before = polyArea(poly), after = polyArea(pts!);
  if (before <= 0 || (after - before).abs() / before > maxAreaDrift) {
    straightenGaveUp++;
    return poly;
  }
  return pts;
}

/// 꺾인 자리만 살짝 둥글린다. 곧은 구간은 건드리지 않는다.
///
/// [minTurn]도보다 덜 꺾인 자리는 그냥 둔다. 안 그러면 거의 곧은 구간에서도
/// 점이 둘로 갈라져 **굽이처럼 보인다** — 점 수만 두 배가 되고 지그재그율이
/// 올라간다. 실제로 그 때문에 도로가 구불구불해 보였다.
List<Pt> roundCorners(List<Pt> poly,
    {int iters = 1, double maxCut = 1.6, double minTurn = 25}) {
  var cur = poly;
  final minRad = minTurn * math.pi / 180;
  for (var k = 0; k < iters; k++) {
    final out = <Pt>[];
    for (var i = 0; i < cur.length; i++) {
      final p = cur[(i - 1 + cur.length) % cur.length];
      final c = cur[i];
      final n = cur[(i + 1) % cur.length];
      final l1 = math.sqrt((c.x - p.x) * (c.x - p.x) + (c.y - p.y) * (c.y - p.y));
      final l2 = math.sqrt((n.x - c.x) * (n.x - c.x) + (n.y - c.y) * (n.y - c.y));
      if (l1 < 1e-6 || l2 < 1e-6) {
        out.add(c);
        continue;
      }
      final dot = (((c.x - p.x) * (n.x - c.x) + (c.y - p.y) * (n.y - c.y)) /
              (l1 * l2))
          .clamp(-1.0, 1.0);
      if (math.acos(dot) < minRad) {
        out.add(c);
        continue;
      }
      // 자를 길이는 짧은 쪽 변의 1/3, 최대 maxCut 미터까지
      final cut = math.min(maxCut, math.min(l1, l2) / 3);
      out.add(Pt(c.x + (p.x - c.x) / l1 * cut, c.y + (p.y - c.y) / l1 * cut));
      out.add(Pt(c.x + (n.x - c.x) / l2 * cut, c.y + (n.y - c.y) / l2 * cut));
    }
    cur = out;
  }
  return cur;
}

/// 3x3 중앙값 필터. JPEG 링잉을 걷어내되 244/248 같은 미세한 경계는 살린다.
/// (평균 필터는 그 경계를 뭉개서 오히려 해가 된다)
img.Image medianFilter3(img.Image src) {
  final out = img.Image.from(src);
  final r = List<int>.filled(9, 0), g = List<int>.filled(9, 0);
  final b = List<int>.filled(9, 0);
  for (var y = 1; y < src.height - 1; y++) {
    for (var x = 1; x < src.width - 1; x++) {
      var k = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final p = src.getPixel(x + dx, y + dy);
          r[k] = p.r.toInt();
          g[k] = p.g.toInt();
          b[k] = p.b.toInt();
          k++;
        }
      }
      r.sort();
      g.sort();
      b.sort();
      out.setPixelRgb(x, y, r[4], g[4], b[4]);
    }
  }
  return out;
}

/// 국소 평균보다 [delta] 이상 어두운 픽셀 — 옅은 외곽선을 잡는 데 쓴다.
///
/// 절대 임계로는 못 잡는 곳이 있다. 네이버는 지도 가장자리 쪽 건물을 배경과
/// 거의 같은 밝기로 흐리게 그리는데(배경 247 / 채움 241~250), 그때도 **외곽선은
/// 주변보다 어둡다**. 그 상대적인 차이만 보면 흐린 구역에서도 건물이 잡힌다.
Mask darkerThanLocal(Uint8List lum, int w, int h, int r, double delta,
    {int loV = 200, int hiV = 252}) {
  final sat = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += lum[y * w + x];
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
  final out = Mask(w, h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final v = lum[y * w + x];
      if (v < loV || v > hiV) continue;
      final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
      final sum = sat[y1 * (w + 1) + x1] -
          sat[y0 * (w + 1) + x1] -
          sat[y1 * (w + 1) + x0] +
          sat[y0 * (w + 1) + x0];
      final mean = sum / ((x1 - x0) * (y1 - y0));
      if (v < mean - delta) out.bits[y * w + x] = 1;
    }
  }
  return out;
}

/// [straighten]이 몇 번이나 포기했는지. 면적 한도에 걸려 원본을 그대로
/// 돌려주면 도로가 편 티가 안 난다 — 그걸 눈치채려고 센다.
int straightenTried = 0, straightenGaveUp = 0;

/// [regularize]가 몇 번 불렸고 몇 번 포기했는지. 포기하면 물결치는 원본이
/// 그대로 나가므로, 이 숫자가 크면 건물이 흐물흐물해 보인다.
int regularizeTried = 0, regularizeGaveUp = 0;

/// 이웃한 두 직선이 나란해 꼭짓점을 못 구한 횟수. 뭉개진 등고선에서는
/// 같은 방향 직선이 나란히 여러 개 남아 여기서 걸린다.
int regularizeNoCorners = 0;
