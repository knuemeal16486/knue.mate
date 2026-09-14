import 'dart:io';
import 'package:image/image.dart' as img;
// dart run tool/zoom.dart <src> <x> <y> <w> <h> <배율> <out>
void main(List<String> a) {
  final im = img.decodeImage(File(a[0]).readAsBytesSync())!;
  final c = img.copyCrop(im,
      x: int.parse(a[1]), y: int.parse(a[2]),
      width: int.parse(a[3]), height: int.parse(a[4]));
  final z = img.copyResize(c,
      width: c.width * int.parse(a[5]),
      interpolation: img.Interpolation.nearest);
  File(a[6]).writeAsBytesSync(img.encodePng(z));
  stdout.writeln('${a[6]} ${z.width}x${z.height}');
}
