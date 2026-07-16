import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_model.dart';

void main() {
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
