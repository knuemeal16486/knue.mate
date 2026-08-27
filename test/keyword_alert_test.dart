import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/keyword_alert_service.dart';
import 'package:knue_mate/notice_model.dart';

Notice _n(int id, String category, String title) => Notice(
    id: id, category: category, group: 'MAIN', title: title,
    date: '2026-07-16', author: '', link: '');

void main() {
  test('키워드 매칭 + 이미 알린 공지 제외', () {
    final result = KeywordAlertService.filterNewMatches(
      notices: [
        _n(1, '학사공지', '2학기 수강신청 안내'),
        _n(2, '학사공지', '도서관 휴관 안내'),
        _n(3, '장학금', '국가장학금 2차 신청'),
      ],
      keywords: ['수강', '장학'],
      favBoards: [],
      notifiedIds: {'3'},
    );
    expect(result.map((n) => n.id), [1]); // 2는 키워드 불일치, 3은 이미 알림
  });

  test('관심 게시판 지정 시 그 외 게시판 제외', () {
    final result = KeywordAlertService.filterNewMatches(
      notices: [_n(1, '학사공지', '수강 안내'), _n(2, '입찰공고', '수강 장비 입찰')],
      keywords: ['수강'],
      favBoards: ['학사공지'],
      notifiedIds: {},
    );
    expect(result.map((n) => n.id), [1]);
  });

  test('키워드 비어 있으면 관심 게시판 새 글 전부 매칭', () {
    final result = KeywordAlertService.filterNewMatches(
      notices: [_n(1, '학사공지', '아무 공지')],
      keywords: [],
      favBoards: ['학사공지'],
      notifiedIds: {},
    );
    expect(result, hasLength(1));
  });
}
