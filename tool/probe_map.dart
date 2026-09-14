// 네이버지도 캡처의 색 팔레트를 조사한다. trace_map.dart 임계값을 정하는 용도.
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  for (final name in ['north.png', 'core.jpg', 'south.png']) {
    final im = img.decodeImage(File('tool/mapsrc/$name').readAsBytesSync())!;
    stdout.writeln('=== $name  ${im.width}x${im.height} ===');
    final counts = <int, int>{};
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        final p = im.getPixel(x, y);
        // 6bit로 뭉개서 JPEG 노이즈를 흡수한다
        final k = ((p.r.toInt() >> 2) << 12) |
            ((p.g.toInt() >> 2) << 6) |
            (p.b.toInt() >> 2);
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    for (final e in top.take(14)) {
      final r = ((e.key >> 12) & 63) << 2;
      final g = ((e.key >> 6) & 63) << 2;
      final b = (e.key & 63) << 2;
      stdout.writeln('  rgb($r,$g,$b)  ${(e.value * 100 / total).toStringAsFixed(1)}%');
    }
  }
}
