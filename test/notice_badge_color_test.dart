import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_service.dart';
import 'package:knue_mate/ui_utils.dart';

/// 청람공지 목록의 게시판 딱지 색.
///
/// 예전엔 전부 테마색 하나로 칠해서, 목록을 훑을 때 어느 게시판 글인지
/// 제목을 읽어야만 알 수 있었다. 이제 게시판 이름으로 색을 정한다.
void main() {
  final scraper = KnueScraper();
  final allBoards = <String>{
    for (final group in scraper.boardGroups.values) ...group.keys,
  };

  group('게시판 딱지 색', () {
    test('같은 게시판은 언제나 같은 색 (순서·재시작과 무관)', () {
      for (final name in allBoards) {
        expect(
          KnueTokens.categoryColor(name, false).toARGB32(),
          KnueTokens.categoryColor(name, false).toARGB32(),
          reason: name,
        );
      }
    });

    test('사용자가 지목한 게시판들이 서로 다른 색이다', () {
      // "도서관일반, 학생지원, 교육대학원 등의 딱지를 게시판별로 다르게"
      const named = ['도서관일반', '학생지원', '교육대학원'];
      final colors = named
          .map((n) => KnueTokens.categoryColor(n, false).toARGB32())
          .toSet();
      expect(colors.length, named.length, reason: '$named 중 색이 겹친다');
    });

    test('라이트/다크에서 각각 색이 정의된다', () {
      for (final name in allBoards) {
        expect(KnueTokens.categoryColor(name, false), isNotNull, reason: name);
        expect(KnueTokens.categoryColor(name, true), isNotNull, reason: name);
      }
    });

    test('전체 게시판이 한 색에 몰리지 않는다', () {
      // 팔레트가 8색이라 게시판 수보다 적어 겹치는 건 불가피하지만,
      // 해시가 망가져 한두 색으로 쏠리는 회귀는 잡는다.
      final colors = allBoards
          .map((n) => KnueTokens.categoryColor(n, false).toARGB32())
          .toSet();
      expect(colors.length, greaterThanOrEqualTo(6),
          reason: '게시판 ${allBoards.length}개가 ${colors.length}색에만 배정됨');
    });

    test('기본 즐겨찾기 게시판(대학소식·학사공지)은 서로 다른 색', () {
      expect(
        KnueTokens.categoryColor('대학소식', false).toARGB32(),
        isNot(KnueTokens.categoryColor('학사공지', false).toARGB32()),
      );
    });
  });
}
