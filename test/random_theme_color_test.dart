import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  group('pickRandomThemeColor', () {
    test('지금 쓰는 색은 절대 다시 뽑히지 않는다', () {
      // 광고를 끝까지 봤는데 색이 그대로면 보상을 못 받은 것처럼 보인다.
      for (final current in kColorPalette) {
        for (var seed = 0; seed < 20; seed++) {
          final picked = pickRandomThemeColor(current, random: Random(seed));
          expect(
            picked.toARGB32(),
            isNot(current.toARGB32()),
            reason: '현재색=$current seed=$seed 인데 같은 색이 뽑힘',
          );
        }
      }
    });

    test('뽑힌 색은 항상 팔레트 안에 있다', () {
      final palette = kColorPalette.map((c) => c.toARGB32()).toSet();
      for (var seed = 0; seed < 30; seed++) {
        final picked =
            pickRandomThemeColor(kColorPalette.first, random: Random(seed));
        expect(palette, contains(picked.toARGB32()));
      }
    });

    test('같은 시드는 같은 결과 — 결정적이다', () {
      final a = pickRandomThemeColor(kColorPalette.first, random: Random(7));
      final b = pickRandomThemeColor(kColorPalette.first, random: Random(7));
      expect(a.toARGB32(), b.toARGB32());
    });

    test('충분히 반복하면 여러 색이 골고루 나온다', () {
      final seen = <int>{};
      for (var seed = 0; seed < 60; seed++) {
        seen.add(
          pickRandomThemeColor(kColorPalette.first, random: Random(seed))
              .toARGB32(),
        );
      }
      // 한두 색에 몰리지 않는지만 확인(팔레트 20색 중 최소 5색).
      expect(seen.length, greaterThanOrEqualTo(5));
    });

    test('팔레트에 없는 색을 쓰고 있어도 정상 동작한다', () {
      // 예전 버전에서 저장된 색이 팔레트에서 빠졌을 수 있다.
      const orphan = Color(0xFF123456);
      final picked = pickRandomThemeColor(orphan, random: Random(1));
      expect(
        kColorPalette.map((c) => c.toARGB32()),
        contains(picked.toARGB32()),
      );
    });
  });
}
