import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/schedule_model.dart';

void main() {
  test('DdayItem daysLeft 계산', () {
    final d = DdayItem(
        id: '1', title: '기말고사', date: DateTime(2026, 7, 20));
    expect(d.daysLeft(DateTime(2026, 7, 16)), 4);
    expect(d.daysLeft(DateTime(2026, 7, 20)), 0);
    expect(d.daysLeft(DateTime(2026, 7, 21)), -1);
  });

  test('DdayItem/PersonalEvent JSON 왕복', () {
    final d = DdayItem(id: 'a', title: '개강', date: DateTime(2026, 9, 1));
    expect(DdayItem.fromJson(d.toJson()).title, '개강');
    final p = PersonalEvent(
        id: 'b', title: '과제 마감', date: DateTime(2026, 7, 18));
    expect(PersonalEvent.fromJson(p.toJson()).date.day, 18);
  });
}
