// 시간표 탭의 "오늘 시간표인지"(2026-11-12). 평일 밤에 휴일 시간표를 열면
// 지나간 버스 표시 때문에 전부 "출발함"이 되던 것을 막는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

void main() {
  final wed = DateTime(2026, 11, 11, 23);
  final sat = DateTime(2026, 11, 14, 23);

  test('평일엔 평일 시간표만 오늘 것', () {
    expect(isTodaysTimetable(route: '513', viewingHoliday: false, now: wed), isTrue);
    expect(isTodaysTimetable(route: '513', viewingHoliday: true, now: wed), isFalse);
  });

  test('토요일엔 휴일 시간표가 오늘 것', () {
    expect(isTodaysTimetable(route: '513', viewingHoliday: true, now: sat), isTrue);
    expect(isTodaysTimetable(route: '513', viewingHoliday: false, now: sat), isFalse);
  });

  test('913은 요일 구분이 없다', () {
    expect(isTodaysTimetable(route: '913', viewingHoliday: true, now: wed), isTrue);
  });
}
