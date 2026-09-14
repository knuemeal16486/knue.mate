import 'dart:math' as math;
import 'dart:ui';

/// 간단한 위도/경도 구조체
class LatLng {
  final double lat; // 위도
  final double lng; // 경도
  const LatLng(this.lat, this.lng);
}

/// 지도 좌표 → 화면 오프셋 변환 (간단한 등거리 투영)
/// center는 화면 중심(보통 대학 중심) 좌표, scale은 화면 확대 배율.
Offset latLngToOffset(LatLng point, LatLng center, double scale) {
  // 1° 위도 ≈ 111 km, 1° 경도 ≈ 111 km * cos(lat)
  final degPerMeter = 1 / 111320.0;
  final dLatDeg = (point.lat - center.lat) * degPerMeter * 1000.0; // km -> m
  final dLngDeg = (point.lng - center.lng) * degPerMeter * 1000.0 * math.cos(center.lat * math.pi / 180);
  // 여기서는 x = 동쪽 거리, y = 남북 거리(위쪽이 negative)
  final dx = dLngDeg * scale;
  final dy = -dLatDeg * scale;
  return Offset(dx, dy);
}
