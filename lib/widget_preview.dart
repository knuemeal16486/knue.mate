/// 설정 화면의 홈 위젯 미리보기 — 테마·투명도를 바꾸면 홈 화면에 나가지 않고 바로 본다.
///
/// 색은 위젯과 같은 규칙이다: iOS `WidgetPalette`(ios/MealWidget/WidgetShared.swift)·
/// Android `WidgetColors`(WidgetTheme.kt). 여기를 바꾸면 거기도 — 기준값
/// [kWidgetOnWallpaperTransparency]는 test/native_id_consistency_test.dart가 맞춰 본다.
/// 글자는 예시로 고정이다(모양만 보는 곳).
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'constants.dart' show themeColor, widgetBgStyle, widgetSource, widgetTheme, widgetTransparency;
import 'home_widgets.dart' show widgetAccentHex;

/// 투명도가 이 값 이상이면 배경화면 위 글씨로 보고 흐린 글씨·주황을 진하게 쓴다.
/// iOS `kWidgetOnWallpaperTransparency`·Android `ON_WALLPAPER_TRANSPARENCY`와 같다.
const kWidgetOnWallpaperTransparency = 0.7;

/// 위젯 색. iOS `WidgetPalette`와 같은 값.
class WidgetPreviewPalette {
  final Color background;
  final Color title;
  final Color body;
  final Color muted;
  final Color accent;
  final Color highlight;

  const WidgetPreviewPalette({
    required this.background,
    required this.title,
    required this.body,
    required this.muted,
    required this.accent,
    required this.highlight,
  });
}

/// "#RRGGBB" → Color.
Color _hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));

/// iOS 위젯 바탕 스타일 이름(설정 화면 순서 = 값).
const kWidgetBgStyleLabels = ['기본', '테마색', '회색'];

/// 테마색 바탕에서 앱 테마 색을 섞는 비율(라이트·다크). iOS `kWidgetTintLight/Dark`와 같다.
const kWidgetTintLight = 0.10;
const kWidgetTintDark = 0.18;

/// iOS 위젯 바탕색 — 모두 불투명. iOS `WidgetPalette.background`와 같은 규칙.
/// 0 기본(흰색 / #1F1F1F), 1 테마색(앱 테마 색을 옅게 섞음), 2 회색(#F2F2F7 / #2C2C2E — iOS 그룹 바탕).
/// [accent]는 위젯이 쓰는 강조색(`widgetAccentHex`를 거친 라이트·다크 값 중 그 모드 것).
Color widgetBgColor(int style, {required bool dark, required Color accent}) {
  final base = dark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF);
  switch (style) {
    case 1:
      return Color.lerp(base, accent, dark ? kWidgetTintDark : kWidgetTintLight)!;
    case 2:
      return dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    default:
      return base;
  }
}

/// 순수 함수 — 테스트 대상. [transparency]는 0.0(불투명)~1.0, [accent]는 앱 테마 색.
/// [ios]면 투명도를 쓰지 않고(iOS는 배경화면이 비치지 않는다) [bgStyle] 바탕색을 쓴다.
WidgetPreviewPalette widgetPreviewPalette({
  required bool dark,
  required double transparency,
  required Color accent,
  int bgStyle = 0,
  bool ios = false,
}) {
  final t = ios ? 0.0 : transparency.clamp(0.0, 1.0);
  final onWallpaper = t >= kWidgetOnWallpaperTransparency;
  final a = widgetAccentHex(accent);
  final accentColor = _hexColor(dark ? a.dark : a.light);
  final base = dark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF);
  return WidgetPreviewPalette(
    background: ios
        ? widgetBgColor(bgStyle, dark: dark, accent: accentColor)
        : base.withValues(alpha: 1 - t),
    title: dark ? Colors.white : Colors.black,
    body: dark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF333333),
    muted: onWallpaper
        ? (dark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF383838))
        : (dark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF8C8C8C)),
    accent: accentColor,
    highlight: dark
        ? const Color(0xFFFCAD70)
        : (onWallpaper ? const Color(0xFFB84D00) : const Color(0xFFE8710A)),
  );
}

/// 위젯 설정 카드 맨 위의 미리보기. 배경화면 같은 판 위에 식단·버스 small 위젯 두 개.
/// 테마·투명도·앱 테마 색·식당이 바뀌면(슬라이더를 끄는 동안에도) 바로 다시 그린다.
class WidgetAppearancePreview extends StatelessWidget {
  const WidgetAppearancePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [widgetTheme, widgetTransparency, widgetBgStyle, themeColor, widgetSource]),
      builder: (context, _) {
        final dark = switch (widgetTheme.value) {
          ThemeMode.light => false,
          ThemeMode.dark => true,
          ThemeMode.system =>
            MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        };
        final p = widgetPreviewPalette(
          dark: dark,
          transparency: widgetTransparency.value,
          accent: themeColor.value,
          bgStyle: widgetBgStyle.value,
          ios: defaultTargetPlatform == TargetPlatform.iOS,
        );
        return Container(
          key: const Key('widget-preview'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // 배경화면처럼 — 투명도를 올리면 이 그림이 위젯 뒤로 비친다.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6A85E8), Color(0xFFB07CC6), Color(0xFFF2B38A)],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _small(_meal(p), p)),
                  const SizedBox(width: 12),
                  Expanded(child: _small(_bus(p), p)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '미리보기 · 예시 글자',
                style: TextStyle(fontSize: 11, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 170×170pt 위젯을 칸 폭에 맞춰 줄인다(글자·여백 비율 그대로).
  Widget _small(Widget content, WidgetPreviewPalette p) => AspectRatio(
        aspectRatio: 1,
        child: FittedBox(
          child: Container(
            key: const Key('widget-preview-card'),
            width: 170,
            height: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: BorderRadius.circular(22),
            ),
            child: content,
          ),
        ),
      );

  Widget _header(String title, String sub, WidgetPreviewPalette p,
          {bool underline = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: p.title)),
          if (underline)
            Container(
              width: 48,
              height: 3,
              margin: const EdgeInsets.only(top: 5, bottom: 3),
              decoration: BoxDecoration(
                  color: p.accent, borderRadius: BorderRadius.circular(1.5)),
            ),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.muted)),
        ],
      );

  Widget _meal(WidgetPreviewPalette p) {
    TextSpan line(List<String> items) => TextSpan(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) TextSpan(text: ' · ', style: TextStyle(color: p.muted)),
            TextSpan(text: items[i], style: TextStyle(color: p.title)),
          ],
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('점심', '${widgetSource.value.label} · 오늘', p, underline: true),
        const SizedBox(height: 8),
        for (final l in const [
          ['잡곡밥', '김치찌개'],
          ['계란말이', '시금치나물'],
          ['깍두기', '요구르트'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(line(l),
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }

  Widget _bus(WidgetPreviewPalette p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('버스', '학교 출발 · 평일', p),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    // 514 노선 색(kNoticeBoardColors 초록) — 다크면 밝은 쪽, 위젯과 같다.
                    color: (p.title == Colors.white
                            ? const Color(0xFF81C995)
                            : const Color(0xFF188038))
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('514',
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.title)),
                    Text.rich(maxLines: 1, overflow: TextOverflow.clip, TextSpan(children: [
                      TextSpan(
                          text: '12:12',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.highlight)),
                      TextSpan(
                          text: '  7분 뒤',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.highlight)),
                    ])),
                  ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text('다음 518 12:15',
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: p.muted)),
          Text('다음 913 평동행 12:33',
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: p.muted)),
        ],
      );
}
