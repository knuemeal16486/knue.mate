// 부지 밖 팔레트 조사. 임계값을 정하기 전에 실제 색을 재려고 만든 진단 도구다.
//
//   dart run tool/probe_outside.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

const s = 0.619;
const shots = {
  'core.jpg': [-201.2, -215.0],
  'north.png': [-236.5, -712.5],
  'south.png': [-116.8, 163.5],
};

/// 부지 밖 관심 지점 — 캡처를 눈으로 보고 고른 자리다.
const spots = <String, List<dynamic>>{
  // [파일, 월드x, 월드y, 설명]
  '원룸촌 배경': ['core.jpg', -80.0, 30.0],
  '원룸촌 골목': ['core.jpg', -60.0, 60.0],
  '월탄3길 노면': ['core.jpg', 90.0, -30.0],
  '원룸 건물 지붕': ['core.jpg', -40.0, 20.0],
  '아파트 단지': ['core.jpg', -120.0, 160.0],
  '교원상가': ['core.jpg', -60.0, 260.0],
  '국도 507 노면': ['south.png', -140.0, 380.0],
  '하천 수면': ['south.png', -105.0, 300.0],
  '하천 둔치': ['south.png', -95.0, 330.0],
  '동쪽 산림': ['south.png', 880.0, 300.0],
  '북동 산림': ['north.png', 700.0, -600.0],
  '북서 배경': ['north.png', -150.0, -400.0],
};

void main() {
  final cache = <String, img.Image>{};
  img.Image load(String f) => cache.putIfAbsent(
      f, () => img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!);

  stdout.writeln('=== 지점별 색 (주변 5x5 중앙값) ===');
  spots.forEach((name, v) {
    final f = v[0] as String;
    final im = load(f);
    final t = shots[f]!;
    final px = ((v[1] as double) - t[0]) ~/ s;
    final py = ((v[2] as double) - t[1]) ~/ s;
    if (px < 2 || py < 2 || px >= im.width - 2 || py >= im.height - 2) {
      stdout.writeln('${name.padRight(14)} 범위밖');
      return;
    }
    final rs = <int>[], gs = <int>[], bs = <int>[];
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final p = im.getPixel(px + dx, py + dy);
        rs.add(p.r.toInt());
        gs.add(p.g.toInt());
        bs.add(p.b.toInt());
      }
    }
    rs.sort();
    gs.sort();
    bs.sort();
    stdout.writeln('${name.padRight(14)} $f px($px,$py) '
        'rgb(${rs[12]},${gs[12]},${bs[12]})');
  });

  // 캡처가 덮는 월드 범위
  stdout.writeln('\n=== 캡처 덮는 범위 ===');
  var mnx = 1e9, mxx = -1e9, mny = 1e9, mxy = -1e9;
  shots.forEach((f, t) {
    final im = load(f);
    final x0 = t[0], y0 = t[1];
    final x1 = t[0] + im.width * s, y1 = t[1] + im.height * s;
    stdout.writeln('$f  x ${x0.toStringAsFixed(1)}..${x1.toStringAsFixed(1)}  '
        'y ${y0.toStringAsFixed(1)}..${y1.toStringAsFixed(1)}');
    mnx = math.min(mnx, x0);
    mxx = math.max(mxx, x1);
    mny = math.min(mny, y0);
    mxy = math.max(mxy, y1);
  });
  stdout.writeln('합집합  x ${mnx.toStringAsFixed(1)}..${mxx.toStringAsFixed(1)}  '
      'y ${mny.toStringAsFixed(1)}..${mxy.toStringAsFixed(1)}');

  // 부지 밖 전체 색 분포 — 부지 파랑이 없는 영역만 훑는다
  stdout.writeln('\n=== 부지 밖 색 상위 (파랑 제외) ===');
  for (final f in shots.keys) {
    final im = load(f);
    final c = <int, int>{};
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        final p = im.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        if (b - r > 18) continue; // 학교용지 파랑·마커 제외
        final k = ((r >> 2) << 12) | ((g >> 2) << 6) | (b >> 2);
        c[k] = (c[k] ?? 0) + 1;
      }
    }
    final t = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final tot = c.values.fold<int>(0, (a, b) => a + b);
    stdout.writeln('--- $f ---');
    for (final e in t.take(12)) {
      stdout.writeln('  rgb(${((e.key >> 12) & 63) << 2},'
          '${((e.key >> 6) & 63) << 2},${(e.key & 63) << 2})  '
          '${(e.value * 100 / tot).toStringAsFixed(1)}%');
    }
  }

  // 마커 색 — 진한 것만
  stdout.writeln('\n=== 마커 후보 (채도 높은 색) ===');
  for (final f in shots.keys) {
    final im = load(f);
    final c = <int, int>{};
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        if (mx - mn < 60 || mx < 120) continue;
        final k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
        c[k] = (c[k] ?? 0) + 1;
      }
    }
    final t = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('--- $f ---');
    for (final e in t.take(10)) {
      stdout.writeln('  rgb(${((e.key >> 10) & 31) << 3},'
          '${((e.key >> 5) & 31) << 3},${(e.key & 31) << 3})  ${e.value}px');
    }
  }
}
