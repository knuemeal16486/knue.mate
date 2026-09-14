// 건물 마스크 기반 등록. VWorld 건물 폴리곤 ↔ 캡처의 건물 채움색(236,244,248).
// 북부는 지적 학교용지 커버리지가 얇아 파란영역 상관이 안 먹혀서 이 방법을 쓴다.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'map_trace_lib.dart';

void main() {
  final base = loadBase();
  final blds = <List<List<double>>>[
    for (final b in base['buildings'])
      [for (final p in b['ring']) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]]
  ];
  var mnX = 1e9, mxX = -1e9, mnY = 1e9, mxY = -1e9;
  for (final r in blds) { for (final p in r) {
    mnX = math.min(mnX, p[0]); mxX = math.max(mxX, p[0]);
    mnY = math.min(mnY, p[1]); mxY = math.max(mxY, p[1]); } }
  const pad = 300.0;
  final ox = mnX - pad, oy = mnY - pad;
  final W = (mxX - mnX + 2*pad).ceil(), H = (mxY - mnY + 2*pad).ceil();
  // 건물은 얇아서 1m 격자에 살짝 부풀려 상관을 안정시킨다
  final world = dilate(rasterize(blds, W, H, ox, oy, 1), 2);
  stdout.writeln('건물격자 ${W}x$H 원점($ox,$oy) 켜진픽셀 ${world.count}');

  const cfg = {
    'core.jpg':  [-200.5, -216.2, 16.0],
    'north.png': [-253.0, -721.0, 10.0],
    'south.png': [-117.6, 163.8, 10.0],
  };
  const scale = 0.619;
  cfg.forEach((f, c) {
    final im = img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!;
    final tol = c[2].toInt();
    final pts = <int>[];
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        if (near(im.getPixel(x, y), 236, 244, 248, tol)) { pts..add(x)..add(y); }
      }
    }
    final n = pts.length ~/ 2;
    double btx = c[0], bty = c[1], best = -1;
    for (final step in [3.0, 0.5]) {
      final range = step == 3.0 ? 90.0 : 4.0;
      final cx = btx, cy = bty; best = -1;
      for (var dx = -range; dx <= range; dx += step) {
        for (var dy = -range; dy <= range; dy += step) {
          final tx = cx + dx, ty = cy + dy;
          var inter = 0;
          for (var k = 0; k < n; k++) {
            if (world.at((pts[k*2]*scale + tx - ox).round(),
                         (pts[k*2+1]*scale + ty - oy).round())) inter++;
          }
          final r = inter / n;
          if (r > best) { best = r; btx = tx; bty = ty; }
        }
      }
    }
    stdout.writeln('$f  건물점 $n  tx ${btx.toStringAsFixed(2)} ty ${bty.toStringAsFixed(2)}  적중률 ${(best*100).toStringAsFixed(1)}%');
  });
}
