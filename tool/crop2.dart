import 'dart:io';
import 'package:image/image.dart' as img;
void main(List<String> a) {
  final im = img.decodeImage(File(a[0]).readAsBytesSync())!;
  final c = img.copyCrop(im, x: int.parse(a[1]), y: int.parse(a[2]),
      width: int.parse(a[3]), height: int.parse(a[4]));
  File(a[5]).writeAsBytesSync(img.encodePng(c));
  stdout.writeln('${a[5]} ${c.width}x${c.height}');
}
