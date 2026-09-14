import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final im = img.decodeImage(File('tool/mapsrc/north.png').readAsBytesSync())!;
  // 건물이 확실한 지점 몇 곳 / 도로 / 배경
  const probes = {
    '국제연수관 건물': [842, 330], '복지관 건물': [1090, 460],
    '함덕당 건물': [820, 640], '부설고 건물': [640, 545],
    '도로(태성탑연로)': [714, 250], '캠퍼스 여백': [520, 300],
    '운동장 잔디': [1350, 700], '운동장 트랙': [1300, 640],
  };
  probes.forEach((k, v) {
    final p = im.getPixel(v[0], v[1]);
    stdout.writeln('$k px(${v[0]},${v[1]}) = rgb(${p.r.toInt()},${p.g.toInt()},${p.b.toInt()})');
  });
  // 건물 후보색 히스토그램: 파랑도 초록도 아니고 밝은 것
  final c = <int, int>{};
  for (var y = 250; y < 750; y++) {
    for (var x = 600; x < 1400; x++) {
      final p = im.getPixel(x, y);
      final k = ((p.r.toInt() >> 2) << 12) | ((p.g.toInt() >> 2) << 6) | (p.b.toInt() >> 2);
      c[k] = (c[k] ?? 0) + 1;
    }
  }
  final t = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('--- 캠퍼스 내부 색 상위 ---');
  for (final e in t.take(12)) {
    stdout.writeln('  rgb(${((e.key>>12)&63)<<2},${((e.key>>6)&63)<<2},${(e.key&63)<<2})  ${e.value}');
  }
}
