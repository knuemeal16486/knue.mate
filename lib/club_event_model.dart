import 'package:cloud_firestore/cloud_firestore.dart';

/// 동아리 공연/행사 한 건. Firestore `club_events` 컬렉션 문서와 대응.
class ClubEvent {
  final String id;
  final String title;
  final String clubName;
  final DateTime startDate;
  final DateTime? endDate;
  final String location;
  final String description;
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
    required this.posterUrl,
    required this.externalLink,
    required this.isFeatured,
    required this.createdAt,
  });

  /// 캐시용 JSON (SharedPreferences 저장). DateTime → ISO8601.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'clubName': clubName,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'location': location,
        'description': description,
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
        posterUrl: data['posterUrl'] as String?,
        externalLink: data['externalLink'] as String?,
        isFeatured: data['isFeatured'] as bool? ?? false,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
