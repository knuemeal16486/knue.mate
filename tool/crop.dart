import 'dart:io';
import 'package:image/image.dart' as img;
// 사용: dart run tool/crop.dart <x> <y> <w> <h> [out]
void main(List<String> a) {
  final im = img.decodeImage(File('tool/mapsrc/debug.png').readAsBytesSync())!;
  final c = img.copyCrop(im,
      x: int.parse(a[0]), y: int.parse(a[1]),
      width: int.parse(a[2]), height: int.parse(a[3]));
  final out = a.length > 4 ? a[4] : 'crop';
  File('tool/mapsrc/$out.png').writeAsBytesSync(img.encodePng(c));
  stdout.writeln('tool/mapsrc/$out.png ${c.width}x${c.height}');
}
