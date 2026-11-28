import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/features/bus/bus_last_update_bar.dart';
import 'package:knue_mate/features/home/home_hero_tile.dart';
import 'package:knue_mate/features/root/exit_promo_sponsor_box.dart';
import 'package:knue_mate/ui_utils.dart';

void main() {
  group('BusLastUpdateBar', () {
    testWidgets('갱신 직후 방금 갱신 텍스트와 운행 대수를 표시한다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusLastUpdateBar(
              lastUpdateTime: DateTime.now(),
              isRefreshing: false,
              totalBuses: 5,
              isDark: false,
            ),
          ),
        ),
      );
      expect(find.text('방금 갱신 · 운행 중 5대'), findsOneWidget);
    });

    testWidgets('갱신 중 상태에서는 갱신 중 인디케이터를 표시한다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusLastUpdateBar(
              lastUpdateTime: DateTime.now(),
              isRefreshing: true,
              totalBuses: 3,
              isDark: true,
            ),
          ),
        ),
      );
      expect(find.text('갱신 중...'), findsOneWidget);
    });
  });

  group('HomeHeroTile', () {
    testWidgets('큰 글꼴 스케일(1.45x)에서도 오버플로 없이 렌더링되고 탭·Semantics가 동작한다', (
      tester,
    ) async {
      var tapped = false;
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: Scaffold(
                body: SizedBox(
                  width: 170,
                  height: 152.0 * 1.45,
                  child: HomeHeroTile(
                    icon: Icons.restaurant_menu_rounded,
                    title: '오늘의 식단',
                    chip: '점심 · 기숙사',
                    footer: '식단 상세',
                    onTap: () => tapped = true,
                    body: const Text(
                      '김치찌개\n계란말이\n백미밥',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(RegExp('오늘의 식단, 점심 · 기숙사, 식단 상세')),
          findsOneWidget,
        );

        await tester.tap(find.byType(HomeHeroTile));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      } finally {
        handle.dispose();
      }
    });
  });

  group('Accessibility & ExitPromoSponsorBox', () {
    testWidgets('AnimatedScaleButton과 KnueSectionHeader에 Semantics가 노출된다', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  KnueSectionHeader(
                    title: '학사일정',
                    actionText: '전체보기',
                    onAction: () {},
                  ),
                  AnimatedScaleButton(
                    semanticLabel: '테스트 버튼',
                    onTap: () {},
                    child: const Text('누르기'),
                  ),
                  ExitPromoSponsorBox(
                    phone: '010-0000-0000',
                    priceText: '주당 1만원',
                    accent: Colors.blue,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('학사일정 전체보기'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('테스트 버튼')), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });
  });
}
