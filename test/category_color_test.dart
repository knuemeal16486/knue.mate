// 게시판 식별색이 (1) 이름마다 안정적이고 (2) 주요 게시판끼리 겹치지 않는지 확인.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/ui_utils.dart';

void main() {
  group('KnueTokens.categoryColor', () {
    test('같은 이름은 항상 같은 색을 준다', () {
      for (final n in ['대학소식', '학사공지', '교육학과', '유아교육과']) {
        final a = KnueTokens.categoryColor(n, false);
        final b = KnueTokens.categoryColor(n, false);
        expect(a, b, reason: '$n 색이 호출마다 달라짐');
      }
    });

    test('기본 즐겨찾기 두 게시판은 서로 다른 색이다', () {
      expect(
        KnueTokens.categoryColor('대학소식', false),
        isNot(KnueTokens.categoryColor('학사공지', false)),
      );
    });

    test('라이트/다크가 각각 다른 값을 준다', () {
      for (final n in ['대학소식', '장학금']) {
        expect(
          KnueTokens.categoryColor(n, false),
          isNot(KnueTokens.categoryColor(n, true)),
        );
      }
    });

    test('홈 빠른 실행 4종이 서로 겹치지 않는다', () {
      final keys = ['동아리', '자취방', '캠퍼스런', '교직원 연락처'];
      for (final dark in [false, true]) {
        final colors = keys.map((k) => KnueTokens.categoryColor(k, dark)).toSet();
        expect(colors.length, keys.length,
            reason: 'dark=$dark 에서 빠른 실행 색이 겹침');
      }
    });

    test('지정되지 않은 이름도 팔레트 안의 색을 준다', () {
      final c = KnueTokens.categoryColor('한번도없던게시판', false);
      expect(c, isA<Color>());
      // 팔레트 밖 색이 나오면 안 된다 — 지정 게시판 색 중 하나와 반드시 일치.
      final palette = ['대학소식', '학사공지', '장학금', '등록금', '학점교류', '청람소양', '행사세미나', '채용공고']
          .map((n) => KnueTokens.categoryColor(n, false))
          .toSet();
      expect(palette.contains(c), isTrue);
    });
  });
}
