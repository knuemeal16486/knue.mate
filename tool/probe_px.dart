// 캡처의 특정 픽셀 색을 잰다. 확대해서 눈으로 고른 자리를 확인하는 용도.
//
//   dart run tool/probe_px.dart <파일> <x> <y> [<x> <y> ...]
//   dart run tool/probe_px.dart <파일> scan <x0> <y0> <x1> <y1>   가로 훑기
import 'dart:io';
import 'package:image/image.dart' as img;

String hex(img.Pixel p) =>
    'rgb(${p.r.toInt()},${p.g.toInt()},${p.b.toInt()})';

void main(List<String> a) {
  final im = img.decodeImage(File('tool/mapsrc/${a[0]}').readAsBytesSync())!;
  stdout.writeln('${a[0]} ${im.width}x${im.height}');
  if (a[1] == 'scan') {
    final x0 = int.parse(a[2]), y0 = int.parse(a[3]);
    final x1 = int.parse(a[4]), y1 = int.parse(a[5]);
    final n = ((x1 - x0).abs() > (y1 - y0).abs() ? (x1 - x0) : (y1 - y0)).abs();
    final b = StringBuffer();
    for (var k = 0; k <= n; k++) {
      final x = x0 + ((x1 - x0) * k / n).round();
      final y = y0 + ((y1 - y0) * k / n).round();
      final p = im.getPixel(x, y);
      b.write('$x,$y:${p.r.toInt()},${p.g.toInt()},${p.b.toInt()}  ');
      if (k % 6 == 5) {
        stdout.writeln(b);
        b.clear();
      }
    }
    if (b.isNotEmpty) stdout.writeln(b);
    return;
  }
  for (var i = 1; i + 1 < a.length; i += 2) {
    final x = int.parse(a[i]), y = int.parse(a[i + 1]);
    stdout.writeln('  px($x,$y) = ${hex(im.getPixel(x, y))}');
  }
}
