import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';

void main() {
  group('경위도 ↔ 지도 좌표', () {
    test('원점은 (0, 0)이고 x는 동쪽, y는 남쪽이 +다', () {
      expect(lonLatToHousingWorld(kHousingOriginLon, kHousingOriginLat), Offset.zero);
      final east = lonLatToHousingWorld(kHousingOriginLon + 0.001, kHousingOriginLat);
      final south = lonLatToHousingWorld(kHousingOriginLon, kHousingOriginLat - 0.001);
      // tool/fetch_osm_roads.js와 같은 환산: 위도 1도 = 111320m, 경도는 cos(위도)배.
      expect(east.dx, closeTo(89.35, 0.05));
      expect(east.dy, 0);
      expect(south.dy, closeTo(111.32, 0.01));
    });

    test('되돌리면 같은 경위도', () {
      const lon = 127.3601, lat = 36.6051;
      final (lon2, lat2) = housingWorldToLonLat(lonLatToHousingWorld(lon, lat));
      expect(lon2, closeTo(lon, 1e-9));
      expect(lat2, closeTo(lat, 1e-9));
    });
  });

  group('위에서 보기(평면 시점)', () {
    const top = IsoProjection(scale: 2, topDown: true);

    test('북쪽이 위, 동쪽이 오른쪽이고 높이는 무시한다', () {
      final east = top.project(10, 0);
      final south = top.project(0, 10);
      expect(east.dx, greaterThan(0));
      expect(east.dy, 0);
      expect(south.dx, 0);
      expect(south.dy, greaterThan(0));
      expect(top.project(10, 5, 30), top.project(10, 5));
    });

    test('거리가 방향과 상관없이 같은 비율로 줄어든다(원이 원으로 보인다)', () {
      expect(top.project(10, 0).distance, closeTo(top.project(0, 10).distance, 1e-9));
      expect(top.project(0, 10).distance, closeTo(top.project(7.071, 7.071).distance, 1e-3));
    });

    test('화면 좌표를 되돌리면 같은 지점 — 회전해도', () {
      for (final r in [0.0, 0.7, 2.5]) {
        final p = IsoProjection(scale: 2.2, rotation: r, topDown: true);
        final s = p.project(123.4, -56.7);
        final back = p.unproject(s.dx, s.dy);
        expect(back.dx, closeTo(123.4, 1e-9));
        expect(back.dy, closeTo(-56.7, 1e-9));
      }
    });
  });
}
