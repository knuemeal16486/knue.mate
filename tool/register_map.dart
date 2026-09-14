// 캡처의 '학교용지 파란 영역'을 VWorld 지적(campus 필지)에 맞춰
// px→월드 변환(배율·평행이동)을 자동으로 찾는다. 눈대중은 탐색 범위를 좁히는 데만 쓴다.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'map_trace_lib.dart';

class Seed {
  final String file;
  final int px, py; // 눈으로 읽은 라벨 위치
  final double wx, wy; // 그 건물의 실측 월드 좌표
  final int tol; // 색 허용오차 (JPEG는 넉넉히)
  const Seed(this.file, this.px, this.py, this.wx, this.wy, this.tol);
}

const seeds = [
  Seed('core.jpg', 731, 463, 252, 65, 16), // 대학본부
  Seed('north.png', 855, 689, 264, -281, 10), // 함덕당
  Seed('south.png', 600, 113, 258, 234, 10), // 교육박물관
];

void main() {
  final base = loadBase();
  final campus = <List<List<double>>>[];
  for (final l in base['landuse']) {
    if (l['g'] == 'campus') {
      campus.add([
        for (final p in l['ring']) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
      ]);
    }
  }
  // 월드 격자 1 m/px
  var mnX = 1e9, mxX = -1e9, mnY = 1e9, mxY = -1e9;
  for (final r in campus) {
    for (final p in r) {
      mnX = math.min(mnX, p[0]);
      mxX = math.max(mxX, p[0]);
      mnY = math.min(mnY, p[1]);
      mxY = math.max(mxY, p[1]);
    }
  }
  const pad = 60.0;
  final ox = mnX - pad, oy = mnY - pad;
  final W = (mxX - mnX + 2 * pad).ceil(), H = (mxY - mnY + 2 * pad).ceil();
  stdout.writeln('월드격자 ${W}x$H  원점($ox,$oy)  campus필지 ${campus.length}');
  final world = rasterize(campus, W, H, ox, oy, 1);
  stdout.writeln('campus 픽셀 ${world.count}');

  // 적분영상 (footprint 내 월드 픽셀 수 계산용)
  final sat = List<int>.filled((W + 1) * (H + 1), 0);
  for (var j = 0; j < H; j++) {
    var row = 0;
    for (var i = 0; i < W; i++) {
      row += world.at(i, j) ? 1 : 0;
      sat[(j + 1) * (W + 1) + i + 1] = sat[j * (W + 1) + i + 1] + row;
    }
  }
  int satSum(int x0, int y0, int x1, int y1) {
    x0 = x0.clamp(0, W); x1 = x1.clamp(0, W);
    y0 = y0.clamp(0, H); y1 = y1.clamp(0, H);
    return sat[y1 * (W + 1) + x1] - sat[y0 * (W + 1) + x1] -
        sat[y1 * (W + 1) + x0] + sat[y0 * (W + 1) + x0];
  }

  for (final s in seeds) {
    final im = img.decodeImage(File('tool/mapsrc/${s.file}').readAsBytesSync())!;
    // 파란 학교용지 픽셀
    final pts = <int>[]; // px,py 쌍
    for (var y = 0; y < im.height; y += 3) {
      for (var x = 0; x < im.width; x += 3) {
        if (near(im.getPixel(x, y), 212, 224, 240, s.tol)) {
          pts..add(x)..add(y);
        }
      }
    }
    final n = pts.length ~/ 2;
    stdout.writeln('\n=== ${s.file} ${im.width}x${im.height}  파란점 $n');

    double bestScore = -1, bs = 0, btx = 0, bty = 0;
    // 1단계: 거친 탐색
    for (var scale = 0.45; scale <= 0.95; scale += 0.005) {
      final tx0 = s.wx - s.px * scale, ty0 = s.wy - s.py * scale;
      for (var dx = -50.0; dx <= 50.0; dx += 3) {
        for (var dy = -50.0; dy <= 50.0; dy += 3) {
          final tx = tx0 + dx, ty = ty0 + dy;
          var inter = 0;
          for (var k = 0; k < n; k += 4) {
            final i = ((pts[k * 2] * scale + tx - ox)).round();
            final j = ((pts[k * 2 + 1] * scale + ty - oy)).round();
            if (world.at(i, j)) inter++;
          }
          final an = (n / 4).ceil();
          final bn = satSum(
              (tx - ox).round(), (ty - oy).round(),
              (im.width * scale + tx - ox).round(),
              (im.height * scale + ty - oy).round());
          // 월드쪽은 1m 격자, 샘플쪽은 4개당 1개 → 스케일 보정
          final bScaled = bn / (scale * scale * 9 * 4);
          final dice = 2 * inter / (an + bScaled);
          if (dice > bestScore) {
            bestScore = dice; bs = scale; btx = tx; bty = ty;
          }
        }
      }
    }
    stdout.writeln('  거친해: 배율 ${bs.toStringAsFixed(4)} m/px  '
        'tx ${btx.toStringAsFixed(1)} ty ${bty.toStringAsFixed(1)}  dice ${bestScore.toStringAsFixed(3)}');

    // 2단계: 정밀 (전체 점 사용)
    double fs = bs, ftx = btx, fty = bty, fbest = -1;
    for (var scale = bs - 0.01; scale <= bs + 0.01; scale += 0.001) {
      for (var dx = -4.0; dx <= 4.0; dx += 0.5) {
        for (var dy = -4.0; dy <= 4.0; dy += 0.5) {
          final tx = btx + dx + (bs - scale) * s.px, ty = bty + dy + (bs - scale) * s.py;
          var inter = 0;
          for (var k = 0; k < n; k++) {
            final i = ((pts[k * 2] * scale + tx - ox)).round();
            final j = ((pts[k * 2 + 1] * scale + ty - oy)).round();
            if (world.at(i, j)) inter++;
          }
          final bn = satSum((tx - ox).round(), (ty - oy).round(),
              (im.width * scale + tx - ox).round(),
              (im.height * scale + ty - oy).round());
          final bScaled = bn / (scale * scale * 9);
          final dice = 2 * inter / (n + bScaled);
          if (dice > fbest) { fbest = dice; fs = scale; ftx = tx; fty = ty; }
        }
      }
    }
    stdout.writeln('  정밀해: 배율 ${fs.toStringAsFixed(4)} m/px  '
        'tx ${ftx.toStringAsFixed(2)} ty ${fty.toStringAsFixed(2)}  dice ${fbest.toStringAsFixed(3)}');
  }
}
