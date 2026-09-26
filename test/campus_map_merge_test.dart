import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/building_data.dart';
import 'package:knue_mate/campus_building_info.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

BuildingData _info(String name, LatLng at, {String? short}) => BuildingData(
      name: name,
      shortName: short ?? name,
      description: '$name 설명',
      position: at,
      color: Colors.blue,
      floors: const [FloorData(floor: 1, rooms: ['101호'])],
    );

/// 지도 좌표 [world] 둘레 10m 네모 건물.
BaseBuilding _box(String id, Offset world, {String? name, bool campus = true}) => BaseBuilding(
      id: id,
      floors: 4,
      isCampus: campus,
      officialName: name,
      ring: [
        world + const Offset(-5, -5),
        world + const Offset(5, -5),
        world + const Offset(5, 5),
        world + const Offset(-5, 5),
      ],
    );

LatLng _latLng(Offset world) {
  final (lon, lat) = housingWorldToLonLat(world);
  return LatLng(lat, lon);
}

void main() {
  group('캠퍼스맵 건물 정보를 3D 건물에 잇기', () {
    test('이름이 같으면 좌표가 떨어져 있어도 그 건물(캠퍼스맵 좌표는 마커 한 점이다)', () {
      final out = matchCampusInfo(
        [_box('a', const Offset(0, 0), name: '인문과학관'), _box('b', const Offset(40, 0), name: '제2대학')],
        // 좌표는 제2대학 쪽에 더 가깝다 — 그래도 이름이 이긴다.
        [_info('인문과학관', _latLng(const Offset(35, 0)))],
      );
      expect(out.keys, ['a']);
    });

    // 미래도서관을 실제 모양대로 둘로 쪼갠 경우 — 어느 조각을 눌러도 같은 안내.
    test('같은 이름 조각이 여럿이면 모두에 붙인다', () {
      final out = matchCampusInfo(
        [_box('main', const Offset(0, 0), name: '미래도서관'), _box('piece', const Offset(60, 0), name: '미래도서관')],
        [_info('미래도서관', _latLng(const Offset(0, 0)))],
      );
      expect(out.keys.toSet(), {'main', 'piece'});
    });

    // 이름표를 숨긴 교내 건물이 원래 이름("신규 원룸")으로 대신 뜨던 문제.
    testWidgets('이름표를 숨긴 교내 건물은 원래 이름으로도 뜨지 않는다', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final piece = _box('piece', const Offset(0, 0), name: '신규 원룸');
      final shown = layoutBuildings([piece], const IsoProjection(scale: 2));
      expect(shown.single.displayName, '신규 원룸', reason: '숨기지 않으면 교내 공식 명칭을 단다');
      final hidden = layoutBuildings([piece], const IsoProjection(scale: 2), hiddenLabelIds: {'piece'});
      expect(hidden.single.displayName, isNull);
      await tester.pump();
      tester.takeException(); // 이름표 글꼴(google_fonts)이 테스트에 없어 남기는 예외 — 무관
    });

    test('여러 동으로 나뉜 건물은 모든 동에 붙인다', () {
      final out = matchCampusInfo(
        [_box('a', const Offset(0, 0), name: '다감관 A동'), _box('b', const Offset(20, 0), name: '다감관 B동')],
        [_info('다감관', _latLng(const Offset(10, 0)))],
      );
      expect(out.keys.toSet(), {'a', 'b'});
    });

    test('이름이 없으면 60m 안의 가장 가까운 교내 건물, 멀면 잇지 않는다', () {
      final buildings = [
        _box('near', const Offset(0, 0)),
        _box('room', const Offset(3, 0), campus: false), // 교외는 후보가 아니다
      ];
      expect(matchCampusInfo(buildings, [_info('학군단', _latLng(const Offset(20, 0)))]).keys, ['near']);
      expect(matchCampusInfo(buildings, [_info('학군단', _latLng(const Offset(200, 0)))]), isEmpty);
    });

    test('약칭으로도 맞춘다', () {
      final out = matchCampusInfo(
        [_box('a', const Offset(0, 0), name: '종교관')],
        [_info('종합교육관', _latLng(const Offset(0, 0)), short: '종교관')],
      );
      expect(out['a']?.name, '종합교육관');
    });

    test('층 이름', () {
      expect(floorLabel(1), '1층');
      expect(floorLabel(-1), '지하 1층');
      expect(floorLabel('B2'), '지하 2층');
      expect(floorLabel('3F'), '3층');
      expect(floorLabel('옥상'), '옥상');
    });
  });

  // 캠퍼스맵 탭에 끼운 3D 지도: 인문과학관에서 시작, 교내 이름표만, 자취방 칩 숨김,
  // 장소 탭의 위도·경도 이동 요청을 받는다.
  testWidgets('캠퍼스 모드 지도', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.isAdmin.value = false;
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final focus = ValueNotifier<HousingFocusRequest?>(null);
    await tester.pumpWidget(MaterialApp(home: HousingScreen(campusMode: true, focusRequests: focus)));
    for (var i = 0; i < 40 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    HousingMapPainter painter() =>
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((c) => c.painter).whereType<HousingMapPainter>().first;

    // 모드 칩은 있고 자취방 전용 칩은 없다
    expect(find.text('캠퍼스'), findsOneWidget);
    expect(find.text('자취방'), findsOneWidget);
    expect(find.text('월 35 이하'), findsNothing);
    // 이름표는 교내 건물에만
    final labeled = painter().buildings.where((b) => b.displayName != null).toList();
    expect(labeled, isNotEmpty);
    expect(labeled.every((b) => b.building.isCampus), isTrue);

    // [자취방]으로 바꾸면 원룸 이름표·칩이 돌아온다
    await tester.tap(find.text('자취방'));
    await tester.pump();
    expect(find.text('월 35 이하'), findsOneWidget);
    expect(painter().buildings.any((b) => b.displayName != null && !b.building.isCampus), isTrue);

    // 장소 탭이 보낸 인문과학관 위도·경도로 옮겨 가고 캠퍼스 모드로 돌아온다
    final before = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.clone();
    focus.value = const HousingFocusRequest.at(36.6105993, 127.3598135, 1);
    await tester.pump();
    final after = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value;
    expect(after, isNot(before));
    expect(find.text('월 35 이하'), findsNothing);

    tester.takeException(); // 이름표용 google_fonts가 테스트에서 남기는 예외 — 무관
  });
}
