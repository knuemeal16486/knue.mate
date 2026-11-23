// 실제 땅 높이(DEM) → assets/housing/campus_dem.json
//
//   dart run tool/fetch_dem.dart
//
// 3D 둘러보기의 언덕에 쓴다. 손으로 놓은 봉우리 모델(CampusElevation)은
// 원룸촌이 평지로 나오고 교내 비탈도 실제와 달랐다.
//
// 원본은 Mapzen/AWS Terrain Tiles(terrarium PNG)다. 한국 지역은 SRTM(약 30m
// 격자, NASA·공공 영역)에서 온다. 요청은 타일 몇 장뿐이고 키가 필요 없다.
// https://registry.opendata.aws/terrain-tiles/
//
// ⚠️ SRTM은 **지표면** 높이라 큰 건물·숲 꼭대기가 조금 섞여 있고 ±수 m 잡음이
// 있다. 그래서 30m 격자로 받아 한 번 부드럽게 고른다(건물 하나하나의 울퉁불퉁을
// 언덕으로 그리지 않게).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// 지도 좌표 원점(tool/fetch_osm_roads.js와 같다). x는 동쪽, y는 남쪽(m).
const originLon = 127.3544, originLat = 36.6092;
const mPerDegLat = 111320.0;
final mPerDegLon = 111320.0 * math.cos(originLat * math.pi / 180);

// 둘러보기 범위(kView3World)에 여백을 둔 것.
const minX = -680.0, minY = -920.0, maxX = 1220.0, maxY = 860.0;
const step = 30.0;
const zoom = 13;

double lonOf(double x) => originLon + x / mPerDegLon;
double latOf(double y) => originLat - y / mPerDegLat;

/// 경위도 → 타일 좌표(소수). 웹 메르카토르.
(double, double) tileXY(double lon, double lat) {
  final n = math.pow(2, zoom).toDouble();
  final x = (lon + 180) / 360 * n;
  final r = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  return (x, y);
}

Future<void> main() async {
  final tiles = <(int, int), img.Image>{};
  Future<img.Image> tile(int tx, int ty) async {
    final hit = tiles[(tx, ty)];
    if (hit != null) return hit;
    final url = Uri.parse(
      'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$zoom/$tx/$ty.png',
    );
    final res = await http.get(url, headers: {'User-Agent': 'map-dem-fetch/1.0'});
    if (res.statusCode != 200) {
      throw StateError('타일 $tx/$ty 받기 실패: ${res.statusCode}');
    }
    final im = img.decodePng(res.bodyBytes);
    if (im == null) throw StateError('타일 $tx/$ty 디코드 실패');
    stdout.writeln('타일 $zoom/$tx/$ty  ${res.bodyBytes.length}바이트');
    return tiles[(tx, ty)] = im;
  }

  /// terrarium: 높이(m) = R×256 + G + B/256 − 32768.
  Future<double> pixel(int px, int py) async {
    final im = await tile(px ~/ 256, py ~/ 256);
    final p = im.getPixel(px % 256, py % 256);
    return p.r * 256.0 + p.g + p.b / 256.0 - 32768.0;
  }

  /// 타일 픽셀 사이를 선형 보간해 읽는다.
  Future<double> sample(double lon, double lat) async {
    final (tx, ty) = tileXY(lon, lat);
    final fx = tx * 256 - 0.5, fy = ty * 256 - 0.5;
    final x0 = fx.floor(), y0 = fy.floor();
    final ax = fx - x0, ay = fy - y0;
    final a = await pixel(x0, y0), b = await pixel(x0 + 1, y0);
    final c = await pixel(x0, y0 + 1), d = await pixel(x0 + 1, y0 + 1);
    return (a * (1 - ax) + b * ax) * (1 - ay) + (c * (1 - ax) + d * ax) * ay;
  }

  final nx = ((maxX - minX) / step).round() + 1;
  final ny = ((maxY - minY) / step).round() + 1;
  final raw = List.generate(ny, (_) => List.filled(nx, 0.0));
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      raw[j][i] = await sample(lonOf(minX + i * step), latOf(minY + j * step));
    }
  }

  // 3×3 가중 평균(1-2-1)으로 한 번 고른다.
  final out = List.generate(ny, (_) => List.filled(nx, 0.0));
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      var sum = 0.0, wsum = 0.0;
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          final jj = j + dj, ii = i + di;
          if (jj < 0 || jj >= ny || ii < 0 || ii >= nx) continue;
          final w = (dj == 0 ? 2 : 1) * (di == 0 ? 2 : 1);
          sum += raw[jj][ii] * w;
          wsum += w;
        }
      }
      out[j][i] = sum / wsum;
    }
  }

  var lo = double.infinity, hi = -double.infinity;
  for (final row in out) {
    for (final v in row) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
  }

  final json = {
    'note': '실제 땅 높이(해발 m). tool/fetch_dem.dart로 생성. '
        'x는 동쪽·y는 남쪽(m), h는 행 우선(위→아래, 왼→오른쪽), 0.1m 단위 정수.',
    'source': 'Mapzen/AWS Terrain Tiles (terrarium z$zoom), SRTM',
    'origin': {'lon': originLon, 'lat': originLat},
    'minX': minX,
    'minY': minY,
    'step': step,
    'nx': nx,
    'ny': ny,
    'h': [
      for (final row in out)
        for (final v in row) (v * 10).round(),
    ],
  };
  File('assets/housing/campus_dem.json').writeAsStringSync(jsonEncode(json));
  stdout.writeln('격자 $nx×$ny (${step.round()}m) · 해발 '
      '${lo.toStringAsFixed(1)}~${hi.toStringAsFixed(1)}m '
      '→ assets/housing/campus_dem.json');

  double at(double x, double y) =>
      out[((y - minY) / step).round()][((x - minX) / step).round()];
  for (final (name, x, y) in [
    ('정문 근처', 0.0, 205.0),
    ('원룸촌 가운데', 78.0, 15.0),
    ('원룸촌 북쪽', 60.0, -194.0),
    ('도서관', 230.0, 70.0),
    ('기숙사 언덕', 600.0, -300.0),
    ('청람동산', 620.0, -520.0),
    ('대운동장', 450.0, 320.0),
  ]) {
    stdout.writeln('  $name ($x, $y): ${at(x, y).toStringAsFixed(1)}m');
  }
}
