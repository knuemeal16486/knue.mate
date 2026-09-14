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

  /// 제목으로 판정한 일정 종류. 캘린더에서 색을 나누는 데 쓴다.
  AcademicEventKind get kind => AcademicEventKind.of(title);
}

/// 학사일정 종류. 학교가 종류를 따로 알려주지 않으므로 제목의 키워드로 나눈다.
///
/// [inkIndex]는 [KnueTokens.inkAt]의 잉크 팔레트 인덱스다. 원색 대신 채도를
/// 낮춘 색을 써서, 한 달치가 한 화면에 깔려도 어지럽지 않게 한다.
enum AcademicEventKind {
  exam('시험', 7, ['시험', '고사', '평가']),
  registration('수강·등록', 5, ['수강신청', '등록금', '납부', '수강정정', '수강신청기간']),
  term('학기', 0, ['개강', '종강', '개학', '학기', '수업일수', '보강', '휴강']),
  breakTime('방학·휴일', 4, ['방학', '휴일', '공휴일', '개교기념일', '연휴', '재량휴업']),
  ceremony('행사', 3, ['입학식', '졸업식', '축제', '체육대회', '설명회', '오리엔테이션', '행사']),
  other('기타', 6, []);

  final String label;
  final int inkIndex;
  final List<String> _keywords;
  const AcademicEventKind(this.label, this.inkIndex, this._keywords);

  /// 제목에 맞는 종류. 어느 키워드에도 안 걸리면 [other].
  /// 선언 순서대로 검사하므로, 더 구체적인 종류를 위에 둔다
  /// (예: "기말고사 기간"은 시험이지 학기가 아니다).
  static AcademicEventKind of(String title) {
    for (final kind in values) {
      if (kind._keywords.any(title.contains)) return kind;
    }
    return other;
  }
}
