// 비/눈/바람 파티클 오버레이가 각 날씨 상태에서 예외 없이 그려지는지 확인한다.
// 날씨 시뮬레이터 토글을 없앤 뒤로는 실제 기기에서 비·눈 상태를 손으로
// 만들어 볼 방법이 없어서, 이 테스트가 유일한 회귀 방지선이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/ui_utils.dart';

/// CustomPaint는 Material 위젯 내부에서도 흔히 쓰여서 find.byType(CustomPaint)를
/// 화면 전체에 걸면 이 오버레이가 그린 것인지 알 수 없다. 오버레이 자손으로
/// 범위를 좁힌다.
Finder _particlePaint() => find.descendant(
      of: find.byType(WeatherParticlesOverlay),
      matching: find.byType(CustomPaint),
    );

Future<void> pumpOverlay(WidgetTester tester, KnueWeatherInfo? weather) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 150,
          child: WeatherParticlesOverlay(weather: weather),
        ),
      ),
    ),
  );
  // 진행률이 실제로 움직이는지까지 본다 — 한 프레임만 보면 정적 렌더만 검증된다.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('비 오는 날 예외 없이 그려진다', (tester) async {
    await pumpOverlay(
      tester,
      const KnueWeatherInfo(temp: 16, weatherCode: 61, windSpeed: 8),
    );
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsOneWidget);
  });

  testWidgets('눈 오는 날 예외 없이 그려진다', (tester) async {
    await pumpOverlay(
      tester,
      const KnueWeatherInfo(temp: -3, weatherCode: 71, windSpeed: 10),
    );
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsOneWidget);
  });

  testWidgets('바람·한파일 때 예외 없이 그려진다', (tester) async {
    await pumpOverlay(
      tester,
      const KnueWeatherInfo(temp: 4, weatherCode: 2, windSpeed: 25),
    );
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsOneWidget);
  });

  testWidgets('맑은 날은 입자를 그리지 않는다(SizedBox.shrink)', (tester) async {
    await pumpOverlay(
      tester,
      const KnueWeatherInfo(temp: 21, weatherCode: 0, windSpeed: 5),
    );
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsNothing);
  });

  testWidgets('날씨 정보가 없어도(null) 안전하다', (tester) async {
    await pumpOverlay(tester, null);
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsNothing);
  });

  testWidgets('날씨가 비→맑음으로 바뀌면 입자가 사라진다', (tester) async {
    const rainy = KnueWeatherInfo(temp: 16, weatherCode: 61, windSpeed: 8);
    const sunny = KnueWeatherInfo(temp: 21, weatherCode: 0, windSpeed: 5);
    await pumpOverlay(tester, rainy);
    expect(_particlePaint(), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 150,
            child: WeatherParticlesOverlay(weather: sunny),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_particlePaint(), findsNothing);
  });
}
