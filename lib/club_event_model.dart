import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// 행사 종류. 카드에 붙는 딱지이고 목록에서 걸러내는 기준이 된다.
///
/// ⚠️ [key]는 Firestore에 그대로 저장되는 값이라 바꾸면 이미 등록된 행사의
/// 종류가 전부 "기타"로 떨어진다. 라벨만 고칠 것.
enum ClubEventCategory {
  school('학교 행사', 'school', 0),
  club('동아리 공연', 'club', 3),
  busking('버스킹', 'busking', 5),
  dept('학과 행사', 'dept', 1),
  etc('기타', 'etc', 6);

  final String label;
  final String key;

  /// KnueTokens.inkAt 팔레트 번호. 원색 대신 채도를 낮춘 색을 써서
  /// 딱지가 여러 개 깔려도 어지럽지 않게 한다.
  final int inkIndex;

  const ClubEventCategory(this.label, this.key, this.inkIndex);

  /// 저장값 → 종류. 종류가 없던 시절에 등록된 행사는 [etc]가 된다.
  static ClubEventCategory fromKey(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return etc;
  }
}

/// 동아리 공연/행사 한 건. Firestore `club_events` 컬렉션 문서와 대응.
class ClubEvent {
  final String id;
  final String title;
  final String clubName;
  final DateTime startDate;
  final DateTime? endDate;
  final String location;
  final String description;
  final ClubEventCategory category;
  final String? posterUrl;
  final String? externalLink;
  final bool isFeatured;
  final DateTime createdAt;

  ClubEvent({
    required this.id,
    required this.title,
    required this.clubName,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.description,
    this.category = ClubEventCategory.etc,
    required this.posterUrl,
    required this.externalLink,
    required this.isFeatured,
    required this.createdAt,
  });

  /// 행사가 끝나는 시점. 끝 날짜가 없으면 시작한 그 날 자정까지로 본다
  /// (시작 시각만 등록된 행사가 시작하자마자 "끝남"이 되면 안 된다).
  DateTime get effectiveEnd {
    final e = endDate ?? startDate;
    return DateTime(e.year, e.month, e.day, 23, 59, 59);
  }

  /// 지금 열리고 있는 행사인가. 시작일 0시부터 끝나는 날 자정까지.
  bool isOngoing(DateTime now) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    return !now.isBefore(start) && !now.isAfter(effectiveEnd);
  }

  /// 이미 끝난 행사인가. 목록에서 감추는 기준.
  bool hasEnded(DateTime now) => now.isAfter(effectiveEnd);

  /// 목록 정렬 기준: 진행중인 것을 맨 위에, 그 아래로 시작이 가까운 순.
  /// 같은 날이면 추천 행사를 먼저 보여준다.
  static int compareForList(ClubEvent a, ClubEvent b, DateTime now) {
    final ao = a.isOngoing(now), bo = b.isOngoing(now);
    if (ao != bo) return ao ? -1 : 1;
    if (ao && bo) {
      // 둘 다 진행중이면 먼저 끝나는 것부터 — 놓치면 안 되는 순서다.
      final byEnd = a.effectiveEnd.compareTo(b.effectiveEnd);
      if (byEnd != 0) return byEnd;
    } else {
      final byStart = a.startDate.compareTo(b.startDate);
      if (byStart != 0) return byStart;
    }
    if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
    return a.title.compareTo(b.title);
  }

  /// 앱 종료 팝업에 보여줄 행사 하나를 고른다. 맨 위 것만 매번 보여주면
  /// 뒤로가기를 여러 번 누르는 사람 눈엔 항상 같은 행사만 보인다 —
  /// 진행중인 것 중 상위 [topN]개(정렬은 [compareForList] 기준으로 이미
  /// 돼 있다고 가정) 안에서 무작위로 하나 골라 노출을 나눠준다. [random]은
  /// 테스트에서 결과를 고정하려고 주입하는 용도.
  static ClubEvent? pickForExitPromo(
    List<ClubEvent> sortedOngoing, {
    int topN = 3,
    math.Random? random,
  }) {
    if (sortedOngoing.isEmpty) return null;
    final top = sortedOngoing.take(topN).toList();
    final r = random ?? math.Random();
    return top[r.nextInt(top.length)];
  }

  /// 캐시용 JSON (SharedPreferences 저장). DateTime → ISO8601.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'clubName': clubName,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'location': location,
    'description': description,
    'category': category.key,
    'posterUrl': posterUrl,
    'externalLink': externalLink,
    'isFeatured': isFeatured,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ClubEvent.fromJson(Map<String, dynamic> json) => ClubEvent(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    clubName: json['clubName'] as String? ?? '',
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: (json['endDate'] as String?) != null
        ? DateTime.parse(json['endDate'] as String)
        : null,
    location: json['location'] as String? ?? '',
    description: json['description'] as String? ?? '',
    category: ClubEventCategory.fromKey(json['category'] as String?),
    posterUrl: json['posterUrl'] as String?,
    externalLink: json['externalLink'] as String?,
    isFeatured: json['isFeatured'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  /// Firestore 쓰기용. id는 문서 ID이므로 제외, DateTime → Timestamp.
  Map<String, dynamic> toFirestore() => {
    'title': title,
    'clubName': clubName,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    'location': location,
    'description': description,
    'category': category.key,
    'posterUrl': posterUrl,
    'externalLink': externalLink,
    'isFeatured': isFeatured,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory ClubEvent.fromFirestore(String id, Map<String, dynamic> data) =>
      ClubEvent(
        id: id,
        title: data['title'] as String? ?? '',
        clubName: data['clubName'] as String? ?? '',
        startDate: (data['startDate'] as Timestamp).toDate(),
        endDate: (data['endDate'] as Timestamp?)?.toDate(),
        location: data['location'] as String? ?? '',
        description: data['description'] as String? ?? '',
        category: ClubEventCategory.fromKey(data['category'] as String?),
        posterUrl: data['posterUrl'] as String?,
        externalLink: data['externalLink'] as String?,
        isFeatured: data['isFeatured'] as bool? ?? false,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
