// 이미지 일부를 잘라 확대한다. 추출 결과를 원본과 눈으로 대조할 때 쓴다.
//
//   dart run tool/crop_ov.dart <src> <x> <y> <w> <h> [배율] [out]
//
// 배율은 최근접 확대라 픽셀 경계가 그대로 보인다 — 계단 모양이 얼마나
// 남았는지 봐야 하므로 보간하면 안 된다.
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> a) {
  if (a.length < 5) {
    stdout.writeln('사용: dart run tool/crop_ov.dart <src> <x> <y> <w> <h> '
        '[배율] [out]');
    return;
  }
  final im = img.decodeImage(File(a[0]).readAsBytesSync())!;
  final x = int.parse(a[1]), y = int.parse(a[2]);
  final w = int.parse(a[3]), h = int.parse(a[4]);
  final c = img.copyCrop(im,
      x: x.clamp(0, im.width - 1),
      y: y.clamp(0, im.height - 1),
      width: w.clamp(1, im.width - x),
      height: h.clamp(1, im.height - y));
  final k = a.length > 5 ? int.parse(a[5]) : 3;
  final up = img.copyResize(c,
      width: c.width * k,
      height: c.height * k,
      interpolation: img.Interpolation.nearest);
  final out = a.length > 6 ? a[6] : 'tool/mapsrc/crop.png';
  File(out).writeAsBytesSync(img.encodePng(up));
  stdout.writeln('→ $out ${up.width}x${up.height} (원본 ${im.width}x${im.height})');
}
