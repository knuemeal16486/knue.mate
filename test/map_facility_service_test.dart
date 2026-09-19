import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/map_facility_service.dart';

void main() {
  group('AdminMapFacility', () {
    test('저장했다가 읽으면 그대로 돌아온다', () {
      const f = AdminMapFacility(
        id: 'doc1',
        name: '테스트 카페',
        typeKey: 'cafe',
        lat: 36.6093,
        lng: 127.3585,
        detail: '09:00~18:00',
      );
      final restored = AdminMapFacility.fromMap('doc1', f.toFirestore());
      expect(restored?.name, '테스트 카페');
      expect(restored?.typeKey, 'cafe');
      expect(restored?.lat, 36.6093);
      expect(restored?.lng, 127.3585);
      expect(restored?.detail, '09:00~18:00');
    });

    test('설명 없이도 왕복한다', () {
      const f = AdminMapFacility(
        id: 'doc2',
        name: '테스트 정류장',
        typeKey: 'bus_stop',
        lat: 36.61,
        lng: 127.36,
      );
      final restored = AdminMapFacility.fromMap('doc2', f.toFirestore());
      expect(restored?.detail, isNull);
    });

    test('필수 필드가 없으면 무시한다', () {
      expect(AdminMapFacility.fromMap('x', {'name': 'a'}), isNull);
      expect(
        AdminMapFacility.fromMap('x', {'name': 'a', 'type': 'cafe'}),
        isNull,
      );
      expect(
        AdminMapFacility.fromMap(
          'x',
          {'name': 'a', 'type': 'cafe', 'lat': 1, 'lng': 1},
        ),
        isNotNull,
      );
    });

    test('id는 문서 id를 그대로 쓴다', () {
      final restored = AdminMapFacility.fromMap('abc123', {
        'name': 'a',
        'type': 'cafe',
        'lat': 1,
        'lng': 1,
      });
      expect(restored?.id, 'abc123');
    });
  });
}
