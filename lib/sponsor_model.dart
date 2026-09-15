import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 광고 카드 아이콘 종류. `key`는 Firestore `sponsors` 문서의 `icon` 필드에
/// 그대로 저장된다 — [lib/native_ad_card.dart]의 `_parseIcon`이 이 키(와 몇몇
/// 동의어)를 보고 아이콘을 고른다. 그 매핑은 이미 운영 중이라 건드리지 않고,
/// 여기서는 관리 화면이 보여줄 칩 목록만 다시 정의한다.
///
/// ⚠️ [key]를 바꾸면 이미 등록된 광고의 아이콘이 기본값(campaign)으로 떨어진다.
enum SponsorCategory {
  restaurant('식당·음식', 'restaurant', Icons.restaurant_rounded),
  cafe('카페', 'cafe', Icons.local_cafe_rounded),
  store('마트·상점', 'store', Icons.storefront_rounded),
  study('학업·서점', 'school', Icons.school_rounded),
  transport('교통', 'bus', Icons.directions_bus_rounded),
  event('행사·축제', 'event', Icons.celebration_rounded),
  game('게임·e스포츠', 'game', Icons.sports_esports_rounded),
  discount('할인·쿠폰', 'discount', Icons.local_offer_rounded),
  housing('주거·부동산', 'housing', Icons.home_rounded),
  fitness('헬스·운동', 'fitness', Icons.fitness_center_rounded),
  pub('주점', 'beer', Icons.sports_bar_rounded),
  etc('기타', 'campaign', Icons.campaign_rounded);

  final String label;
  final String key;
  final IconData icon;
  const SponsorCategory(this.label, this.key, this.icon);

  static SponsorCategory fromKey(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return etc;
  }
}

/// 광고가 노출되는 탭. [KnueNativeAdCard]가 생성될 때 넘기는 `placement`
/// 문자열과 1:1로 대응한다 (home_screen/meal_screen/bus_screen/settings).
enum SponsorPlacement {
  all('전체 탭', 'all'),
  home('홈', 'home'),
  meal('식단', 'meal'),
  bus('버스', 'bus'),
  settings('설정', 'settings');

  final String label;
  final String key;
  const SponsorPlacement(this.label, this.key);

  static SponsorPlacement fromKey(String? key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return all;
  }
}

/// 제휴/광고 한 건. Firestore `sponsors` 컬렉션 문서와 대응.
///
/// 필드는 [KnueNativeAdCard]가 읽는 스키마([tool/seed_sponsor.dart] 예시와
/// 동일)를 그대로 따른다 — 새 필드를 추가하려면 그 파일의 `_isAdValid`/
/// `build()`도 같이 봐야 한다.
class Sponsor {
  final String id;
  final String title;
  final String subtitle;
  final String callToAction;
  final SponsorCategory category;
  final String? imageUrl;
  final String? targetUrl;
  final SponsorPlacement placement;
  final int priority;
  final bool isActive;
  final DateTime? startDate;
  final DateTime? endDate;

  Sponsor({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.callToAction,
    required this.category,
    required this.imageUrl,
    required this.targetUrl,
    required this.placement,
    required this.priority,
    required this.isActive,
    required this.startDate,
    required this.endDate,
  });

  /// 지금 유효한지 — 기간·활성 여부만 본다. 실제 노출 여부는 배치(placement)와
  /// 우선순위까지 봐야 하므로 최종 판단은 [KnueNativeAdCard]가 한다. 관리
  /// 목록에서 "지금 노출 중" 배지를 다는 용도로만 쓴다.
  bool isCurrentlyValid(DateTime now) {
    if (!isActive) return false;
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'subtitle': subtitle,
    'callToAction': callToAction,
    'icon': category.key,
    'imageUrl': (imageUrl == null || imageUrl!.isEmpty) ? null : imageUrl,
    'targetUrl': (targetUrl == null || targetUrl!.isEmpty) ? null : targetUrl,
    'placement': placement.key,
    'priority': priority,
    'isActive': isActive,
    'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    // 종료일은 "그 날까지"가 자연스러운 기대라 자정이 아니라 하루가 끝나는
    // 시각으로 저장한다. Timestamp를 자정 그대로 저장하면 종료일 당일 새벽부터
    // 광고가 꺼져버린다 — KnueNativeAdCard._isAdValid는 문자열 날짜에는 이
    // 보정을 하지만 Timestamp에는 하지 않는다.
    'endDate': endDate != null
        ? Timestamp.fromDate(
            DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59),
          )
        : null,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static DateTime? _dateOf(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  factory Sponsor.fromFirestore(String id, Map<String, dynamic> data) =>
      Sponsor(
        id: id,
        title: data['title'] as String? ?? '',
        subtitle: data['subtitle'] as String? ?? '',
        callToAction: data['callToAction'] as String? ?? '자세히 보기',
        category: SponsorCategory.fromKey(data['icon'] as String?),
        imageUrl: data['imageUrl'] as String?,
        targetUrl: data['targetUrl'] as String?,
        placement: SponsorPlacement.fromKey(data['placement'] as String?),
        priority: (data['priority'] is num)
            ? (data['priority'] as num).toInt()
            : 0,
        isActive: data['isActive'] as bool? ?? true,
        startDate: _dateOf(data['startDate']),
        endDate: _dateOf(data['endDate']),
      );

  Sponsor copyWith({String? id, bool? isActive}) => Sponsor(
    id: id ?? this.id,
    title: title,
    subtitle: subtitle,
    callToAction: callToAction,
    category: category,
    imageUrl: imageUrl,
    targetUrl: targetUrl,
    placement: placement,
    priority: priority,
    isActive: isActive ?? this.isActive,
    startDate: startDate,
    endDate: endDate,
  );
}
