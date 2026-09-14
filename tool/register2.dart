// 세 캡처는 같은 줌(50m 눈금)이므로 배율은 하나여야 한다.
// 배율을 공유값으로 고정하고 평행이동만 넓게 다시 찾는다.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'map_trace_lib.dart';

void main() {
  final base = loadBase();
  final campus = <List<List<double>>>[];
  for (final l in base['landuse']) {
    if (l['g'] == 'campus') {
      campus.add([for (final p in l['ring']) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]]);
    }
  }
  var mnX = 1e9, mxX = -1e9, mnY = 1e9, mxY = -1e9;
  for (final r in campus) { for (final p in r) {
    mnX = math.min(mnX, p[0]); mxX = math.max(mxX, p[0]);
    mnY = math.min(mnY, p[1]); mxY = math.max(mxY, p[1]); } }
  const pad = 400.0;
  final ox = mnX - pad, oy = mnY - pad;
  final W = (mxX - mnX + 2 * pad).ceil(), H = (mxY - mnY + 2 * pad).ceil();
  final world = rasterize(campus, W, H, ox, oy, 1);
  final sat = List<int>.filled((W + 1) * (H + 1), 0);
  for (var j = 0; j < H; j++) { var row = 0;
    for (var i = 0; i < W; i++) { row += world.at(i, j) ? 1 : 0;
      sat[(j + 1) * (W + 1) + i + 1] = sat[j * (W + 1) + i + 1] + row; } }
  int satSum(int x0, int y0, int x1, int y1) {
    x0 = x0.clamp(0, W); x1 = x1.clamp(0, W); y0 = y0.clamp(0, H); y1 = y1.clamp(0, H);
    return sat[y1*(W+1)+x1] - sat[y0*(W+1)+x1] - sat[y1*(W+1)+x0] + sat[y0*(W+1)+x0];
  }

  const files = {'core.jpg': 16, 'north.png': 10, 'south.png': 10};
  const priors = {'core.jpg': [-198.5, -216.2], 'north.png': [-253.0, -721.0], 'south.png': [-119.6, 162.8]};
  final scale = double.parse(Platform.environment['SCALE'] ?? '0.619');
  stdout.writeln('고정 배율 ${scale} m/px');

  files.forEach((f, tol) {
    final im = img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!;
    final pts = <int>[];
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        if (near(im.getPixel(x, y), 212, 224, 240, tol)) { pts..add(x)..add(y); }
      }
    }
    final n = pts.length ~/ 2;
    final p0 = priors[f]!;
    double best = -1, btx = 0, bty = 0;
    // 넓은 거친 탐색 → 정밀
    for (final step in [4.0, 0.5]) {
      final range = step == 4.0 ? 90.0 : 6.0;
      final cx = step == 4.0 ? p0[0] : btx, cy = step == 4.0 ? p0[1] : bty;
      final sub = step == 4.0 ? 4 : 1;
      best = -1;
      for (var dx = -range; dx <= range; dx += step) {
        for (var dy = -range; dy <= range; dy += step) {
          final tx = cx + dx, ty = cy + dy;
          var inter = 0, cnt = 0;
          for (var k = 0; k < n; k += sub) {
            cnt++;
            final i = (pts[k*2] * scale + tx - ox).round();
            final j = (pts[k*2+1] * scale + ty - oy).round();
            if (world.at(i, j)) inter++;
          }
          final bn = satSum((tx-ox).round(), (ty-oy).round(),
              (im.width*scale+tx-ox).round(), (im.height*scale+ty-oy).round());
          final bScaled = bn / (scale*scale*4*sub);
          final dice = 2*inter/(cnt + bScaled);
          if (dice > best) { best = dice; btx = tx; bty = ty; }
        }
      }
    }
    stdout.writeln('$f  tx ${btx.toStringAsFixed(2)}  ty ${bty.toStringAsFixed(2)}  dice ${best.toStringAsFixed(3)}');
  });
}
