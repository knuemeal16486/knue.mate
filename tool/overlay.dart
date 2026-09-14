// 캡처 위에 뽑아낸 폴리곤을 겹쳐 그린다. "얼마나 똑같이 땄나"를 보는 눈검사.
//
//   dart run tool/overlay.dart [core|north|south]
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'traced_json.dart';

const s = 0.619;
const shots = {
  'core.jpg': [-201.2, -215.0],
  'north.png': [-236.5, -712.5],
  'south.png': [-116.8, 163.5],
};

void main(List<String> args) {
  final tj = loadTraced();
  final pave = tj['pavement'] as Map<String, dynamic>;
  final layers = <String, List<dynamic>>{
    '포장면': [asRings(pave['outer']), 230, 30, 30],
    '구멍': [asRings(pave['holes']), 230, 120, 30],
    '건물': [buildingRings(tj), 0, 90, 255],
    '운동시설': [asRings(tj['facilities']), 200, 0, 200],
    '주차장': [asRings(tj['parking']), 255, 150, 0],
    '녹지': [asRings(tj['greens']), 0, 160, 60],
    '국도': [asRings(tj['major']), 200, 170, 0],
    '부지경계': [asRings(tj['outline']), 120, 0, 160],
  };
  final want = args.isEmpty ? shots.keys : shots.keys.where((f) => f.startsWith(args[0]));
  for (final f in want) {
    final im = img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!;
    final t = shots[f]!;
    int px(double x) => ((x - t[0]) / s).round();
    int py(double y) => ((y - t[1]) / s).round();
    void line(int x0, int y0, int x1, int y1, img.Color c) {
      final n = math.max(1, math.max((x1 - x0).abs(), (y1 - y0).abs()));
      for (var k = 0; k <= n; k++) {
        final x = (x0 + (x1 - x0) * k / n).round();
        final y = (y0 + (y1 - y0) * k / n).round();
        if (x >= 0 && y >= 0 && x < im.width && y < im.height) {
          im.setPixel(x, y, c);
        }
      }
    }

    layers.forEach((name, v) {
      final c = img.ColorRgb8(v[1] as int, v[2] as int, v[3] as int);
      for (final r in (v[0] as List<List<List<double>>>)) {
        for (var i = 0; i < r.length; i++) {
          final a = r[i], b = r[(i + 1) % r.length];
          line(px(a[0]), py(a[1]), px(b[0]), py(b[1]), c);
        }
      }
    });
    final out = 'tool/mapsrc/${f.split('.').first}_ov.png';
    File(out).writeAsBytesSync(img.encodePng(im));
    stdout.writeln('→ $out');
  }
}
