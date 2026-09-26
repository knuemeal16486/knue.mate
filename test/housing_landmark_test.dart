import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_landmark.dart';
import 'package:knue_mate/housing_model.dart';

void main() {
  tearDown(() => kPlacedLandmarkPositions.value = const {});

  group('찍은 위치 저장·읽기', () {
    test('지도 좌표로 찍어 경위도로 저장하고, 되읽으면 같은 자리', () {
      final l = HousingLandmark.atWorld(
        id: 'lm_1',
        kind: HousingLandmarkKind.backGate,
        name: '',
        world: const Offset(120.5, -48.25),
      );
      final back = HousingLandmark.fromMap('lm_1', l.toFirestore())!;
      expect(back.kind, HousingLandmarkKind.backGate);
      expect(back.world.dx, closeTo(120.5, 1e-6));
      expect(back.world.dy, closeTo(-48.25, 1e-6));
      expect(back.label, '후문', reason: '이름을 비우면 종류 이름');
    });

    test('종류나 좌표가 없는 문서는 버린다', () {
      expect(HousingLandmark.fromMap('x', {'kind': 'busStop', 'lon': 127.3}), isNull);
      expect(HousingLandmark.fromMap('x', {'kind': 'nope', 'lon': 127.3, 'lat': 36.6}), isNull);
      expect(HousingLandmark.fromMap('x', {'kind': 'sideGate', 'lon': 127.3, 'lat': 36.6})?.label, '쪽문');
    });

    test('옮기면 좌표만 바뀌고 이름·종류는 그대로', () {
      final l = HousingLandmark.atWorld(id: 'a', kind: HousingLandmarkKind.busStop, name: '탑연삼거리', world: Offset.zero);
      final moved = l.copyWith(world: const Offset(10, 20));
      expect(moved.name, '탑연삼거리');
      expect(moved.world.dx, closeTo(10, 1e-6));
      expect(moved.world.dy, closeTo(20, 1e-6));
    });
  });

  group('찍은 위치가 캠퍼스 거점을 대신한다', () {
    HousingLandmark lm(String id, HousingLandmarkKind k, String name, Offset w) =>
        HousingLandmark.atWorld(id: id, kind: k, name: name, world: w);

    test('정문은 먼저 찍은 것, 탑연 정류장은 이름으로', () {
      final o = campusLandmarkOverrides([
        lm('1', HousingLandmarkKind.busStop, '교원대 정문', const Offset(5, 5)),
        lm('2', HousingLandmarkKind.mainGate, '', const Offset(1, 2)),
        lm('3', HousingLandmarkKind.mainGate, '', const Offset(9, 9)),
        lm('4', HousingLandmarkKind.busStop, '탑연삼거리', const Offset(-200, 300)),
        lm('5', HousingLandmarkKind.backGate, '', const Offset(0, 0)),
      ]);
      expect(o.keys.toSet(), {CampusLandmark.mainGate, CampusLandmark.topyeonStop});
      expect(o[CampusLandmark.mainGate]!.dx, closeTo(1, 1e-6));
      expect(o[CampusLandmark.topyeonStop]!.dx, closeTo(-200, 1e-6));
    });

    test('도보 거리와 등시선이 찍은 정문을 쓴다', () {
      const b = Offset(100, 205);
      final before = walkingDistanceMeters(b, CampusLandmark.mainGate);
      kPlacedLandmarkPositions.value = {CampusLandmark.mainGate: const Offset(100, 105)};
      expect(walkingDistanceMeters(b, CampusLandmark.mainGate), 120); // 100m × 보행 계수 1.2
      expect(walkingDistanceMeters(b, CampusLandmark.mainGate), isNot(before));
      expect(IsochroneCenter.landmark(CampusLandmark.mainGate).position, const Offset(100, 105));
      // 찍지 않은 거점은 그대로.
      expect(landmarkPosition(CampusLandmark.library), CampusLandmark.library.position);
    });
  });
}
