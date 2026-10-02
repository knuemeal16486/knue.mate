import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/legal_tips.dart';
import 'package:knue_mate/legal_tips_screen.dart';

/// 화면의 제목은 낱말 붙이기([keepKoreanWords])를 거친 글자로 그려진다.
Finder tipTitle(String s) => find.text(keepKoreanWords(s));

void main() {
  test('id는 겹치지 않는다', () {
    final ids = kLegalTips.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('모든 항목에 주제·묶음·본문이 있다', () {
    for (final t in kLegalTips) {
      expect(t.topics, isNotEmpty, reason: t.id);
      expect(t.group.trim(), isNotEmpty, reason: t.id);
      expect(t.title.trim(), isNotEmpty, reason: t.id);
      expect(t.summary.trim(), isNotEmpty, reason: t.id);
      expect(t.points, isNotEmpty, reason: t.id);
    }
  });

  test('근거를 적었으면 조 번호가 있다', () {
    for (final t in kLegalTips) {
      if (t.basis != null) {
        expect(t.basis, contains('제'), reason: '${t.id}: 조 번호가 없다');
      }
    }
  });

  test('링크는 https이고 이름표와 짝을 이룬다', () {
    for (final t in kLegalTips) {
      expect(t.linkUrl == null, t.linkLabel == null, reason: t.id);
      if (t.linkUrl != null) {
        expect(Uri.parse(t.linkUrl!).scheme, 'https', reason: t.id);
      }
    }
  });

  test('굵게 표시(**)는 짝이 맞고, 제목·요약에는 쓰지 않는다', () {
    for (final t in kLegalTips) {
      expect(t.title, isNot(contains('**')), reason: t.id);
      expect(t.summary, isNot(contains('**')), reason: t.id);
      for (final p in t.points) {
        expect(
          '**'.allMatches(p).length.isEven,
          isTrue,
          reason: '${t.id}: $p',
        );
        expect(p, isNot(contains('****')), reason: '${t.id}: 빈 굵게 표시');
      }
    }
  });

  test('주제마다 항목과 상담처가 있다', () {
    for (final topic in LegalTopic.values) {
      expect(
        kLegalTips.any((t) => t.topics.contains(topic)),
        isTrue,
        reason: topic.label,
      );
      expect(
        kLegalContacts.any((c) => c.topics.contains(topic)),
        isTrue,
        reason: topic.label,
      );
    }
  });

  test('상담처는 전화나 누리집 중 하나가 있다', () {
    for (final c in kLegalContacts) {
      expect(c.tel != null || c.url != null, isTrue, reason: c.name);
      if (c.url != null) {
        expect(Uri.parse(c.url!).scheme, 'https', reason: c.name);
      }
    }
  });

  group('parseLegalEmphasis', () {
    List<(String, bool)> parse(String s) =>
        parseLegalEmphasis(s).map((e) => (e.text, e.bold)).toList();

    test('표시가 없으면 한 조각', () {
      expect(parse('그냥 글'), [('그냥 글', false)]);
    });

    test('가운데·처음·끝의 굵게', () {
      expect(parse('앞 **굵게** 뒤'), [
        ('앞 ', false),
        ('굵게', true),
        (' 뒤', false),
      ]);
      expect(parse('**처음** 뒤'), [('처음', true), (' 뒤', false)]);
      expect(parse('앞 **끝**'), [('앞 ', false), ('끝', true)]);
    });

    test('한 줄에 여러 번', () {
      expect(parse('**가** 나 **다**'), [
        ('가', true),
        (' 나 ', false),
        ('다', true),
      ]);
    });

    test('짝이 안 맞으면 전부 보통 글씨', () {
      expect(parse('앞 **뒤'), [('앞 ', false), ('뒤', false)]);
    });

    test('plainLegalText는 표시만 걷어낸다', () {
      expect(plainLegalText('앞 **굵게** 뒤'), '앞 굵게 뒤');
    });
  });

  group('keepKoreanWords', () {
    const j = '‍';

    test('낱말 안에만 이음 문자를 끼우고 띄어쓰기는 그대로 둔다', () {
      expect(keepKoreanWords('받아 두세요'), '받$j아 두$j세$j요');
    });

    test('한 글자와 빈 글은 그대로', () {
      expect(keepKoreanWords('가'), '가');
      expect(keepKoreanWords(''), '');
    });

    test('이음 문자를 빼면 원문이다', () {
      for (final t in kLegalTips) {
        expect(keepKoreanWords(t.title).replaceAll(j, ''), t.title);
      }
    });
  });

  group('legalDisplaySpans', () {
    const j = '‍';

    test('굵은 조각과 맞닿은 문장부호 사이도 붙인다', () {
      final spans = legalDisplaySpans('**갑구**: 소유권');
      expect(spans.map((s) => s.bold), [true, false]);
      expect(spans[0].text, '갑$j구$j');
      expect(spans[1].text, ': 소$j유$j권');
    });

    test('띄어쓰기로 갈린 조각 사이는 붙이지 않는다', () {
      final spans = legalDisplaySpans('앞 **굵게** 뒤');
      expect(spans[0].text, '앞 ');
      expect(spans[1].text, '굵$j게');
      expect(spans[2].text, ' 뒤');
    });

    test('모든 본문에서 이음 문자를 빼면 원문과 같다', () {
      for (final t in kLegalTips) {
        for (final p in t.points) {
          final shown =
              legalDisplaySpans(p).map((s) => s.text).join().replaceAll(j, '');
          expect(shown, plainLegalText(p), reason: t.id);
        }
      }
    });
  });

  group('legalPointKind', () {
    test('예)로 시작하면 계산 예시', () {
      expect(legalPointKind('예) 300 + 35×70'), LegalPointKind.example);
    });

    test('따옴표로 통째로 감싸면 옮겨 쓸 문구', () {
      expect(legalPointKind('"새 권리를 설정하지 않는다."'), LegalPointKind.quote);
    });

    test('따옴표로 시작만 하면 보통 줄', () {
      expect(legalPointKind('"수습이라 깎는다"는 안 돼요.'), LegalPointKind.normal);
      expect(legalPointKind('**"가계약금"**도 돌려받기 어려워요.'), LegalPointKind.normal);
    });

    test('특약 항목에는 옮겨 쓸 문구가 있다', () {
      final terms = kLegalTips.firstWhere((t) => t.id == 'special-terms');
      expect(
        terms.points.where((p) => legalPointKind(p) == LegalPointKind.quote),
        isNotEmpty,
      );
    });
  });

  group('filterLegalTips', () {
    test('조건이 없으면 전부 돌려준다', () {
      expect(filterLegalTips(kLegalTips).length, kLegalTips.length);
    });

    test('주제로 추린다', () {
      final out = filterLegalTips(kLegalTips, topic: LegalTopic.housing);
      expect(out, isNotEmpty);
      expect(out.every((t) => t.topics.contains(LegalTopic.housing)), isTrue);
      expect(out.map((t) => t.id), isNot(contains('min-wage')));
    });

    test('묶음으로 추린다', () {
      final out = filterLegalTips(
        kLegalTips,
        topic: LegalTopic.life,
        group: '돈을 빌려줄 때',
      );
      expect(out.map((t) => t.id), ['lend-proof', 'lend-unpaid', 'guarantee-name']);
    });

    test('세금 항목은 과외와 알바 양쪽에 나오고 집 계약에는 없다', () {
      List<String> ids(LegalTopic topic) =>
          filterLegalTips(kLegalTips, topic: topic).map((t) => t.id).toList();
      expect(ids(LegalTopic.tutoring), contains('tax-3-3'));
      expect(ids(LegalTopic.partTime), contains('tax-3-3'));
      expect(ids(LegalTopic.housing), isNot(contains('tax-3-3')));
    });

    test('본문에만 있는 낱말도 찾는다', () {
      final out = filterLegalTips(kLegalTips, query: '임차권등기명령');
      expect(out.map((t) => t.id), contains('deposit-return'));
    });

    test('굵게 표시에 걸친 말도 찾는다', () {
      // 본문은 "**입주 + 전입신고 = 대항력.** 집주인이 …"
      final out = filterLegalTips(kLegalTips, query: '대항력. 집주인');
      expect(out.map((t) => t.id), contains('move-in-report'));
      expect(filterLegalTips(kLegalTips, query: '**'), isEmpty);
    });

    test('근거 조문으로도 찾는다', () {
      final out = filterLegalTips(kLegalTips, query: '제565조');
      expect(out.map((t) => t.id), ['down-payment']);
    });

    test('앞뒤 공백은 무시하고, 없는 낱말은 빈 목록', () {
      expect(filterLegalTips(kLegalTips, query: '  전입신고 '), isNotEmpty);
      expect(filterLegalTips(kLegalTips, query: '없는낱말zzz'), isEmpty);
    });

    test('주제와 검색어를 함께 건다', () {
      final out = filterLegalTips(
        kLegalTips,
        topic: LegalTopic.partTime,
        query: '주휴수당',
      );
      expect(out.map((t) => t.id), contains('weekly-15h'));
      expect(out.every((t) => t.topics.contains(LegalTopic.partTime)), isTrue);
    });
  });

  group('groupLegalTips', () {
    List<String> groupsOf(LegalTopic topic) =>
        groupLegalTips(filterLegalTips(kLegalTips, topic: topic)).keys.toList();

    test('집 계약은 계약 흐름 순서로 묶인다', () {
      expect(groupsOf(LegalTopic.housing), [
        '계약 전',
        '계약할 때',
        '입주 직후',
        '사는 동안',
        '나갈 때',
      ]);
    });

    test('알바와 과외는 세금·장학금 묶음이 맨 끝에 온다', () {
      for (final topic in [LegalTopic.partTime, LegalTopic.tutoring]) {
        expect(groupsOf(topic).last, '세금·장학금', reason: topic.label);
        expect(groupsOf(topic).length, 3, reason: topic.label);
      }
    });

    test('대학 생활은 돈을 빌려줄 때부터 시작한다', () {
      expect(groupsOf(LegalTopic.life).first, '돈을 빌려줄 때');
    });

    test('항목 수는 그대로다', () {
      final tips = filterLegalTips(kLegalTips, topic: LegalTopic.housing);
      final total = groupLegalTips(tips)
          .values
          .fold<int>(0, (sum, list) => sum + list.length);
      expect(total, tips.length);
    });
  });

  group('countLegalMatchesByTopic', () {
    test('검색어가 비면 빈 결과', () {
      expect(countLegalMatchesByTopic(kLegalTips, '  '), isEmpty);
    });

    test('걸리는 주제만 나온다', () {
      final out = countLegalMatchesByTopic(kLegalTips, '차용증');
      expect(out.keys, [LegalTopic.life]);
    });

    test('두 주제에 걸친 항목은 양쪽에서 센다', () {
      final out = countLegalMatchesByTopic(kLegalTips, '종합소득세');
      expect(out.keys, containsAll([LegalTopic.tutoring, LegalTopic.partTime]));
      expect(out.containsKey(LegalTopic.housing), isFalse);
    });
  });

  testWidgets('주제 네 개가 보이고, 고르면 그 주제 내용으로 바뀐다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalTipsScreen()));
    expect(find.text('법률상식'), findsOneWidget);
    for (final topic in LegalTopic.values) {
      expect(find.text(topic.label), findsOneWidget);
    }
    // 처음은 집 계약.
    expect(tipTitle('등기부등본은 내가 직접 떼요'), findsOneWidget);

    await tester.tap(find.text('아르바이트'));
    await tester.pumpAndSettle();
    expect(tipTitle('등기부등본은 내가 직접 떼요'), findsNothing);
    expect(tipTitle('근로계약서는 꼭 쓰고 한 부 받아요'), findsOneWidget);

    await tester.tap(find.text('학원강사(과외)'));
    await tester.pumpAndSettle();
    expect(tipTitle('근로계약서는 꼭 쓰고 한 부 받아요'), findsNothing);
    expect(tipTitle('"프리랜서" 계약이어도 근로자일 수 있어요'), findsOneWidget);

    await tester.tap(find.text('대학 생활'));
    await tester.pumpAndSettle();
    expect(tipTitle('친구·가족에게 빌려줄 땐 기록을 남겨요'), findsOneWidget);
  });

  testWidgets('묶음 칩으로 좁힌다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalTipsScreen()));
    // 칩과 목록의 묶음 제목 양쪽에 같은 글자가 있다. 칩이 먼저다.
    await tester.tap(find.text('나갈 때').first);
    await tester.pumpAndSettle();
    expect(tipTitle('등기부등본은 내가 직접 떼요'), findsNothing);
    expect(tipTitle('원상회복은 어디까지 해야 하나요?'), findsOneWidget);
  });

  testWidgets('이 주제에 없는 검색어는 다른 주제로 건너가게 해 준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalTipsScreen()));
    await tester.enterText(find.byType(TextField), '차용증');
    await tester.pumpAndSettle();
    expect(find.text('여기에는 없어요'), findsOneWidget);

    await tester.tap(find.textContaining('대학 생활에서'));
    await tester.pumpAndSettle();
    expect(tipTitle('친구·가족에게 빌려줄 땐 기록을 남겨요'), findsOneWidget);
  });

  testWidgets('좁은 폰(320dp)에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LegalTipsScreen()));
    for (final topic in LegalTopic.values) {
      await tester.tap(find.text(topic.label));
      await tester.pumpAndSettle();
    }
    // 계산 예시와 옮겨 쓸 문구가 있는 창도 열어 본다.
    await tester.tap(find.text(LegalTopic.housing.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계약할 때').first);
    await tester.pumpAndSettle();
    for (final title in ['약속은 특약에 글로 남겨요', '중개보수에는 상한이 있어요']) {
      await tester.ensureVisible(tipTitle(title));
      await tester.pumpAndSettle();
      await tester.tap(tipTitle(title));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legal-tip-sheet')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('legal-tip-sheet'))))
          .pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('카드를 누르면 본문 창이 올라온다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalTipsScreen()));
    // 목록에는 본문이 없다.
    expect(find.byKey(const Key('legal-tip-sheet')), findsNothing);
    expect(find.textContaining(keepKoreanWords('근거')), findsNothing);

    await tester.tap(tipTitle('등기부등본은 내가 직접 떼요'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legal-tip-sheet')), findsOneWidget);
    // 제목은 목록 카드와 창, 두 곳에 있다.
    expect(tipTitle('등기부등본은 내가 직접 떼요'), findsNWidgets(2));
    // 링크 버튼은 창을 끝까지 내려야 나온다.
    await tester.scrollUntilVisible(
      find.text('인터넷등기소 열어 보기'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('legal-tip-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('인터넷등기소 열어 보기'), findsOneWidget);
    expect(find.textContaining(keepKoreanWords('근거')), findsOneWidget);
  });
}
