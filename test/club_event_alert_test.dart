import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_model.dart';
import 'package:knue_mate/club_event_alert_service.dart';

ClubEvent _ev(String id, {required bool featured}) => ClubEvent(
      id: id,
      title: '공연$id',
      clubName: '동아리',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: '장소',
      description: '',
      posterUrl: null,
      externalLink: null,
      isFeatured: featured,
      createdAt: DateTime(2026, 5, 1),
    );

void main() {
  test('녹출이면서 아직 안 알린 행사만 선별', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [
        _ev('1', featured: true),
        _ev('2', featured: false), // 녹출 아님
        _ev('3', featured: true),
      ],
      notifiedIds: {'1'}, // 이미 알림
    );
    expect(result.map((e) => e.id), ['3']);
  });

  test('전부 이미 알렸으면 빈 리스트', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [_ev('1', featured: true)],
      notifiedIds: {'1'},
    );
    expect(result, isEmpty);
  });

  test('녹출 없으면 빈 리스트', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [_ev('1', featured: false)],
      notifiedIds: {},
    );
    expect(result, isEmpty);
  });
}
