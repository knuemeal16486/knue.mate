// 펄 테마 검증.
//
// 핵심 관심사 두 가지:
//  1) 팔레트 20색 어디에 적용해도 깨지지 않는가 (검정·회색 포함)
//  2) 흰 글씨를 얹는 헤더에서 대비가 무너지지 않는가
//
// [kPearlTheme]를 false로 바꾸면 헤더는 예전 2단 그라데이션, 스와치는 단색으로
// 즉시 되돌아간다. 아래 "되돌리기" 그룹이 그 계약을 지킨다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/ui_utils.dart';

void main() {
  group('펄 색 생성', () {
    test('하이라이트는 씨드보다 밝고, 그림자는 어둡다', () {
      for (final seed in kColorPalette) {
        final hi = KnuePearl.highlight(seed);
        final lo = KnuePearl.shade(seed);
        final l = HSLColor.fromColor(seed).lightness;
        expect(HSLColor.fromColor(hi).lightness, greaterThanOrEqualTo(l),
            reason: '$seed 하이라이트가 더 어둡다');
        expect(HSLColor.fromColor(lo).lightness, lessThanOrEqualTo(l),
            reason: '$seed 그림자가 더 밝다');
      }
    });

    test('검정처럼 채도 0인 색도 안전하게 처리된다', () {
      // 팔레트에 순수 검정(0xFF000000)이 있다. 밝기를 내릴 여지가 없으므로
      // 클램프가 동작하지 않으면 값이 범위를 벗어난다.
      const black = Color(0xFF000000);
      final hi = KnuePearl.highlight(black);
      final lo = KnuePearl.shade(black);
      for (final c in [hi, lo]) {
        final hsl = HSLColor.fromColor(c);
        expect(hsl.lightness, inInclusiveRange(0.0, 1.0));
        expect(hsl.saturation, inInclusiveRange(0.0, 1.0));
      }
      // 검정은 그림자를 더 못 만들므로 검정 그대로여야 한다.
      expect(lo, black);
    });

    test('색상 회전이 0~360 범위를 벗어나지 않는다', () {
      // 빨강 계열(hue가 0 근처)은 -12도를 돌리면 음수가 될 수 있다.
      for (final seed in kColorPalette) {
        for (final c in [KnuePearl.highlight(seed), KnuePearl.shade(seed)]) {
          final h = HSLColor.fromColor(c).hue;
          expect(h, inInclusiveRange(0.0, 360.0), reason: '$seed → hue $h');
        }
      }
    });
  });

  group('헤더 가독성', () {
    // 흰 글씨 대비 계산 (WCAG 상대 명도비).
    double whiteContrast(Color c) => 1.05 / (c.computeLuminance() + 0.05);

    // 펄 적용 전 공식: 위쪽은 흰색 8% 혼합.
    Color flatTop(Color seed) => Color.lerp(seed, Colors.white, 0.08)!;

    test('펄이 기존보다 흰 글씨 대비를 떨어뜨리지 않는다', () {
      // ⚠️ 절대 기준(3:1)은 쓰지 않는다. 기존 팔레트가 이미 노랑에서 1.36:1로
      // 그 선을 한참 밑돌기 때문이다(펄과 무관한 별도 문제). 여기서 지킬 계약은
      // "광택을 넣었다고 지금보다 나빠지지는 않는다"이다.
      for (final seed in kColorPalette) {
        final baseline = whiteContrast(flatTop(seed));
        for (final isDark in [false, true]) {
          for (final c in KnuePearl.headerGradient(seed, isDark).colors) {
            expect(whiteContrast(c), greaterThanOrEqualTo(baseline - 0.02),
                reason: '$seed (dark=$isDark) 정점 $c → '
                    '${whiteContrast(c).toStringAsFixed(2)}:1 이 '
                    '기존 ${baseline.toStringAsFixed(2)}:1 보다 나쁘다');
          }
        }
      }
    });

    test('밝은 색에서도 하이라이트가 기존 상한을 넘지 않는다', () {
      // 밝은 빨강·노랑처럼 여유가 없는 색이 회귀의 단골이라 따로 못 박는다.
      for (final seed in [const Color(0xFFEF5350), const Color(0xFFFDD835)]) {
        final hi = KnuePearl.highlight(seed);
        expect(hi.computeLuminance(),
            lessThanOrEqualTo(flatTop(seed).computeLuminance() + 1e-6),
            reason: '$seed 하이라이트가 기존보다 밝다');
      }
    });

    test('다크 모드에서는 광택이 라이트 모드보다 약하다', () {
      // 어두운 화면에서 밝은 띠가 튀지 않도록 강도를 낮춰뒀다.
      for (final seed in kColorPalette) {
        final light = KnuePearl.headerGradient(seed, false).colors;
        final dark = KnuePearl.headerGradient(seed, true).colors;
        final lightSpan = HSLColor.fromColor(light.first).lightness -
            HSLColor.fromColor(light.last).lightness;
        final darkSpan = HSLColor.fromColor(dark.first).lightness -
            HSLColor.fromColor(dark.last).lightness;
        expect(darkSpan, lessThanOrEqualTo(lightSpan + 1e-9),
            reason: '$seed 다크 광택이 더 세다');
      }
    });
  });

  group('되돌리기 계약 (kPearlTheme)', () {
    test('켜져 있으면 헤더가 3단, 스와치가 그라데이션이다', () {
      // kPearlTheme를 false로 바꾸면 이 테스트가 실패한다 — 의도된 신호다.
      // 되돌릴 때는 이 그룹의 기대값을 뒤집으면 된다.
      expect(kPearlTheme, isTrue,
          reason: 'kPearlTheme를 껐다면 이 그룹의 기대값도 함께 뒤집어야 한다');

      final g = KnuePearl.headerGradient(kColorPalette.first, false);
      expect(g.colors.length, 3);
      expect(g.begin, Alignment.topLeft);

      final s = KnuePearl.swatchGradient(kColorPalette.first);
      expect(s.colors.length, 3);
      expect(s.colors.first, isNot(s.colors.last));
    });

    test('스와치 반사광은 완전 투명으로 끝난다', () {
      // 가장자리까지 흰빛이 남으면 색이 바래 보인다.
      final sheen = KnuePearl.sheen();
      expect(sheen.colors.last.a, 0.0);
    });
  });
}
