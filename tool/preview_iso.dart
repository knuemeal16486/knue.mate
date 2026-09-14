// 아이소메트릭 지도를 PNG로 떠서 눈으로 확인한다.
// 앱을 띄우지 않고 데이터만으로 그려보는 용도 — housing_iso.dart의 투영식과
// 칠하는 순서를 그대로 따라간다.
//
//   dart run tool/preview_iso.dart [scale] [out.png]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'traced_json.dart' as tj;

const floorHeight = 3.0;

class P {
  final double x, y;
  const P(this.x, this.y);
}

double _scale = 2.2;
P proj(double x, double y, [double z = 0]) =>
    P((x - y) * 0.5 * _scale, (x + y) * 0.25 * _scale - z * _scale);

void main(List<String> args) {
  if (args.isNotEmpty) _scale = double.parse(args[0]);
  final t = tj.loadTraced();
  final base = jsonDecode(
      File('assets/housing/campus_base.json').readAsStringSync());

  List<List<P>> conv(List<List<List<double>>> src) =>
      [for (final r in src) [for (final p in r) P(p[0], p[1])]];

  final pv = t['pavement'] as Map<String, dynamic>;
  final outline = conv(tj.asRings(t['outline']));
  final paveOuter = conv(tj.asRings(pv['outer']));
  final paveHoles = conv(tj.asRings(pv['holes']));
  final greens = conv(tj.asRings(t['greens']));
  final gOut = [for (final v in (t['greensOutside'] as List? ?? [])) v == true];
  final facils = conv(tj.asRings(t['facilities']));
  final water = conv(tj.asRings(t['water']));
  final parks = conv(tj.asRings(t['parking']));
  final majors = conv(tj.asRings(t['major']));
  final blds = conv(tj.buildingRings(t));
  final index = [
    for (final b in (t['buildings'] as List))
      [b['no'], b['name'], b['floors'], b['use'], b['campus'] == true]
  ];
  stdout.writeln('경계 ${outline.length}  포장 ${paveOuter.length}  '
      '녹지 ${greens.length}  시설 ${facils.length}  주차 ${parks.length}  '
      '건물 ${blds.length}');

  // 부지 밖 건물 (원룸촌 등)
  final outside = <List<P>>[];
  for (final b in base['buildings']) {
    final ring = [
      for (final p in b['ring'])
        P((p[0] as num).toDouble(), (p[1] as num).toDouble())
    ];
    if (ring.length < 3) continue;
    var cx = 0.0, cy = 0.0;
    for (final p in ring) {
      cx += p.x;
      cy += p.y;
    }
    if (_pip(outline, cx / ring.length, cy / ring.length)) continue;
    outside.add(ring);
  }

  // 화면 범위
  var mnx = 1e9, mxx = -1e9, mny = 1e9, mxy = -1e9;
  void grow(P p) {
    mnx = math.min(mnx, p.x);
    mxx = math.max(mxx, p.x);
    mny = math.min(mny, p.y);
    mxy = math.max(mxy, p.y);
  }

  for (final r in [...outline, ...blds, ...outside]) {
    for (final p in r) {
      grow(proj(p.x, p.y));
      grow(proj(p.x, p.y, 30));
    }
  }
  const pad = 30.0;
  final w = (mxx - mnx + pad * 2).round(), h = (mxy - mny + pad * 2).round();
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(244, 241, 233));
  P sc(P p) => P(p.x - mnx + pad, p.y - mny + pad);

  void fill(List<P> ring, img.Color c, {double z = 0}) {
    final pts = [for (final p in ring) sc(proj(p.x, p.y, z))];
    _fillPoly(im, pts, c);
  }

  void stroke(List<P> ring, img.Color c, {double z = 0, bool close = true}) {
    final pts = [for (final p in ring) sc(proj(p.x, p.y, z))];
    for (var i = 0; i + (close ? 0 : 1) < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      img.drawLine(im,
          x1: a.x.round(), y1: a.y.round(), x2: b.x.round(), y2: b.y.round(),
          color: c);
    }
  }

  for (final r in outline) {
    fill(r, img.ColorRgb8(220, 230, 241));
  }
  // 포장면: 외곽 채우고 구멍은 부지색으로 도로 판다 (evenOdd 흉내)
  for (final r in paveOuter) {
    fill(r, img.ColorRgb8(255, 253, 248));
  }
  for (final r in paveHoles) {
    fill(r, img.ColorRgb8(220, 230, 241));
  }
  for (final r in majors) {
    fill(r, img.ColorRgb8(250, 233, 168));
  }
  for (final r in paveOuter) {
    stroke(r, img.ColorRgb8(201, 194, 176));
  }
  for (final r in paveHoles) {
    stroke(r, img.ColorRgb8(201, 194, 176));
  }
  for (final r in parks) {
    fill(r, img.ColorRgb8(237, 224, 192));
    stroke(r, img.ColorRgb8(191, 172, 124));
  }
  for (final r in facils) {
    fill(r, img.ColorRgb8(220, 218, 207));
  }
  for (var gi = 0; gi < greens.length; gi++) {
    final wood = gi < gOut.length && gOut[gi];
    fill(greens[gi], wood
        ? img.ColorRgb8(207, 227, 180)
        : img.ColorRgb8(158, 212, 126));
  }
  for (final r in water) {
    fill(r, img.ColorRgb8(175, 211, 232));
  }
  for (final r in outline) {
    stroke(r, img.ColorRgb8(95, 138, 68));
  }

  const useColor = {
    'academic': [236, 241, 249], 'library': [237, 233, 250],
    'student': [251, 238, 224], 'dorm': [233, 243, 250],
    'sports': [228, 246, 242], 'culture': [250, 235, 239],
    'training': [234, 245, 235], 'admin': [241, 241, 244],
    'affiliate': [246, 244, 230], 'etc': [247, 248, 249],
  };

  // 건물: 뒤쪽부터 그린다 (화가 알고리즘)
  final order = List.generate(blds.length, (i) => i)
    ..sort((a, b) {
      double d(List<P> r) {
        var s = 0.0;
        for (final p in r) {
          s += p.x + p.y;
        }
        return s / r.length;
      }

      return d(blds[a]).compareTo(d(blds[b]));
    });
  final outsideOrder = List.generate(outside.length, (i) => i);
  for (final r in outsideOrder) {
    final ring = outside[r];
    fill(ring, img.ColorRgb8(255, 255, 255), z: 3);
    stroke(ring, img.ColorRgb8(209, 203, 192), z: 3);
  }
  for (final i in order) {
    final ring = blds[i];
    final rec = i < index.length ? index[i] : null;
    final fl = rec == null ? 1 : rec[2] as int;
    final c = useColor[rec == null ? 'etc' : rec[3] as String] ?? useColor['etc']!;
    final z = fl * floorHeight;
    // 벽
    for (var k = 0; k < ring.length; k++) {
      final a = ring[k], b = ring[(k + 1) % ring.length];
      final quad = [
        sc(proj(a.x, a.y, z)),
        sc(proj(b.x, b.y, z)),
        sc(proj(b.x, b.y)),
        sc(proj(a.x, a.y)),
      ];
      final dark = (b.x - a.x).abs() < (b.y - a.y).abs() ? 0.84 : 0.92;
      _fillPoly(
          im,
          quad,
          img.ColorRgb8((c[0] * dark).round(), (c[1] * dark).round(),
              (c[2] * dark).round()));
    }
    fill(ring, img.ColorRgb8(c[0], c[1], c[2]), z: z);
    stroke(ring, img.ColorRgb8(180, 180, 180), z: z);
    // 번호
    if (rec != null && rec[0] != null) {
      var cx = 0.0, cy = 0.0;
      for (final p in ring) {
        cx += p.x;
        cy += p.y;
      }
      final t = sc(proj(cx / ring.length, cy / ring.length, z));
      img.fillCircle(im,
          x: t.x.round(), y: t.y.round(), radius: 9,
          color: img.ColorRgb8(255, 255, 255));
      img.drawCircle(im,
          x: t.x.round(), y: t.y.round(), radius: 9,
          color: img.ColorRgb8(150, 160, 170));
      final s = '${rec[0]}';
      img.drawString(im, s,
          font: img.arial14,
          x: t.x.round() - s.length * 4,
          y: t.y.round() - 7,
          color: img.ColorRgb8(30, 40, 50));
    }
  }

  var result = im;
  // 3·4번째 인자로 월드 좌표를 주면 그 자리를 잘라낸다. 매번 화면 좌표를
  // 손으로 계산하지 않아도 되게.
  if (args.length > 3) {
    final wx = double.parse(args[2]), wy = double.parse(args[3]);
    final cw = args.length > 4 ? int.parse(args[4]) : 1200;
    final ch = args.length > 5 ? int.parse(args[5]) : 760;
    final p = sc(proj(wx, wy));
    final cx = (p.x - cw / 2).round().clamp(0, math.max(0, w - cw));
    final cy = (p.y - ch / 2).round().clamp(0, math.max(0, h - ch));
    result = img.copyCrop(im,
        x: cx.toInt(),
        y: cy.toInt(),
        width: math.min(cw, w - cx.toInt()),
        height: math.min(ch, h - cy.toInt()));
    stdout.writeln('월드($wx,$wy) → 화면(${p.x.round()},${p.y.round()})');
  }
  final out = args.length > 1 ? args[1] : 'tool/mapsrc/iso_preview.png';
  File(out).writeAsBytesSync(img.encodePng(result));
  stdout.writeln('→ $out  ${result.width}x${result.height}');
}

bool _pip(List<List<P>> rings, double x, double y) {
  for (final ring in rings) {
    var c = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.y > y) != (b.y > y) &&
          x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
        c = !c;
      }
    }
    if (c) return true;
  }
  return false;
}

void _fillPoly(img.Image im, List<P> pts, img.Color c) {
  if (pts.length < 3) return;
  var mny = 1e9, mxy = -1e9;
  for (final p in pts) {
    mny = math.min(mny, p.y);
    mxy = math.max(mxy, p.y);
  }
  for (var y = mny.floor(); y <= mxy.ceil(); y++) {
    if (y < 0 || y >= im.height) continue;
    final xs = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.y <= y) != (b.y <= y)) {
        xs.add(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
      }
    }
    xs.sort();
    for (var k = 0; k + 1 < xs.length; k += 2) {
      for (var x = xs[k].ceil(); x <= xs[k + 1].floor(); x++) {
        if (x >= 0 && x < im.width) im.setPixel(x, y, c);
      }
    }
  }
}
