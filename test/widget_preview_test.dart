import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart' show widgetTheme, widgetTransparency;
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
}
