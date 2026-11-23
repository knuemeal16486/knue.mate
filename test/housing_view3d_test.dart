import 'dart:math' as math;
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:knue_mate/housing_view3d.dart';
import 'package:knue_mate/housing_view3d_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _size = Size(400, 800);

View3BuildingSpec _box(String id, Rect r, {int floors = 3, String? name}) =>
    View3BuildingSpec(
      building: BaseBuilding(
        id: id,
        floors: floors,
        ring: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
      ),
      color: Colors.white,
      name: name,
    );

View3Scene _flat(List<View3BuildingSpec> buildings, {List<OsmRoad> roads = const []}) =>
    View3Scene.build(
      world: const Rect.fromLTRB(-200, -200, 200, 200),
      buildings: buildings,
      roads: roads,
      elevation: (_, _) => 0,
    );

void main() {
  group('카메라·투영', () {
    test('북쪽을 보면 동쪽이 화면 오른쪽, 높은 곳이 화면 위다(좌우가 안 뒤집힌다)', () {
      const cam = View3Camera(x: 0, y: 0, z: 2, yaw: 0, pitch: 0);
      final p = View3Projector(cam, _size);
      // y는 남쪽이 +라서 북쪽은 -.
      expect(p.project(0, -50, 2), const Offset(200, 400));
      expect(p.project(10, -50, 2)!.dx, greaterThan(200));
      expect(p.project(0, -50, 12)!.dy, lessThan(400));
      expect(p.project(0, 50, 2), isNull, reason: '뒤에 있는 점은 못 그린다');
    });

    test('동쪽(90°)을 보면 남쪽이 화면 오른쪽이다', () {
      const cam = View3Camera(x: 0, y: 0, z: 2, yaw: math.pi / 2, pitch: 0);
      final p = View3Projector(cam, _size);
      expect(p.project(50, 10, 2)!.dx, greaterThan(200));
    });

    test('내려다보는 카메라는 어느 방향·기울기에서도 목표를 화면 한가운데 둔다', () {
      for (final az in [0.0, 1.0, 2.5, -2.0]) {
        for (final tilt in [0.25, 0.7, 1.5]) {
          final cam = View3Camera.orbit(
            target: const Offset(30, -40),
            targetZ: 5,
            distance: 300,
            azimuth: az,
            tilt: tilt,
          );
          final at = View3Projector(cam, _size).project(30, -40, 5)!;
          expect(at.dx, closeTo(200, 1e-6));
          expect(at.dy, closeTo(400, 1e-6));
          expect(cam.z, greaterThan(5), reason: '땅 위에 떠 있다');
        }
      }
    });

    test('위로 볼수록 지평선이 화면 아래로 내려간다', () {
      double horizon(double pitch) => View3Projector(
            View3Camera(x: 0, y: 0, z: 2, yaw: 0, pitch: pitch),
            _size,
          ).horizonY;
      expect(horizon(0), 400);
      expect(horizon(0.3), greaterThan(400));
      expect(horizon(-0.3), lessThan(400));
    });

    test('지도 회전값을 둘러보기 방위로 옮긴다', () {
      // 지도는 회전 0일 때 북서쪽이 화면 위.
      expect(view3AzimuthFromMap(0), closeTo(-math.pi / 4, 1e-9));
      expect(view3AzimuthFromMap(0, topDown: true), 0);
      // 지도의 화면 위 방향(월드)과 둘러보기 카메라의 앞 방향이 같아야 한다.
      for (final r in [0.0, 0.8, 2.0, 4.5]) {
        final proj = IsoProjection(rotation: r);
        final up = proj.unproject(0, -10) - proj.unproject(0, 0);
        final cam = View3Camera(
          x: 0, y: 0, z: 0, yaw: view3AzimuthFromMap(r), pitch: 0,
        );
        final f = cam.forwardH;
        expect(f.dx, closeTo(up.dx / up.distance, 1e-6));
        expect(f.dy, closeTo(up.dy / up.distance, 1e-6));
      }
    });
  });

  group('가까운 면 자르기', () {
    final p = View3Projector(
      const View3Camera(x: 0, y: 0, z: 0, yaw: 0, pitch: 0),
      _size,
    );
    List<double> v(double x, double y, double z) => [x, y, z, 0, 0];

    int run(List<double> a, List<double> b, List<double> c, [List<Offset>? out]) =>
        clipAndEmit(p, (sx, sy, u, v, color) {
          expect(sx.isFinite && sy.isFinite, isTrue);
          out?.add(Offset(sx, sy));
        }, a, b, c, 1, 2, 3);

    test('전부 앞이면 그대로 1개, 전부 뒤면 0개', () {
      expect(run(v(0, 0, 5), v(1, 0, 5), v(0, 1, 5)), 1);
      expect(run(v(0, 0, -5), v(1, 0, -5), v(0, 1, -5)), 0);
    });

    test('하나만 앞이면 1개, 둘이 앞이면 2개로 잘린다', () {
      final one = <Offset>[];
      expect(run(v(0, 0, 5), v(1, 0, -5), v(0, 1, -5), one), 1);
      expect(one, hasLength(3));
      final two = <Offset>[];
      expect(run(v(0, 0, 5), v(1, 0, 5), v(0, 1, -5), two), 2);
      expect(two, hasLength(6));
    });

    test('어느 꼭짓점이 뒤에 있든 같은 개수로 잘린다', () {
      final pts = [v(0, 0, 5), v(1, 0, 5), v(0, 1, -5)];
      for (var s = 0; s < 3; s++) {
        expect(run(pts[s % 3], pts[(s + 1) % 3], pts[(s + 2) % 3]), 2);
      }
      final one = [v(0, 0, -5), v(1, 0, -5), v(0, 1, 5)];
      for (var s = 0; s < 3; s++) {
        expect(run(one[s % 3], one[(s + 1) % 3], one[(s + 2) % 3]), 1);
      }
    });
  });

  group('건물 모양', () {
    // ㄱ자: 부채꼴로 나누면 바깥으로 삐져나오는 모양.
    const lShape = [
      Offset(0, 0), Offset(10, 0), Offset(10, 4), Offset(4, 4),
      Offset(4, 10), Offset(0, 10), Offset(0, 0), // 끝점 중복
    ];

    test('끝점 중복을 빼고 방향을 맞춘다', () {
      final ring = normalizeRing(lShape);
      expect(ring, hasLength(6));
      expect(signedArea(ring), greaterThan(0));
      expect(signedArea(normalizeRing(lShape.reversed.toList())), greaterThan(0));
    });

    test('ㄱ자 지붕을 넓이 그대로, 안쪽으로만 나눈다', () {
      final ring = normalizeRing(lShape);
      final tris = triangulate(ring);
      expect(tris.length, (ring.length - 2) * 3);
      var area = 0.0;
      for (var t = 0; t < tris.length; t += 3) {
        final tri = [ring[tris[t]], ring[tris[t + 1]], ring[tris[t + 2]]];
        area += signedArea(tri).abs();
        final c = (tri[0] + tri[1] + tri[2]) / 3;
        expect(pointInRing(c, ring), isTrue, reason: '삼각형이 건물 밖으로 나갔다');
      }
      expect(area, closeTo(signedArea(ring), 1e-6)); // 64㎡
    });

    test('건물은 비탈의 낮은 쪽 땅에 서고, 지붕은 층수만큼 올라간다', () {
      final scene = View3Scene.build(
        world: const Rect.fromLTRB(-100, -100, 100, 100),
        buildings: [_box('a', const Rect.fromLTRB(0, 0, 20, 10), floors: 4)],
        elevation: (x, _) => x * 0.1, // 동쪽으로 오르막
      );
      final b = scene.buildings.single;
      expect(b.baseZ, closeTo(0, 1e-6));
      expect(b.topZ, closeTo(1.0 + 12, 1e-6)); // 가운데 땅 1m + 4층×3m
    });
  });

  group('벽 밑동', () {
    // 동쪽으로 갈수록 높고, 가운데가 불룩한 땅.
    double hill(double x, double y) => x * 0.08 + 6 * math.exp(-(x * x + y * y) / 3000);
    final scene = View3Scene.build(
      world: const Rect.fromLTRB(-200, -200, 200, 200),
      buildings: [_box('a', const Rect.fromLTRB(-13, -9, 17, 11))],
      elevation: hill,
    );
    final b = scene.buildings.single;

    test('그려지는 땅 높이는 격자 꼭짓점에서 실제 높이와 같고 칸 안에서는 다르다', () {
      expect(scene.meshHeightAt(20, 20), closeTo(hill(20, 20), 1e-4));
      expect((scene.meshHeightAt(10, 10) - hill(10, 10)).abs(), greaterThan(0.1));
      // 대각선 양쪽이 이어진다.
      expect(
        (scene.meshHeightAt(10.001, 10) - scene.meshHeightAt(10, 10.001)).abs(),
        lessThan(0.01),
      );
    });

    test('벽은 모든 모서리에서 그려지는 땅보다 아래까지 내려간다', () {
      expect(b.footZ, hasLength(b.ring.length));
      for (var i = 0; i < b.ring.length; i++) {
        final p = b.ring[i];
        expect(b.footZ[i], lessThan(scene.meshHeightAt(p.dx, p.dy) - 0.5));
        expect(b.footZ[i], lessThan(scene.groundAt(p.dx, p.dy) - 0.5));
      }
      expect(b.footZ.first, lessThan(b.baseZ));
    });
  });

  group('길', () {
    const roads = [
      OsmRoad(kind: 'road', widthM: 6, name: '월탄3길', points: [Offset(0, 0), Offset(100, 0)]),
      OsmRoad(kind: 'walk', widthM: 2, points: [Offset(0, 50), Offset(100, 50)]),
    ];

    test('길 띠는 길 폭만큼 벌어지고 긴 구간은 쪼개진다', () {
      final strip = View3Road.build(roads.first, (_, _) => 0)!;
      expect(strip.length, greaterThan(2), reason: '100m 구간을 12m마다 쪼갠다');
      final w = Offset(strip.left[0] - strip.right[0], strip.left[1] - strip.right[1]);
      expect(w.distance, closeTo(6, 1e-4));
      expect(_flat(const [], roads: roads).roads, hasLength(2));
    });
  });

  group('실측 높이 격자', () {
    final dem = CampusDem.fromJson({
      'minX': 0, 'minY': 0, 'step': 30, 'nx': 3, 'ny': 2,
      // 0.1m 단위: 윗줄 10·20·30m, 아랫줄 40·50·60m
      'h': [100, 200, 300, 400, 500, 600],
    });

    test('격자점은 그대로, 사이는 선형 보간한다', () {
      expect(dem.at(0, 0), closeTo(10, 1e-4));
      expect(dem.at(60, 30), closeTo(60, 1e-4));
      expect(dem.at(15, 0), closeTo(15, 1e-4));
      expect(dem.at(30, 15), closeTo(35, 1e-4));
    });

    test('격자 밖은 가장자리 값이다(튀지 않는다)', () {
      expect(dem.at(-500, -500), closeTo(10, 1e-4));
      expect(dem.at(999, 999), closeTo(60, 1e-4));
    });
  });

  test('앞 건물에 가려진 건물 이름표는 숨긴다', () {
    final scene = _flat([
      _box('front', const Rect.fromLTRB(-10, -30, 10, -20), floors: 5),
      _box('back', const Rect.fromLTRB(-10, -80, 10, -70), floors: 2),
    ]);
    final back = scene.buildings.firstWhere((b) => b.spec.building.id == 'back');
    // 눈높이에서는 5층 건물 뒤의 2층 건물이 안 보인다.
    expect(
      scene.sightBlocked(Offset.zero, 1.7, back.center, back.topZ, except: back),
      isTrue,
    );
    // 높이 올라가면 넘어다 보인다.
    expect(
      scene.sightBlocked(Offset.zero, 200, back.center, back.topZ, except: back),
      isFalse,
    );
    // 옆으로 비켜서면 보인다.
    expect(
      scene.sightBlocked(const Offset(60, 0), 1.7, back.center, back.topZ, except: back),
      isFalse,
    );
  });

  testWidgets('어느 시점에서 그려도 예외가 없다(땅 그림이 없어도)', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final scene = View3Scene.build(
      world: kView3World,
      buildings: [
        _box('a', const Rect.fromLTRB(10, -10, 30, 10), name: '가온빌'),
        _box('b', const Rect.fromLTRB(-40, -60, -20, -30), floors: 6),
      ],
      roads: const [
        OsmRoad(kind: 'road', widthM: 6, points: [Offset(-100, 0), Offset(100, 0)]),
      ],
    );
    for (final cam in [
      View3Camera.orbit(
        target: Offset.zero, targetZ: 0, distance: 400, azimuth: 0.6, tilt: 0.7,
      ),
      // 건물 벽 바로 앞 눈높이 — 삼각형이 카메라 뒤로 넘어가는 경우.
      const View3Camera(x: 9, y: 0, z: 1.7, yaw: 1.2, pitch: 0.1),
      const View3Camera(x: 0, y: 0, z: 1.7, yaw: -2.0, pitch: -0.5),
    ]) {
      for (final isDark in [false, true]) {
        final rec = PictureRecorder();
        View3Painter(scene: scene, camera: ValueNotifier(cam), isDark: isDark)
            .paint(Canvas(rec), _size);
        rec.endRecording().dispose();
      }
    }
    tester.takeException(); // 대체 글꼴 경고
  });

  testWidgets('지도의 3D 버튼으로 들어가 둘러본다', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.isAdmin.value = false;
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: HousingScreen(isEmbedded: true, campusMode: true)),
    );
    for (var i = 0; i < 40 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('3D 둘러보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HousingView3DScreen), findsOneWidget);
    // 실측 높이(에셋)를 읽은 뒤에 장면이 뜬다.
    for (var i = 0; i < 40 && find.byType(CustomPaint).evaluate().isEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty && i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 걸어보기는 없앴다(2026-11-16).
    expect(find.textContaining('걸어보기'), findsNothing);
    expect(find.text('한 손가락: 이동 · 두 손가락: 회전·확대·기울이기'), findsOneWidget);
    // 도로가 OSM 데이터라 출처 표기가 있어야 한다(ODbL).
    expect(find.text('도로 © OpenStreetMap 기여자'), findsWidgets);

    // 끌어서 옮기고 돌려도 예외가 없다.
    await tester.drag(find.byType(HousingView3DScreen), const Offset(80, 40));
    await tester.pump();
    await tester.tap(find.byTooltip('확대'));
    await tester.tap(find.byTooltip('북쪽 보기'));
    await tester.pump();
    tester.takeException(); // 대체 글꼴 경고
  });
}
