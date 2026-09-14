import 'dart:io';
import 'package:image/image.dart' as img;
// 월드좌표를 찍어 색을 본다: 트랙 노면, 테니스 코트.
const s = 0.619;
void main() {
  final north = img.decodeImage(File('tool/mapsrc/north.png').readAsBytesSync())!;
  final south = img.decodeImage(File('tool/mapsrc/south.png').readAsBytesSync())!;
  void probe(String tag, img.Image im, double tx, double ty, List<List<double>> ws) {
    for (final w in ws) {
      final px = ((w[0] - tx) / s).round(), py = ((w[1] - ty) / s).round();
      if (px < 0 || py < 0 || px >= im.width || py >= im.height) {
        stdout.writeln('$tag (${w[0]},${w[1]}) 범위밖');
        continue;
      }
      final p = im.getPixel(px, py);
      stdout.writeln('$tag 월드(${w[0]},${w[1]}) px($px,$py) = '
          'rgb(${p.r.toInt()},${p.g.toInt()},${p.b.toInt()})');
    }
  }
  stdout.writeln('--- 대운동장 트랙 (north) ---');
  probe('트랙', north, -236.5, -712.5, [
    [629, -255], [700, -255], [560, -255], [629, -320], [629, -190],
    [690, -300], [575, -210],
  ]);
  stdout.writeln('--- 테니스장 (south) ---');
  probe('테니스', south, -116.8, 163.5, [
    [660, 360], [690, 345], [720, 330], [750, 315], [773, 306],
    [640, 370], [700, 340],
  ]);
  stdout.writeln('--- 남측 운동장 (south) ---');
  probe('운동장', south, -116.8, 163.5, [[577, 417], [577, 380], [577, 450]]);
}
