import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_model.dart';

void main() {
  test('Notice JSON 왕복 직렬화', () {
    final n = Notice(
      id: 12345,
      category: '학사공지',
      group: 'MAIN',
      title: '2026학년도 2학기 수강신청 안내',
      date: '2026-07-15',
      author: '교무처',
      link: 'https://www.knue.ac.kr/www/selectBbsNttView.do?nttNo=12345',
      isNew: true,
    );
    final restored = Notice.fromJson(n.toJson());
    expect(restored.id, 12345);
    expect(restored.category, '학사공지');
    expect(restored.group, 'MAIN');
    expect(restored.title, '2026학년도 2학기 수강신청 안내');
    expect(restored.isNew, true);
    expect(restored.isRead, false);
  });

  test('CalendarEvent.fromJson은 missing start/end를 throw하지 않음', () {
    final event = CalendarEvent.fromJson({'title': 'Test Event'});
    expect(event.title, 'Test Event');
    expect(event.startDate, isA<DateTime>());
    expect(event.endDate, isA<DateTime>());
  });
}
