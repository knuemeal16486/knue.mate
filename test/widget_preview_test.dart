import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart' show widgetBgStyle, widgetTheme, widgetTransparency;
import 'package:knue_mate/widget_preview.dart';

/// 설정 화면 위젯 미리보기. 색은 iOS WidgetPalette·Android WidgetColors와 같아야 한다.
void main() {
  const accent = Color(0xFF2563EB);

  group('widgetPreviewPalette — 위젯과 같은 색', () {
    test('라이트, 불투명', () {
      final p = widgetPreviewPalette(dark: false, transparency: 0, accent: accent);
      expect(p.background, const Color(0xFFFFFFFF));
      expect(p.title, Colors.black);
      expect(p.muted, const Color(0xFF8C8C8C));
      expect(p.highlight, const Color(0xFFE8710A));
    });
    test('다크, 불투명', () {
      final p = widgetPreviewPalette(dark: true, transparency: 0, accent: accent);
      expect(p.background, const Color(0xFF1F1F1F));
      expect(p.title, Colors.white);
      expect(p.highlight, const Color(0xFFFCAD70));
    });
    test('바탕 알파 = 1 - 투명도', () {
      final p = widgetPreviewPalette(dark: false, transparency: 0.3, accent: accent);
      expect(p.background.a, closeTo(0.7, 0.01));
    });
    test('0.7부터 배경화면 위 글씨 — 흐린 글씨·주황을 진하게', () {
      final below = widgetPreviewPalette(dark: false, transparency: 0.69, accent: accent);
      final at = widgetPreviewPalette(dark: false, transparency: 0.7, accent: accent);
      expect(below.muted, const Color(0xFF8C8C8C));
      expect(at.muted, const Color(0xFF383838));
      expect(below.highlight, const Color(0xFFE8710A));
      expect(at.highlight, const Color(0xFFB84D00));
      final darkAt = widgetPreviewPalette(dark: true, transparency: 0.7, accent: accent);
      expect(darkAt.muted.a, closeTo(0.8, 0.01));
    });
  });

  testWidgets('투명도·테마를 바꾸면 미리보기가 바로 바뀐다', (tester) async {
    widgetTheme.value = ThemeMode.light;
    widgetTransparency.value = 0;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: WidgetAppearancePreview())),
    ));
    Color cardBg() => ((tester
                .widget<Container>(find.byKey(const Key('widget-preview-card')).first)
                .decoration) as BoxDecoration)
            .color!;
    expect(cardBg(), const Color(0xFFFFFFFF));

    widgetTransparency.value = 0.5; // 슬라이더를 끄는 중
    await tester.pump();
    expect(cardBg().a, closeTo(0.5, 0.01));

    widgetTheme.value = ThemeMode.dark;
    await tester.pump();
    expect(cardBg().r, closeTo(0x1F / 255, 0.01));
    expect(find.text('점심'), findsOneWidget);
    expect(find.text('버스'), findsOneWidget);
  });

  // iOS 위젯 바탕(2026-11-25) — 값은 iOS WidgetPalette.background와 같다(Linux swiftc로 같은 RGB 확인).
  group('widgetBgColor — iOS 위젯 바탕(모두 불투명)', () {
    const light = Color(0xFF1D4ED8), dark = Color(0xFF60A5FA);
    int rgb(Color c) => c.toARGB32() & 0xFFFFFF;
    test('기본·테마색·회색 × 라이트·다크', () {
      expect(rgb(widgetBgColor(0, dark: false, accent: light)), 0xFFFFFF);
      expect(rgb(widgetBgColor(0, dark: true, accent: dark)), 0x1F1F1F);
      expect(rgb(widgetBgColor(1, dark: false, accent: light)), 0xE8EDFB); // 232,237,251
      expect(rgb(widgetBgColor(1, dark: true, accent: dark)), 0x2B3746); // 43,55,70
      expect(rgb(widgetBgColor(2, dark: false, accent: light)), 0xF2F2F7);
      expect(rgb(widgetBgColor(2, dark: true, accent: dark)), 0x2C2C2E);
      for (var s = 0; s < 3; s++) {
        expect(widgetBgColor(s, dark: false, accent: light).a, 1.0);
      }
    });
    test('iOS 팔레트는 투명도를 쓰지 않는다', () {
      final p = widgetPreviewPalette(
          dark: false, transparency: 0.8, accent: accent, bgStyle: 2, ios: true);
      expect(p.background, const Color(0xFFF2F2F7));
      expect(p.muted, const Color(0xFF8C8C8C)); // 배경화면 위 글씨로 보지 않는다
    });
  });

  testWidgets('iOS 미리보기는 바탕 스타일을 따른다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      widgetTheme.value = ThemeMode.light;
      widgetTransparency.value = 0.5;
      widgetBgStyle.value = 2;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: WidgetAppearancePreview())),
      ));
      final bg = ((tester
                  .widget<Container>(find.byKey(const Key('widget-preview-card')).first)
                  .decoration) as BoxDecoration)
              .color!;
      expect(bg, const Color(0xFFF2F2F7));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      widgetBgStyle.value = 0;
      widgetTransparency.value = 0;
    }
  });
}
