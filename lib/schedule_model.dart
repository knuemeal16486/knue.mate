/// D-day 항목. id는 생성 시각 밀리초 문자열 (uuid 미도입 방침).
class DdayItem {
  final String id;
  final String title;
  final DateTime date;

  DdayItem({required this.id, required this.title, required this.date});

  /// 남은 일수. 오늘이면 0, 지났으면 음수.
  int daysLeft(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'date': date.toIso8601String()};

  factory DdayItem.fromJson(Map<String, dynamic> json) => DdayItem(
        id: json['id'] as String,
        title: json['title'] as String,
        date: DateTime.parse(json['date'] as String),
      );
}

/// 개인 일정 (캘린더 표시용)
class PersonalEvent {
  final String id;
  final String title;
  final DateTime date;

  PersonalEvent({required this.id, required this.title, required this.date});

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'date': date.toIso8601String()};

  factory PersonalEvent.fromJson(Map<String, dynamic> json) => PersonalEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        date: DateTime.parse(json['date'] as String),
      );
}
