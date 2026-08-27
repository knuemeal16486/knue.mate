/// KNUE 게시판 공지 한 건. (KNUE_MoA notice_model.dart 이식, Hive 제거)
class Notice {
  final int id;
  final String category; // 게시판 이름 (예: 학사공지)
  final String group; // 게시판 그룹 (MAIN/ANNEX/LIFE/DEPT)
  final String title;
  final String date; // yyyy-MM-dd
  final String author;
  final String link;
  final bool isNew;
  bool isRead;

  Notice({
    required this.id,
    required this.category,
    required this.group,
    required this.title,
    required this.date,
    required this.author,
    required this.link,
    this.isNew = false,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'group': group,
        'title': title,
        'date': date,
        'author': author,
        'link': link,
        'isNew': isNew,
        'isRead': isRead,
      };

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
        id: json['id'] as int,
        category: json['category'] as String,
        group: json['group'] as String,
        title: json['title'] as String,
        date: json['date'] as String,
        author: json['author'] as String? ?? '',
        link: json['link'] as String? ?? '',
        isNew: json['isNew'] as bool? ?? false,
        isRead: json['isRead'] as bool? ?? false,
      );
}

/// 학사일정 이벤트 (KNUE_MoA scraper_service.dart의 CalendarEvent 이식)
class CalendarEvent {
  final DateTime startDate;
  final DateTime endDate;
  final String title;

  CalendarEvent({
    required this.startDate,
    required this.endDate,
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'start': startDate.toIso8601String(),
        'end': endDate.toIso8601String(),
        'title': title,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return DateTime.now();
      try {
        return DateTime.parse(dateStr);
      } catch (e) {
        return DateTime.now();
      }
    }

    return CalendarEvent(
      startDate: parseDate(json['start'] as String?),
      endDate: parseDate(json['end'] as String?),
      title: json['title'] as String? ?? '',
    );
  }
}
