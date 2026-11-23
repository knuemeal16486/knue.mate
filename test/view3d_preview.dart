// 3D 둘러보기를 파일로 떠서 눈으로 확인하는 도구. 테스트가 아니다.
// (파일명이 _test.dart로 끝나지 않아 `flutter test`가 자동으로 집지 않는다)
//
//   flutter test test/view3d_preview.dart
//   → build/view3d/*.png  (위에서 본 장면 · 언덕, 밝은/어두운 모드)
//
// 앱의 View3Painter와 땅 그림 굽기를 **그대로** 쓴다. 이름표는 대체 글꼴이라
// 네모로 보이고, google_fonts 예외로 "실패"가 찍히지만 PNG는 정상 생성된다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:knue_mate/housing_view3d.dart';
import 'package:knue_mate/housing_view3d_screen.dart';

const _size = Size(412, 860);
const _dpr = 2.0;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('둘러보기 미리보기 PNG', (tester) async {
    Directory('build/view3d').createSync(recursive: true);
    final loaded = await tester.runAsync(() async {
      final base = await CampusBase.load();
      final osm = await CampusBase.loadOsmRoads();
      final dem = await CampusDem.load();
      return (base, osm, dem);
    });
    final (base, osm, dem) = loaded!;

    for (final isDark in [false, true]) {
      final style = housingMapStyle(base.buildings);
      final iso = layoutBuildings(
        base.buildings,
        const IsoProjection(),
        oneRoomIds: style.oneRoomIds,
        zoneColors: style.zoneColors,
        displayNames: style.displayNames,
      );
      final scene = View3Scene.build(
        world: kView3World,
        buildings: view3SpecsFrom(iso, isDark),
        roads: osm,
        elevation: dem.exaggerated,
      );
      final ground = await tester.runAsync(
        () => renderView3Ground(base: base, osmRoads: osm, isDark: isDark),
      );

      Future<void> shoot(String name, View3Camera cam) async {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)..scale(_dpr);
        final sw = Stopwatch()..start();
        View3Painter(
          scene: scene,
          camera: ValueNotifier(cam),
          ground: ground,
          isDark: isDark,
        ).paint(canvas, _size);
        final ms = sw.elapsedMicroseconds / 1000;
        final pic = rec.endRecording();
        final out = 'build/view3d/$name${isDark ? '_dark' : ''}.png';
        await tester.runAsync(() async {
          final img = await pic.toImage(
            (_size.width * _dpr).round(),
            (_size.height * _dpr).round(),
          );
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File(out).writeAsBytesSync(png!.buffer.asUint8List());
        });
        stdout.writeln('$out  (그리기 준비 ${ms.toStringAsFixed(1)}ms)');
      }

      View3Camera orbit(Offset t, double dist, double azDeg, double tiltDeg) =>
          View3Camera.orbit(
            target: t,
            targetZ: scene.groundAt(t.dx, t.dy),
            distance: dist,
            azimuth: azDeg * math.pi / 180,
            tilt: tiltDeg * math.pi / 180,
          );
      // 원룸촌을 북서쪽에서(지도 기본 시점과 같은 방향).
      await shoot('orbit_oneroom', orbit(const Offset(280, 150), 420, -45, 38));
      // 낮게 기울여 청람동산·기숙사 언덕 쪽을.
      await shoot('orbit_hills', orbit(const Offset(480, -250), 520, 30, 20));
      // 원룸촌을 남쪽에서 낮게 — 뒤쪽 언덕이 보이는지.
      await shoot('orbit_oneroom_low', orbit(const Offset(70, -20), 380, 0, 16));
      // 멀리서 전체.
      await shoot('orbit_far', orbit(const Offset(300, -50), 1500, 0, 55));
    }
    tester.takeException();
  });
}
