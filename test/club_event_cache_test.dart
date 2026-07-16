import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/club_event_model.dart';
import 'package:knue_mate/club_event_service.dart';

ClubEvent _ev(String id) => ClubEvent(
      id: id,
      title: '공연$id',
      clubName: '동아리$id',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: '장소',
      description: '설명',
      posterUrl: null,
      externalLink: null,
      isFeatured: false,
      createdAt: DateTime(2026, 5, 1),
    );

void main() {
  test('ClubEventCache 저장/복원 왕복', () async {
    SharedPreferences.setMockInitialValues({});
    await ClubEventCache.save([_ev('1'), _ev('2')]);
    final loaded = await ClubEventCache.load();
    expect(loaded, isNotNull);
    expect(loaded!.length, 2);
    expect(loaded[0].id, '1');
    expect(loaded[1].title, '공연2');
  });

  test('캐시 없으면 null, lastUpdated도 null', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ClubEventCache.load(), isNull);
    expect(await ClubEventCache.lastUpdated(), isNull);
  });

  test('저장 시 lastUpdated 기록', () async {
    SharedPreferences.setMockInitialValues({});
    await ClubEventCache.save([_ev('1')]);
    expect(await ClubEventCache.lastUpdated(), isNotNull);
  });
}
