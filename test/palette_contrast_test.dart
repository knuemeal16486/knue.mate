// 팔레트 가독성 + 무지개 모드 검증.
//
// 테마 색상은 헤더·앱바 배경으로 깔리고 그 위에는 흰 글씨만 올라간다.
// 따라서 "흰색 대비"가 이 팔레트의 합격 기준이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/ui_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

double whiteContrast(Color c) => 1.05 / (c.computeLuminance() + 0.05);

void main() {
  group('테마 팔레트', () {
    // 이 팔레트는 **의도적으로 대비보다 색감을 택했다.** 그래서 "모든 색이
    // N:1 이상" 같은 게이트는 두지 않는다. 대신 그 결정이 나중에 조용히
    // 뒤집히지 않도록, 선명함이 유지되는지를 반대 방향으로 검사한다.
    test('선명한 팔레트가 그대로 유지된다', () {
      // 한 번 대비를 이유로 전 색을 어둡게 낮춘 적이 있는데(노랑이 머스타드가
      // 되는 등) 팔레트가 탁해져 되돌렸다. 같은 일이 조용히 반복되지 않도록
      // 의도한 값을 고정한다. 색을 바꾸려면 여기도 함께 고쳐야 한다.
      //
      // ("채도/밝기가 N 이상" 같은 대략적 기준은 쓰지 않는다 — 틸(#00897B)은
      //  채도 100%의 선명한 색인데도 HSL 밝기가 27%라 잘못 걸린다.)
      expect(kColorPalette, const [
        Color(0xFF2563EB), Color(0xFFEF5350), Color(0xFFEC407A),
        Color(0xFFC77AD3), Color(0xFFAB47BC), Color(0xFF7E57C2),
        Color(0xFF5C6BC0), Color(0xFF039BE5), Color(0xFF00ACC1),
        Color(0xFF00897B), Color(0xFF43A047), Color(0xFF7CB342),
        Color(0xFFC0CA33), Color(0xFFFDD835), Color(0xFFFFB300),
        Color(0xFFFB8C00), Color(0xFFF4511E), Color(0xFF6D4C41),
        Color(0xFF757575), Color(0xFF000000),
      ]);
    });

    test('무지개 팔레트는 테마 팔레트에서 뽑아 쓴다', () {
      // 무지개만 따로 놀면 그날 색이 앱 색감에서 벗어난다.
      for (final c in kRainbowPalette) {
        expect(kColorPalette.contains(c), isTrue, reason: '$c 는 팔레트 밖 색');
      }
    });

    test('그림자는 모든 색에서 같고, 아주 옅다', () {
      // 밝은 색에서만 진해지는 방식은 글자에 검은 테두리가 둘린 것처럼 보였다.
      final s = KnueTokens.headerTextShadow;
      expect(s.first.color.a, lessThanOrEqualTo(0.25),
          reason: '그림자가 과하다 — 글자에 테두리가 생긴다');
      expect(s.first.color.a, greaterThan(0.0));
    });

    test('펄이 흰 글씨 대비를 기존 단색보다 떨어뜨리지 않는다', () {
      // 팔레트가 밝아진 만큼, 펄 광택이 대비를 더 깎지는 않는지가 중요해졌다.
      for (final seed in [...kColorPalette, ...kRainbowPalette]) {
        final baseline = whiteContrast(Color.lerp(seed, Colors.white, 0.08)!);
        for (final isDark in [false, true]) {
          for (final c in KnuePearl.headerGradient(seed, isDark).colors) {
            expect(whiteContrast(c), greaterThanOrEqualTo(baseline - 0.02),
                reason: '$seed(dark=$isDark) 정점 $c → '
                    '${whiteContrast(c).toStringAsFixed(2)}:1 < '
                    '${baseline.toStringAsFixed(2)}:1');
          }
        }
      }
    });

    test('팔레트에 중복된 색이 없다', () {
      expect(kColorPalette.toSet().length, kColorPalette.length);
      expect(kRainbowPalette.toSet().length, kRainbowPalette.length);
    });
  });

  group('무지개 모드 — 오늘의 색', () {
    test('같은 날은 항상 같은 색이다', () {
      // 화면을 볼 때마다 색이 바뀌면 어지럽다. 하루 동안은 고정이어야 한다.
      final a = colorOfDay(DateTime(2026, 8, 19, 0, 1));
      final b = colorOfDay(DateTime(2026, 8, 19, 23, 59));
      expect(a, b);
    });

    test('연속한 날은 서로 다른 색이다', () {
      var d = DateTime(2026, 1, 1);
      for (var i = 0; i < 400; i++) {
        final next = d.add(const Duration(days: 1));
        expect(colorOfDay(d), isNot(colorOfDay(next)),
            reason: '$d 와 $next 가 같은 색');
        d = next;
      }
    });

    test('12일이면 무지개 12색을 빠짐없이 한 번씩 쓴다', () {
      final seen = <Color>{};
      var d = DateTime(2026, 3, 1);
      for (var i = 0; i < kRainbowPalette.length; i++) {
        seen.add(colorOfDay(d));
        d = d.add(const Duration(days: 1));
      }
      expect(seen.length, kRainbowPalette.length);
    });

    test('항상 무지개 팔레트 안의 색만 나온다', () {
      var d = DateTime(2025, 1, 1);
      for (var i = 0; i < 800; i++) {
        expect(kRainbowPalette.contains(colorOfDay(d)), isTrue);
        d = d.add(const Duration(days: 1));
      }
    });

    test('서머타임/시간대 영향 없이 하루 단위로만 바뀐다', () {
      // 로컬 시간의 시/분이 달라도 같은 날짜면 같은 색.
      for (final h in [0, 6, 12, 18, 23]) {
        expect(colorOfDay(DateTime(2026, 6, 15, h)),
            colorOfDay(DateTime(2026, 6, 15)));
      }
    });
  });

  group('무지개 모드 — 토글', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rainbowModeNotifier.value = false;
      themeColor.value = kColorPalette.first;
    });

    test('켜면 오늘의 색이 즉시 적용된다', () async {
      await PreferencesService.setRainbowMode(true);
      expect(rainbowModeNotifier.value, isTrue);
      expect(themeColor.value, colorOfDay(DateTime.now()));
    });

    test('끄면 사용자가 고른 색으로 정확히 되돌아온다', () async {
      // 사용자가 퍼플을 고른 상태 → 무지개 켰다 끄면 다시 퍼플이어야 한다.
      const picked = Color(0xFF6A1B9A);
      themeColor.value = picked;
      await PreferencesService.saveThemeColor(picked);

      await PreferencesService.setRainbowMode(true);
      expect(themeColor.value, isNot(picked),
          reason: '무지개가 켜졌는데 색이 안 바뀜');

      await PreferencesService.setRainbowMode(false);
      expect(themeColor.value, picked, reason: '고른 색으로 복원되지 않음');
    });

    test('무지개 모드가 저장된 선택 색을 덮어쓰지 않는다', () async {
      const picked = Color(0xFF00695C);
      await PreferencesService.saveThemeColor(picked);
      await PreferencesService.setRainbowMode(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PreferencesService.keyThemeColor), picked.value,
          reason: '저장된 사용자 색이 오늘의 색으로 덮여썼다');
    });

    test('꺼져 있으면 날짜 갱신이 색을 건드리지 않는다', () {
      const picked = Color(0xFFC62828);
      themeColor.value = picked;
      rainbowModeNotifier.value = false;
      PreferencesService.refreshRainbowColorIfNeeded();
      expect(themeColor.value, picked);
    });

    test('켜져 있으면 날짜 갱신이 오늘의 색을 맞춘다', () {
      rainbowModeNotifier.value = true;
      themeColor.value = const Color(0xFF123456); // 어제 색이라고 가정
      PreferencesService.refreshRainbowColorIfNeeded();
      expect(themeColor.value, colorOfDay(DateTime.now()));
    });
  });
}
