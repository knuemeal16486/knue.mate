// 생성된 지형 에셋을 도구들이 함께 읽는 로더.
// 예전에는 Dart 소스를 정규식으로 훑었다 — JSON이 되면서 그럴 필요가 없어졌다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Map<String, dynamic> loadTraced([String path = 'assets/housing/campus_traced.json']) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<List<double>> asRing(dynamic r) => [
      for (final p in r) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];

List<List<List<double>>> asRings(dynamic l) =>
    [for (final r in (l as List? ?? [])) asRing(r)];

/// 건물 바닥면만. [campusOnly]가 true면 교내만.
List<List<List<double>>> buildingRings(Map<String, dynamic> t,
        {bool? campusOnly}) =>
    [
      for (final b in (t['buildings'] as List))
        if (campusOnly == null || (b['campus'] == true) == campusOnly)
          asRing(b['ring'])
    ];

double ringArea(List<List<double>> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s.abs() / 2;
}

List<double> ringCenter(List<List<double>> r) {
  var a = 1e9, b = -1e9, c = 1e9, d = -1e9;
  for (final p in r) {
    a = math.min(a, p[0]);
    b = math.max(b, p[0]);
    c = math.min(c, p[1]);
    d = math.max(d, p[1]);
  }
  return [(a + b) / 2, (c + d) / 2];
}

bool ringContains(List<List<double>> r, double x, double y) {
  var t = false;
  for (var i = 0, k = r.length - 1; i < r.length; k = i++) {
    final a = r[i], b = r[k];
    if ((a[1] > y) != (b[1] > y) &&
        x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) {
      t = !t;
    }
  }
  return t;
}
