import 'dart:io';
import 'package:image/image.dart' as img;
const s = 0.619;
void main() {
  final core = img.decodeImage(File('tool/mapsrc/core.jpg').readAsBytesSync())!;
  final north = img.decodeImage(File('tool/mapsrc/north.png').readAsBytesSync())!;
  void scan(String tag, img.Image im, double tx, double ty, double y,
      double x0, double x1) {
    final py = ((y - ty) / s).round();
    final b = StringBuffer('$tag y=$y  ');
    for (var x = x0; x <= x1; x += 3) {
      final px = ((x - tx) / s).round();
      if (px < 0 || px >= im.width || py < 0 || py >= im.height) continue;
      final p = im.getPixel(px, py);
      b.write('${x.round()}:${p.r.toInt()},${p.g.toInt()},${p.b.toInt()}  ');
    }
    stdout.writeln(b);
  }
  // 호연관을 가로지르는 선 (core.jpg)
  scan('호연관', core, -201.2, -215.0, -15, 370, 430);
  stdout.writeln('');
  scan('대학본부', core, -201.2, -215.0, 65, 225, 285);
  stdout.writeln('');
  // 같은 종류를 PNG에서
  scan('국제연수관', north, -236.5, -712.5, -487, 200, 260);
}
