// 레이어끼리 겹치는지 잰다. 도로가 건물 위를 덮거나 녹지가 건물을 덮으면
// 지도가 뭉개져 보인다. 0.5m 격자에 찍어 센다.
import 'dart:io';
import 'dart:math' as math;
import 'traced_json.dart';

const cell = 0.5;
late double mnx, mny;
late int gw, gh;

void paint(List<int> g, List<List<List<double>>> polys, int bit) {
  for (final r in polys) {
    if (r.length < 3) continue;
    for (var j = 0; j < gh; j++) {
      final yw = mny + j * cell;
      final xs = <double>[];
      for (var i = 0; i < r.length; i++) {
        final a = r[i], b = r[(i + 1) % r.length];
        if ((a[1] <= yw) != (b[1] <= yw)) {
          xs.add(a[0] + (yw - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        for (var i = ((xs[k] - mnx) / cell).ceil();
            i <= ((xs[k + 1] - mnx) / cell).floor();
            i++) {
          if (i >= 0 && i < gw) g[j * gw + i] |= bit;
        }
      }
    }
  }
}

void main() {
  final t = loadTraced();
  final pv = t['pavement'] as Map<String, dynamic>;
  final blds = buildingRings(t);
  final outer = asRings(pv['outer']), holes = asRings(pv['holes']);
  final greens = asRings(t['greens']);
  mnx = 1e9;
  mny = 1e9;
  var mxx = -1e9, mxy = -1e9;
  for (final r in [...blds, ...outer, ...greens]) {
    for (final p in r) {
      mnx = math.min(mnx, p[0]);
      mxx = math.max(mxx, p[0]);
      mny = math.min(mny, p[1]);
      mxy = math.max(mxy, p[1]);
    }
  }
  gw = ((mxx - mnx) / cell).ceil() + 2;
  gh = ((mxy - mny) / cell).ceil() + 2;
  final g = List<int>.filled(gw * gh, 0);
  paint(g, blds, 1);
  paint(g, outer, 2);
  paint(g, holes, 4); // 구멍은 포장면에서 빠지는 부분
  paint(g, greens, 8);
  var bld = 0, pave = 0, green = 0;
  var bldPave = 0, bldGreen = 0, paveGreen = 0;
  for (final v in g) {
    final b = v & 1 != 0;
    final p = (v & 2 != 0) && (v & 4 == 0);
    final gr = v & 8 != 0;
    if (b) bld++;
    if (p) pave++;
    if (gr) green++;
    if (b && p) bldPave++;
    if (b && gr) bldGreen++;
    if (p && gr) paveGreen++;
  }
  final a = cell * cell;
  stdout.writeln('건물 ${(bld * a).round()}㎡  포장 ${(pave * a).round()}㎡  '
      '녹지 ${(green * a).round()}㎡');
  stdout.writeln('겹침:');
  stdout.writeln('  건물↔포장  ${(bldPave * a).round()}㎡  '
      '(건물의 ${(bldPave * 100 / bld).toStringAsFixed(1)}%)');
  stdout.writeln('  건물↔녹지  ${(bldGreen * a).round()}㎡  '
      '(건물의 ${(bldGreen * 100 / bld).toStringAsFixed(1)}%)');
  stdout.writeln('  포장↔녹지  ${(paveGreen * a).round()}㎡  '
      '(포장의 ${(paveGreen * 100 / pave).toStringAsFixed(1)}%)');
}
