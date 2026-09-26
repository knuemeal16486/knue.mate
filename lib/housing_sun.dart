import 'dart:math' as math;
import 'dart:ui' show Offset, Path;

import 'housing_iso.dart' show BaseBuilding, IsoProjection, buildingBaseZ, computeConvexHull;
import 'housing_model.dart' show kHousingOriginLat, kHousingOriginLon;

// 자취방 지도의 시간별 그림자.
//
// 해의 위치는 NOAA 간이식(오차 1° 안팎)으로 계산한다. 건물 그림자는 바닥
// 모양을 해 반대쪽으로 (높이 ÷ tan 해 높이)만큼 민 모양과 원래 바닥 모양을
// 합친 볼록 껍질로 그린다. ㄱ자처럼 오목한 건물은 오목한 안쪽까지 살짝 덮이지만,
// 모든 그림자가 같은 방향으로 감긴 다각형 하나씩이 되어 한 번에 칠할 수 있다.

/// 한국 표준시(UTC+9). 기기 시간대와 상관없이 캠퍼스 시각으로 계산한다.
const Duration _kst = Duration(hours: 9);

/// 해의 위치. [altitude]는 지평선 위 높이(°), [azimuth]는 북쪽에서 시계
/// 방향으로 잰 방위(°, 동=90, 남=180).
class SunPosition {
  final double altitude;
  final double azimuth;
  const SunPosition(this.altitude, this.azimuth);

  bool get isUp => altitude > 0;
}

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// [utc] 시각, (위도 [lat], 경도 [lon])에서 본 해의 위치. 순수 함수 — 테스트 대상.
SunPosition sunPositionAt(
  DateTime utc, {
  double lat = kHousingOriginLat,
  double lon = kHousingOriginLon,
}) {
  final t = utc.toUtc();
  final startOfYear = DateTime.utc(t.year);
  final dayOfYear = t.difference(startOfYear).inDays + 1;
  final hour = t.hour + t.minute / 60 + t.second / 3600;
  final daysInYear = DateTime.utc(t.year + 1).difference(startOfYear).inDays;

  final g = 2 * math.pi / daysInYear * (dayOfYear - 1 + (hour - 12) / 24);
  final eqTime = 229.18 *
      (0.000075 +
          0.001868 * math.cos(g) -
          0.032077 * math.sin(g) -
          0.014615 * math.cos(2 * g) -
          0.040849 * math.sin(2 * g));
  final decl = 0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);

  // 참태양시(분) → 시간각
  final trueSolarMin = hour * 60 + eqTime + 4 * lon;
  final ha = _rad(trueSolarMin / 4 - 180);
  final phi = _rad(lat);

  final cosZen = (math.sin(phi) * math.sin(decl) +
          math.cos(phi) * math.cos(decl) * math.cos(ha))
      .clamp(-1.0, 1.0);
  final zenith = math.acos(cosZen);
  // 남쪽 기준 방위를 atan2로 구한 뒤 북쪽 기준으로 돌린다.
  final azFromSouth = math.atan2(
    math.sin(ha),
    math.cos(ha) * math.sin(phi) - math.tan(decl) * math.cos(phi),
  );
  final azimuth = (_deg(azFromSouth) + 180) % 360;
  return SunPosition(90 - _deg(zenith), azimuth);
}

/// 한국 시각 [year]-[month]-[day] [minuteOfDay]분을 UTC로.
DateTime kstToUtc(int year, int month, int day, int minuteOfDay) =>
    DateTime.utc(year, month, day).add(Duration(minutes: minuteOfDay)).subtract(_kst);

/// 지금 한국 날짜와 자정 이후 분.
({int year, int month, int day, int minute}) nowInKst([DateTime? now]) {
  final k = (now ?? DateTime.now()).toUtc().add(_kst);
  return (year: k.year, month: k.month, day: k.day, minute: k.hour * 60 + k.minute);
}

/// 그날 해 뜨는·지는 시각(한국 시각, 자정 이후 분). 1분 간격으로 해 높이가
/// 0을 지나는 곳을 찾는다.
({int sunrise, int sunset}) sunriseSunsetKst(int year, int month, int day) {
  int? rise, set;
  var prevUp = sunPositionAt(kstToUtc(year, month, day, 0)).isUp;
  for (var m = 1; m < 24 * 60; m++) {
    final up = sunPositionAt(kstToUtc(year, month, day, m)).isUp;
    if (up && !prevUp) rise ??= m;
    if (!up && prevUp) set = m;
    prevUp = up;
  }
  return (sunrise: rise ?? 6 * 60, sunset: set ?? 18 * 60);
}

/// 높이 [heightM]인 물체의 그림자 끝이 발밑에서 떨어진 거리(지도 월드
/// 좌표, 미터). 해가 졌으면 null. 해가 지평선에 붙으면 그림자가 끝없이
/// 길어지므로 [maxLength]에서 자른다.
Offset? shadowOffset(SunPosition sun, double heightM, {double maxLength = 300}) {
  if (!sun.isUp) return null;
  final len = math.min(heightM / math.tan(_rad(sun.altitude)), maxLength);
  final a = _rad(sun.azimuth);
  // 해를 향하는 방향은 월드 (sin A, -cos A)(x=동, y=남). 그림자는 그 반대.
  return Offset(-math.sin(a) * len, math.cos(a) * len);
}

/// 건물 하나의 그림자 모양(월드 좌표). 바닥과 밀린 바닥을 감싼다.
List<Offset> shadowPolygon(List<Offset> ring, Offset offset) =>
    computeConvexHull([...ring, for (final p in ring) p + offset]);

/// 모든 건물의 그림자를 화면(투영) 좌표 경로 하나로. 해가 졌으면 null.
Path? buildShadowPath(
  Iterable<BaseBuilding> buildings,
  IsoProjection proj,
  SunPosition sun,
) {
  if (!sun.isUp) return null;
  final path = Path();
  for (final b in buildings) {
    if (b.ring.length < 3) continue;
    final d = shadowOffset(sun, proj.heightOf(b));
    if (d == null) return null;
    final z = buildingBaseZ(b);
    final poly = [for (final p in shadowPolygon(b.ring, d)) proj.project(p.dx, p.dy, z)];
    if (poly.length >= 3) path.addPolygon(poly, true);
  }
  return path;
}

/// '오전 9:05' 같은 한국어 시각.
String formatKstMinute(int minute) {
  final h = minute ~/ 60, m = minute % 60;
  final ampm = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$ampm $h12:${m.toString().padLeft(2, '0')}';
}
