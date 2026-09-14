import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_model.dart';

void main() {
  _categoryAndOrderTests();

  test('ClubEvent JSON 왕복 직렬화', () {
    final e = ClubEvent(
      id: 'abc123',
      title: '봄 정기공연',
      clubName: '노래패 청람',
      startDate: DateTime(2026, 5, 20, 18, 30),
      endDate: DateTime(2026, 5, 20, 20, 0),
      location: '학생회관 대강당',
      description: '동아리 봄 정기공연입니다.',
      posterUrl: 'https://example.com/poster.jpg',
      externalLink: 'https://forms.gle/xyz',
      isFeatured: true,
      createdAt: DateTime(2026, 5, 1, 9, 0),
    );
    final restored = ClubEvent.fromJson(e.toJson());
    expect(restored.id, 'abc123');
    expect(restored.title, '봄 정기공연');
    expect(restored.clubName, '노래패 청람');
    expect(restored.startDate, DateTime(2026, 5, 20, 18, 30));
    expect(restored.endDate, DateTime(2026, 5, 20, 20, 0));
    expect(restored.location, '학생회관 대강당');
    expect(restored.isFeatured, true);
    expect(restored.posterUrl, 'https://example.com/poster.jpg');
    expect(restored.externalLink, 'https://forms.gle/xyz');
  });

  test('선택 필드(endDate/posterUrl/externalLink) 없어도 왕복', () {
    final e = ClubEvent(
      id: 'x',
      title: 't',
      clubName: 'c',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: 'l',
      description: 'd',
      posterUrl: null,
      externalLink: null,
      isFeatured: false,
      createdAt: DateTime(2026, 5, 1),
    );
    final restored = ClubEvent.fromJson(e.toJson());
    expect(restored.endDate, isNull);
    expect(restored.posterUrl, isNull);
    expect(restored.externalLink, isNull);
    expect(restored.isFeatured, false);
  });
}

// ── 행사 종류 딱지와 목록 정렬 ─────────────────────────────────────────
ClubEvent ev(
  String title,
  DateTime start, {
  DateTime? end,
  ClubEventCategory category = ClubEventCategory.etc,
  bool featured = false,
}) =>
    ClubEvent(
      id: title,
      title: title,
      clubName: '',
      startDate: start,
      endDate: end,
      location: '',
      description: '',
      category: category,
      posterUrl: null,
      externalLink: null,
      isFeatured: featured,
      createdAt: DateTime(2026, 1, 1),
    );

void _categoryAndOrderTests() {
  group('행사 종류', () {
    test('저장값으로 왕복한다', () {
      for (final c in ClubEventCategory.values) {
        expect(ClubEventCategory.fromKey(c.key), c);
      }
    });

    test('종류가 없던 시절 행사는 기타가 된다', () {
      // 종류를 넣기 전에 등록된 문서에는 category 필드가 아예 없다.
      expect(ClubEventCategory.fromKey(null), ClubEventCategory.etc);
      expect(ClubEventCategory.fromKey('없는값'), ClubEventCategory.etc);
    });

    test('JSON 왕복에서 종류가 살아남는다', () {
      final e = ev('버스킹', DateTime(2026, 5, 1),
          category: ClubEventCategory.busking);
      expect(ClubEvent.fromJson(e.toJson()).category,
          ClubEventCategory.busking);
    });
  });

  group('진행중 판정', () {
    final now = DateTime(2026, 5, 20, 14, 0);

    test('시작 시각 전이라도 그 날이면 진행중이다', () {
      // 18시 공연을 낮에 열어봐도 "오늘 열린다"고 보여야 한다.
      expect(ev('오늘', DateTime(2026, 5, 20, 18, 0)).isOngoing(now), isTrue);
    });

    test('끝 날짜가 없으면 그 날 자정까지 진행중이다', () {
      final e = ev('하루', DateTime(2026, 5, 20, 9, 0));
      expect(e.isOngoing(now), isTrue);
      expect(e.hasEnded(now), isFalse);
      expect(e.hasEnded(DateTime(2026, 5, 21, 0, 1)), isTrue);
    });

    test('기간 행사는 마지막 날까지 진행중이다', () {
      final e = ev('축제', DateTime(2026, 5, 19), end: DateTime(2026, 5, 22));
      expect(e.isOngoing(now), isTrue);
      expect(e.hasEnded(DateTime(2026, 5, 22, 23, 0)), isFalse);
      expect(e.hasEnded(DateTime(2026, 5, 23, 0, 1)), isTrue);
    });
  });

  group('목록 정렬', () {
    final now = DateTime(2026, 5, 20, 14, 0);

    test('진행중이 맨 위, 아래로 갈수록 먼 날짜', () {
      final list = [
        ev('다음달', DateTime(2026, 6, 20)),
        ev('모레', DateTime(2026, 5, 22)),
        ev('진행중', DateTime(2026, 5, 19), end: DateTime(2026, 5, 21)),
        ev('내일', DateTime(2026, 5, 21)),
      ]..sort((a, b) => ClubEvent.compareForList(a, b, now));
      expect(list.map((e) => e.title).toList(),
          ['진행중', '내일', '모레', '다음달']);
    });

    test('진행중이 여럿이면 먼저 끝나는 것부터', () {
      // 곧 끝나는 것을 놓치면 안 되니 위로 올린다.
      final list = [
        ev('길게', DateTime(2026, 5, 18), end: DateTime(2026, 5, 25)),
        ev('오늘까지', DateTime(2026, 5, 18), end: DateTime(2026, 5, 20)),
      ]..sort((a, b) => ClubEvent.compareForList(a, b, now));
      expect(list.first.title, '오늘까지');
    });

    test('같은 날이면 추천 행사가 먼저', () {
      final list = [
        ev('보통', DateTime(2026, 5, 25)),
        ev('추천', DateTime(2026, 5, 25), featured: true),
      ]..sort((a, b) => ClubEvent.compareForList(a, b, now));
      expect(list.first.title, '추천');
    });
  });
}
