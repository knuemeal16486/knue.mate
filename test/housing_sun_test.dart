import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_sun.dart';

void main() {
  group('해의 위치 (교원대, 북위 36.6°)', () {
    // 남중 고도 = 90 − 위도 + 적위. 하지 적위 +23.4°, 동지 −23.4°.
    test('하지 정오 무렵 해는 남쪽 높이 약 77°', () {
      final noon = _highest(2026, 6, 21);
      expect(noon.altitude, closeTo(76.8, 1));
      expect(noon.azimuth, closeTo(180, 3));
    });

    test('동지 정오 무렵 해는 남쪽 높이 약 30°', () {
      final noon = _highest(2026, 12, 21);
      expect(noon.altitude, closeTo(30.0, 1));
      expect(noon.azimuth, closeTo(180, 3));
    });

    test('아침엔 동쪽, 저녁엔 서쪽에 있다', () {
      final morning = sunPositionAt(kstToUtc(2026, 9, 25, 8 * 60));
      final evening = sunPositionAt(kstToUtc(2026, 9, 25, 17 * 60));
      expect(morning.azimuth, inInclusiveRange(80, 140));
      expect(evening.azimuth, inInclusiveRange(220, 280));
    });

    test('자정엔 해가 없다', () {
      expect(sunPositionAt(kstToUtc(2026, 9, 25, 0)).isUp, isFalse);
    });
  });

  group('해 뜨고 지는 시각 (한국 시각)', () {
    // 청주 기준 천문 자료: 하지 일출 약 5:15·일몰 19:55, 동지 일출 7:40·일몰 17:20.
    test('하지', () {
      final t = sunriseSunsetKst(2026, 6, 21);
      expect(t.sunrise, closeTo(5 * 60 + 15, 8));
      expect(t.sunset, closeTo(19 * 60 + 55, 8));
    });

    test('동지', () {
      final t = sunriseSunsetKst(2026, 12, 21);
      expect(t.sunrise, closeTo(7 * 60 + 40, 8));
      expect(t.sunset, closeTo(17 * 60 + 20, 8));
    });
  });

  group('그림자', () {
    test('해가 45° 높이면 그림자 길이 = 건물 높이, 해 반대쪽으로', () {
      // 해가 정남(180°)에 있으면 그림자는 북쪽(월드 y −)으로 진다.
      final d = shadowOffset(const SunPosition(45, 180), 12)!;
      expect(d.dx, closeTo(0, 1e-9));
      expect(d.dy, closeTo(-12, 1e-9));
      // 해가 동쪽(90°)이면 그림자는 서쪽(x −).
      final w = shadowOffset(const SunPosition(45, 90), 12)!;
      expect(w.dx, closeTo(-12, 1e-9));
    });

    test('해가 낮을수록 길어지되 끝없이 길어지진 않고, 지면 없다', () {
      final low = shadowOffset(const SunPosition(10, 180), 12)!;
      expect(low.distance, closeTo(12 / math.tan(10 * math.pi / 180), 1e-6));
      expect(shadowOffset(const SunPosition(0.1, 180), 12)!.distance, 300);
      expect(shadowOffset(const SunPosition(-5, 180), 12), isNull);
    });

    test('그림자 모양은 바닥과 밀린 바닥을 모두 덮는다', () {
      const ring = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];
      final poly = shadowPolygon(ring, const Offset(0, -20));
      for (final p in [const Offset(0, 10), const Offset(10, 10), const Offset(0, -20), const Offset(10, -20)]) {
        expect(poly, contains(p));
      }
    });
  });

  test('시각 표기', () {
    expect(formatKstMinute(9 * 60 + 5), '오전 9:05');
    expect(formatKstMinute(12 * 60), '오후 12:00');
    expect(formatKstMinute(17 * 60 + 30), '오후 5:30');
    expect(formatKstMinute(0), '오전 12:00');
  });
}

/// 그날 해가 가장 높을 때의 위치(1분 간격으로 찾음).
SunPosition _highest(int y, int m, int d) {
  var best = sunPositionAt(kstToUtc(y, m, d, 0));
  for (var min = 1; min < 24 * 60; min++) {
    final s = sunPositionAt(kstToUtc(y, m, d, min));
    if (s.altitude > best.altitude) best = s;
  }
  return best;
}
