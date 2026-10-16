// iPhone에서 홈을 맨 위에서 더 당기면 헤더가 밀려 내려간다. 그 위 빈틈을 헤더와
// 같은 그라디언트로 채우는 계산(stretchedHeaderAlignment).
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/ui_utils.dart';

void main() {
  test('당기지 않았고 상자가 헤더와 같으면 그대로', () {
    final a = stretchedHeaderAlignment(Alignment.topLeft,
        overscroll: 0, headerHeight: 200, boxHeight: 200);
    expect(a, Alignment.topLeft);
    final b = stretchedHeaderAlignment(Alignment.bottomRight,
        overscroll: 0, headerHeight: 200, boxHeight: 200);
    expect(b, Alignment.bottomRight);
  });

  test('80만큼 당기면 헤더 맨 위가 상자 안에서 80 아래로 옮겨진다', () {
    // 상자 높이 = 80 + 100. 헤더 맨 위(화면 y=80) → 상자 정렬값 2*80/180-1.
    final a = stretchedHeaderAlignment(Alignment.topLeft,
        overscroll: 80, headerHeight: 200, boxHeight: 180);
    expect(a.x, -1);
    expect(a.y, closeTo(2 * 80 / 180 - 1, 1e-9));
    // 헤더 맨 아래(화면 y=280)는 상자 밖(1보다 크다) — 같은 기울기로 이어진다.
    final b = stretchedHeaderAlignment(Alignment.bottomRight,
        overscroll: 80, headerHeight: 200, boxHeight: 180);
    expect(b.y, closeTo(2 * 280 / 180 - 1, 1e-9));
  });

  test('선형 그라디언트가 아니면 그대로, 색·구간은 유지', () {
    const radial = RadialGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]);
    expect(stretchedHeaderGradient(radial, overscroll: 50, headerHeight: 200, boxHeight: 150), same(radial));
    const linear = LinearGradient(
      colors: [Color(0xFF111111), Color(0xFF222222), Color(0xFF333333)],
      stops: [0, 0.52, 1],
    );
    final g = stretchedHeaderGradient(linear, overscroll: 50, headerHeight: 200, boxHeight: 150) as LinearGradient;
    expect(g.colors, linear.colors);
    expect(g.stops, linear.stops);
  });

  test('상자 높이가 0이면 그대로(나눗셈 안 함)', () {
    expect(
      stretchedHeaderAlignment(Alignment.center, overscroll: 0, headerHeight: 0, boxHeight: 0),
      Alignment.center,
    );
  });
}
