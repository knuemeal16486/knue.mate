// 종료 팝업 문구가 좁은 화면에서 접히지 않는지 **실제로 재서** 확인한다.
//
// 문구를 짧게 고쳐놔도, 다음에 누가 한 단어를 더 붙이면 조용히 두 줄이 된다.
// 눈으로만 보는 확인은 그때 돌아오지 않는다.
//
// ⚠️ 테스트 환경의 글꼴은 **모든 글자를 같은 폭(1em)으로** 그린다. 실제
// 앱이 쓰는 Noto Sans KR에서 숫자·영문·공백은 그 절반 남짓이므로, 여기서
// 재는 폭은 언제나 실제보다 **넓게** 나온다. 그래서 이 테스트는 한쪽으로만
// 믿을 수 있다 — **통과하면 실제로도 안 접힌다.** 반대로 여기서 넘친다고
// 실제로 접힌다는 뜻은 아니다(숫자가 많은 줄이 특히 그렇다).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/root_screen.dart';

void main() {
  /// [text]가 줄바꿈 없이 한 줄에 들어갔는지.
  ///
  /// 줄 수를 직접 세는 API는 Flutter 버전마다 있다 없다 해서, 줄을 안 접고
  /// 그리는 데 필요한 폭(내재 폭)과 실제로 받은 폭을 견준다 — 필요한 폭이
  /// 더 크면 그만큼이 다음 줄로 넘어갔다는 뜻이다.
  bool fitsOneLine(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    final needed = paragraph.getMaxIntrinsicWidth(double.infinity);
    return needed <= paragraph.size.width + 0.5; // 반올림 오차 여유
  }

  /// 팝업 안에서 이 칸이 실제로 받는 폭.
  ///
  /// 팝업 = 화면폭 - insetPadding(24×2), 본문 Padding(20×2)을 빼면 남는 값이다.
  /// 이 셈이 팝업 쪽([RootNavigationScreenState] `_showExitPromo`)과 어긋나면
  /// 테스트가 헐거워지므로 한 곳에 적어 둔다.
  double boxWidth(double screenWidth) => screenWidth - 24 * 2 - 20 * 2;

  const headline = "행사 홍보하고 싶으신가요?";
  const price = "9/30까지 무료 · 이후 주당 1만원";
  const contact = "문의 · 010-8032-8088";

  Future<void> pumpBox(
    WidgetTester tester,
    double screenWidth, {
    String priceText = price,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: boxWidth(screenWidth),
              child: ExitPromoSponsorBox(
                phone: "010-8032-8088",
                priceText: priceText,
                accent: Colors.blue,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('요즘 폰 폭(412dp)에서는 세 줄 모두 안 접힌다', () {
    // 고정폭 글꼴로 재고도 들어간다는 뜻이라, 실제 글꼴에서는 여유가 더 있다.
    const wide = 412.0;

    testWidgets('모집 문구', (tester) async {
      await pumpBox(tester, wide);
      expect(fitsOneLine(tester, headline), isTrue);
    });

    testWidgets('단가 문구', (tester) async {
      await pumpBox(tester, wide);
      expect(fitsOneLine(tester, price), isTrue);
    });

    testWidgets('연락처 — 접히면 눌러야 할 번호가 두 동강 난다', (tester) async {
      await pumpBox(tester, wide);
      expect(fitsOneLine(tester, contact), isTrue);
    });

    testWidgets('프로모션이 끝난 뒤의 짧은 단가도', (tester) async {
      await pumpBox(tester, wide, priceText: "주당 1만원");
      expect(fitsOneLine(tester, "주당 1만원"), isTrue);
    });
  });

  testWidgets('360dp에서도 모집 문구는 한 줄', (tester) async {
    // 사용자가 접힘을 본 크기. 이 줄은 한글뿐이라 고정폭 글꼴로 재도
    // 실제와 거의 같다 — 여기서 통과하면 실제로도 안 접힌다.
    //
    // 예전 문구 "우리 동아리·학과 행사도 여기 올리고 싶다면?"은 이 폭에서
    // 두 줄이 됐다.
    await pumpBox(tester, 360);
    expect(fitsOneLine(tester, headline), isTrue);
  });

  testWidgets('가장 좁은 폭(320dp)에서도 넘치지는 않는다', (tester) async {
    // 여기서는 접혀도 좋다. 다만 칸 밖으로 흘러넘치면(노란 줄무늬) 안 된다.
    await pumpBox(tester, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('누르면 문의로 연결된다', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: boxWidth(360),
              child: ExitPromoSponsorBox(
                phone: "010-8032-8088",
                priceText: price,
                accent: Colors.blue,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ExitPromoSponsorBox));
    expect(tapped, isTrue);
  });
}
