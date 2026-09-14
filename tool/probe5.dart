import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final im = img.decodeImage(File('tool/mapsrc/north.png').readAsBytesSync())!;
  const probes = {
    '주차 빗살(세로줄)': [749, 308], '주차 빗살2': [750, 312], '주차 빗살3': [751, 316],
    '주차 띠(가로)': [740, 330], '주차 띠2': [742, 336],
    'P 마커 중심': [750, 328], 'P 마커 테두리': [745, 328],
    '포장면 민무늬': [845, 360], '건물 안': [794, 340], '건물 외곽선': [780, 314],
    '캠퍼스 바탕': [710, 300],
    '우측 주차 빗살': [840, 305], '우측 주차 띠': [770, 330],
  };
  probes.forEach((k, v) {
    final p = im.getPixel(v[0], v[1]);
    stdout.writeln('${k.padRight(16)} px(${v[0]},${v[1]}) '
        'rgb(${p.r.toInt()},${p.g.toInt()},${p.b.toInt()})');
  });
  // P 마커의 파란색을 넓게 훑는다
  final c = <int, int>{};
  for (var y = 315; y < 345; y++) {
    for (var x = 738; x < 765; x++) {
      final p = im.getPixel(x, y);
      if (p.b.toInt() - p.r.toInt() > 40) {
        final k = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
        c[k] = (c[k] ?? 0) + 1;
      }
    }
  }
  final t = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('--- P 마커 파랑 상위 ---');
  for (final e in t.take(5)) {
    stdout.writeln('  rgb(${(e.key >> 16) & 255},${(e.key >> 8) & 255},'
        '${e.key & 255}) ${e.value}px');
  }
}
