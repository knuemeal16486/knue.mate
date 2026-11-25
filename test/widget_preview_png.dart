// 설정 화면의 위젯 미리보기를 그림으로 확인한다(2026-11-25).
//
//   flutter test test/widget_preview_png.dart   # → build/widget_preview.png(Android 투명도), build/widget_bg_ios.png(iOS 바탕),
//                                                 build/widget_settings_{light,dark,ios}.png
//
// 라이트·다크 × 투명도 0·0.5·0.8 여섯 칸을 한 장에. 한글 글꼴은 환경 변수
// KNUE_FONT_DIR(NotoSansKR_400Regular.ttf 등이 든 폴더)이나 Windows 글꼴에서 읽는다 —
// 없으면 글자가 네모로 나오지만 색·투명도는 확인할 수 있다. 이름이 _test로 끝나지
// 않아 `flutter test` 전체 실행에는 끼지 않는다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:knue_mate/constants.dart' show widgetBgStyle, widgetTheme, widgetTransparency;
import 'package:knue_mate/widget_preview.dart';
import 'package:knue_mate/widget_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final dir = Platform.environment['KNUE_FONT_DIR'];
  final files = <File>[
    if (dir != null)
      for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold'])
        File('$dir/NotoSansKR_$w.ttf'),
    File('C:/Windows/Fonts/NotoSansKR-VF.ttf'),
  ].where((f) => f.existsSync()).toList();
  if (files.isEmpty) return;
  final loader = FontLoader('NotoSansKR');
  for (final f in files) {
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
  }
  await loader.load();
}

/// 한 칸: 그 설정으로 그린 미리보기. 위젯 테스트에서 값 하나를 여러 번 바꿔 그릴 수
/// 없어서(전역 ValueNotifier) 칸마다 따로 찍어 이어 붙인다.
Future<ui.Image> _shot(WidgetTester tester, ThemeMode mode, double t, {int? style}) async {
  widgetTheme.value = mode;
  widgetTransparency.value = t;
  if (style != null) widgetBgStyle.value = style;
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'NotoSansKR'),
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${mode == ThemeMode.dark ? '다크' : '라이트'} · '
                  '${style != null ? 'iOS 바탕 ${kWidgetBgStyleLabels[style]}' : '투명도 ${(t * 100).round()}%'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const WidgetAppearancePreview(),
            ]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
}

void main() {
  testWidgets('위젯 미리보기 PNG', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    final shots = <ui.Image>[];
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final t in [0.0, 0.5, 0.8]) {
        shots.add(await _shot(tester, mode, t));
      }
    }
    // 2열 × 3행으로 이어 붙인다.
    final w = shots.first.width, h = shots.first.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < shots.length; i++) {
      canvas.drawImage(shots[i], Offset((i ~/ 3) * w.toDouble(), (i % 3) * h.toDouble()), Paint());
    }
    final sheet = await tester.runAsync(
        () => recorder.endRecording().toImage(w * 2, h * 3));
    final png = await tester.runAsync(() => sheet!.toByteData(format: ui.ImageByteFormat.png));
    Directory('build').createSync(recursive: true);
    File('build/widget_preview.png').writeAsBytesSync(png!.buffer.asUint8List());
    addTearDown(tester.view.reset);
  });

  // iOS 위젯 바탕 3가지 × 라이트·다크(투명도 대신, 2026-11-25).
  testWidgets('iOS 바탕 PNG', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final shots = <ui.Image>[];
    try {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (var st = 0; st < 3; st++) {
          shots.add(await _shot(tester, mode, 0, style: st));
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      widgetBgStyle.value = 0;
    }
    final w = shots.first.width, h = shots.first.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < shots.length; i++) {
      canvas.drawImage(shots[i], Offset((i ~/ 3) * w.toDouble(), (i % 3) * h.toDouble()), Paint());
    }
    final sheet = await tester.runAsync(() => recorder.endRecording().toImage(w * 2, h * 3));
    final png = await tester.runAsync(() => sheet!.toByteData(format: ui.ImageByteFormat.png));
    Directory('build').createSync(recursive: true);
    File('build/widget_bg_ios.png').writeAsBytesSync(png!.buffer.asUint8List());
    addTearDown(tester.view.reset);
  });

  // 설정 → 홈 위젯 화면 전체(라이트·다크).
  for (final dark in [false, true]) {
    testWidgets('홈 위젯 화면 PNG ${dark ? 'dark' : 'light'}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(390, 1180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      widgetTheme.value = ThemeMode.system;
      widgetTransparency.value = 0.3;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansKR', brightness: Brightness.light),
          darkTheme: ThemeData(fontFamily: 'NotoSansKR', brightness: Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const WidgetSettingsScreen(),
        ),
      ));
      await tester.pump();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
      final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      Directory('build').createSync(recursive: true);
      File('build/widget_settings_${dark ? 'dark' : 'light'}.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}
