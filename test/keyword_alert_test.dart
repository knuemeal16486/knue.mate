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

  group('isDigestDue (하루 N번 지정 시각 알림)', () {
    test('아직 아무 것도 안 보냈고 지정 시각을 지났으면 보낼 때', () {
      final due = KeywordAlertService.isDigestDue(
        now: DateTime(2026, 9, 17, 10, 0),
        targetHours: [9, 18],
        lastDigestSentAt: null,
      );
      expect(due, isTrue); // 9시는 지났고 아직 한 번도 안 보냈다
    });

    test('오늘 지정 시각을 아직 하나도 안 지났으면 안 보낼 때', () {
      final due = KeywordAlertService.isDigestDue(
        now: DateTime(2026, 9, 17, 8, 0),
        targetHours: [9, 18],
        lastDigestSentAt: null,
      );
      expect(due, isFalse);
    });

    test('그 시각 이후로 이미 한 번 보냈으면 다시 안 보낸다', () {
      final due = KeywordAlertService.isDigestDue(
        now: DateTime(2026, 9, 17, 10, 0),
        targetHours: [9, 18],
        lastDigestSentAt: DateTime(2026, 9, 17, 9, 30), // 9시 이후에 이미 보냄
      );
      expect(due, isFalse);
    });

    test('다음 지정 시각(18시)이 지나면 그날 두 번째로 다시 보낸다', () {
      final due = KeywordAlertService.isDigestDue(
        now: DateTime(2026, 9, 17, 19, 0),
        targetHours: [9, 18],
        lastDigestSentAt: DateTime(2026, 9, 17, 9, 30), // 9시치는 이미 보냄
      );
      expect(due, isTrue); // 18시치는 아직 안 보냄
    });

    test('점검이 며칠 건너뛰어도 날짜가 바뀌면 다시 보낼 때로 판단한다', () {
      final due = KeywordAlertService.isDigestDue(
        now: DateTime(2026, 9, 19, 10, 0),
        targetHours: [9, 18],
        lastDigestSentAt: DateTime(2026, 9, 17, 18, 30), // 이틀 전 마지막 발송
      );
      expect(due, isTrue);
    });
  });
}
