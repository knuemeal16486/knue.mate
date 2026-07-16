import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/notice_model.dart';

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
}
