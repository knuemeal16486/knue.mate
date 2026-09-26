import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, Offset;
import 'package:shared_preferences/shared_preferences.dart';

import 'housing_iso.dart' show BaseBuilding, BuildingUse, kCampusAddress;
import 'housing_model.dart';
import 'offline_cache.dart';

/// 방 구조. "내 조건 찾기"에서 제일 먼저 거르는 조건이라 따로 둔다.
///
/// ⚠️ [key]는 Firestore에 그대로 저장되는 값이다. 바꾸면 이미 등록된 제보의
/// 방 구조가 전부 "모름"으로 떨어진다. 라벨만 고칠 것.
enum HousingRoomType {
  oneRoom('원룸', 'oneRoom'),
  onePointFive('1.5룸', 'onePointFive'),
  twoRoom('2룸', 'twoRoom'),
  threeRoomPlus('3룸 이상', 'threeRoomPlus');

  final String label;
  final String key;
  const HousingRoomType(this.label, this.key);

  /// 저장값 → 방 구조. 방 구조가 없던 시절 제보는 null(모름)이다.
  static HousingRoomType? fromKey(String? key) {
    if (key == null) return null;
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// 방 구조별(원룸, 1.5룸, 2룸) 시세 요약 정보
class HousingRoomPricing {
  final int deposit;
  final int monthlyRent;
  final int maintenanceFee;
  final int totalMonthly;
  final int reportCount;
  final bool isEstimated;
  final String sourceDescription;

  const HousingRoomPricing({
    required this.deposit,
    required this.monthlyRent,
    required this.maintenanceFee,
    required this.totalMonthly,
    required this.reportCount,
    required this.isEstimated,
    required this.sourceDescription,
  });
}

/// 한글 초성 검색 및 부분 문자열 일치 검사.
/// 사용자가 'ㄷㅅ' 또는 '다솜' 또는 '다솜빌'을 쳐도 실시간으로 매칭된다.
bool matchesKoreanHousingSearch(String target, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  final t = target.trim().toLowerCase();
  if (t.contains(q)) return true;

  const chosungList = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
  ];

  final sb = StringBuffer();
  for (int i = 0; i < t.length; i++) {
    final code = t.codeUnitAt(i);
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final chosungIdx = (code - 0xAC00) ~/ (21 * 28);
      sb.write(chosungList[chosungIdx]);
    } else {
      sb.write(t[i]);
    }
  }

  return sb.toString().contains(q);
}

/// 복수 전화번호(집주인/관리인 보통 2개)를 파싱 및 정규화
List<String> parseContactPhones(List<String?> inputs) {
  final result = <String>[];
  final seen = <String>{};

  for (final raw in inputs) {
    if (raw == null) continue;
    final parts = raw.split(RegExp(r'[,/\n;&]'));
    for (final part in parts) {
      final cleaned = part.trim();
      if (cleaned.isEmpty) continue;
      final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 7 && !seen.contains(digits)) {
        seen.add(digits);
        result.add(cleaned);
      }
    }
  }
  return result;
}

/// 자취방 시세 제보 한 건.
///
/// 학교 주변 원룸은 공개된 시세표가 없어서 학생들이 서로 물어보는 수밖에 없다.
/// 그 정보를 건물 단위로 모아 평균을 보여주는 게 이 기능의 목적이다.
class HousingReport {
  /// 어느 건물에 대한 제보인지 ([OneRoom.id]).
  final String buildingId;

  /// 보증금(만원).
  final int deposit;

  /// 월세(만원).
  final int monthlyRent;

  /// 관리비(만원). 모르면 null.
  final int? maintenanceFee;

  /// 추천 장점 — "도시가스", "방음 양호", "풀옵션" 등.
  final List<String> features;

  /// 솔직 주의점·단점 — "심야전기(난방비 주의)", "벽간 소음", "벌레" 등.
  final List<String> drawbacks;

  /// 외벽 현수막/관리인 임대 문의 연락처 (예: 010-XXXX-XXXX).
  final String? contactPhone;

  /// 이 건물의 원룸 이름([OneRoomName.id]). 건축물대장에는 원룸 이름이
  /// 없어서, 시세와 함께 학생에게 물어 채운다.
  final String? oneRoomId;

  /// 남긴 시점. 오래된 제보는 참고만 하도록 화면에 연도를 같이 보여준다.
  final DateTime reportedAt;

  /// Firestore 문서 id. 학생 제보 작성 시점엔 아직 없어 null이고,
  /// 관리자 화면이 개별 제보를 수정·삭제할 때만 필요해서 읽어올 때만 채운다.
  final String? id;

  /// 방 구조. 이 필드가 생기기 전 제보는 null(모름).
  final HousingRoomType? roomType;

  /// 한줄 거주 후기 / 장단점 (선택).
  final String? review;

  /// 관리비에 포함된 공과금 항목 (예: '수도', '인터넷', '전기', '도시가스').
  final List<String> includedUtilities;

  /// 학생 제보가 아니라 앱에 담아 둔 시세 조사([kHousingSurvey]) 값인지.
  /// 시세 평균에 섞이고, 화면엔 "시세 조사 N건"으로 따로 센다.
  /// Firestore에 쓰지 않는다.
  final bool survey;

  const HousingReport({
    required this.buildingId,
    required this.deposit,
    required this.monthlyRent,
    required this.features,
    this.drawbacks = const [],
    this.contactPhone,
    required this.reportedAt,
    this.maintenanceFee,
    this.oneRoomId,
    this.id,
    this.roomType,
    this.review,
    this.includedUtilities = const [],
    this.survey = false,
  });

  /// 관리비까지 포함한 월 부담액. 관리비를 안 적었으면 월세만.
  int get monthlyTotal => monthlyRent + (maintenanceFee ?? 0);

  Map<String, dynamic> toFirestore() => {
        'buildingId': buildingId,
        'deposit': deposit,
        'monthlyRent': monthlyRent,
        if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
        if (oneRoomId != null) 'oneRoomId': oneRoomId,
        if (roomType != null) 'roomType': roomType!.key,
        if (review != null && review!.trim().isNotEmpty) 'review': review!.trim(),
        if (contactPhone != null && contactPhone!.trim().isNotEmpty)
          'contactPhone': contactPhone!.trim(),
        if (drawbacks.isNotEmpty) 'drawbacks': drawbacks,
        if (includedUtilities.isNotEmpty) 'includedUtilities': includedUtilities,
        'features': features,
        'reportedAt': FieldValue.serverTimestamp(),
      };

  static HousingReport? fromMap(Map<String, dynamic> d, {String? id}) {
    final buildingId = d['buildingId'];
    final deposit = d['deposit'];
    final rent = d['monthlyRent'];
    if (buildingId is! String || deposit is! num || rent is! num) return null;
    final ts = d['reportedAt'];
    final rev = d['review'] as String?;
    final phone = d['contactPhone'] as String?;
    return HousingReport(
      id: id,
      buildingId: buildingId,
      deposit: deposit.toInt(),
      monthlyRent: rent.toInt(),
      maintenanceFee: (d['maintenanceFee'] as num?)?.toInt(),
      oneRoomId: d['oneRoomId'] as String?,
      roomType: HousingRoomType.fromKey(d['roomType'] as String?),
      features: (d['features'] as List?)?.whereType<String>().toList() ?? const [],
      drawbacks: (d['drawbacks'] as List?)?.whereType<String>().toList() ?? const [],
      contactPhone: (phone != null && phone.trim().isNotEmpty) ? phone.trim() : null,
      review: (rev != null && rev.trim().isNotEmpty) ? rev.trim() : null,
      includedUtilities: (d['includedUtilities'] as List?)?.whereType<String>().toList() ?? const [],
      reportedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

/// 상가 건물 안의 가게 하나.
@immutable
class HousingShop {
  final String name;

  /// 업종(카페·편의점·식당…). 비워도 된다.
  final String? category;

  /// 층(예: "1층", "지하"). 비워도 된다.
  final String? floor;

  const HousingShop({required this.name, this.category, this.floor});

  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
        if ((floor ?? '').trim().isNotEmpty) 'floor': floor!.trim(),
      };

  /// Firestore 배열 → 목록. 이름 없는 항목은 버린다. 순수 함수 — 테스트 대상.
  static List<HousingShop> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final m in raw)
        if (m is Map && m['name'] is String && (m['name'] as String).trim().isNotEmpty)
          HousingShop(
            name: (m['name'] as String).trim(),
            category: m['category'] as String?,
            floor: m['floor'] as String?,
          ),
    ];
  }

  /// 목록에 띄울 한 줄 설명: "1층 · 카페".
  String get detail => [
        if ((floor ?? '').trim().isNotEmpty) floor!.trim(),
        if ((category ?? '').trim().isNotEmpty) category!.trim(),
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is HousingShop && other.name == name && other.category == category && other.floor == floor;

  @override
  int get hashCode => Object.hash(name, category, floor);
}

/// 개발자가 직접 적어 넣은 시세 한 건. 금액은 만원 단위.
@immutable
class HousingPriceEntry {
  final int deposit;
  final int monthlyRent;
  final int? maintenanceFee;

  /// 원룸·1.5룸·투룸 등. 비워도 된다.
  final String? roomType;

  /// 언제 기준인지(예: "2026-09"). 비워도 된다.
  final String? asOf;
  final String? note;

  const HousingPriceEntry({
    required this.deposit,
    required this.monthlyRent,
    this.maintenanceFee,
    this.roomType,
    this.asOf,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'deposit': deposit,
        'monthlyRent': monthlyRent,
        if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
        if ((roomType ?? '').trim().isNotEmpty) 'roomType': roomType!.trim(),
        if ((asOf ?? '').trim().isNotEmpty) 'asOf': asOf!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      };

  /// Firestore 배열 → 목록. 금액이 없는 항목은 버린다. 순수 함수 — 테스트 대상.
  static List<HousingPriceEntry> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final m in raw)
        if (m is Map && m['deposit'] is num && m['monthlyRent'] is num)
          HousingPriceEntry(
            deposit: (m['deposit'] as num).toInt(),
            monthlyRent: (m['monthlyRent'] as num).toInt(),
            maintenanceFee: (m['maintenanceFee'] as num?)?.toInt(),
            roomType: m['roomType'] as String?,
            asOf: m['asOf'] as String?,
            note: m['note'] as String?,
          ),
    ];
  }

  /// "보증금 300 / 월세 35 (관리비 5)".
  String get priceText =>
      '보증금 $deposit / 월세 $monthlyRent${maintenanceFee != null ? ' (관리비 $maintenanceFee)' : ''}';

  /// "원룸 · 2026-09 · 메모".
  String get detail => [
        if ((roomType ?? '').trim().isNotEmpty) roomType!.trim(),
        if ((asOf ?? '').trim().isNotEmpty) asOf!.trim(),
        if ((note ?? '').trim().isNotEmpty) note!.trim(),
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is HousingPriceEntry &&
      other.deposit == deposit &&
      other.monthlyRent == monthlyRent &&
      other.maintenanceFee == maintenanceFee &&
      other.roomType == roomType &&
      other.asOf == asOf &&
      other.note == note;

  @override
  int get hashCode => Object.hash(deposit, monthlyRent, maintenanceFee, roomType, asOf, note);
}

/// 직접 입력한 시세를 최근 것부터. 기준 시기("2026-09")가 적힌 건 그 순서로,
/// 안 적힌 건 입력한 순서대로 뒤에 둔다. 순수 함수 — 테스트 대상.
List<HousingPriceEntry> sortedPriceEntries(List<HousingPriceEntry> prices) {
  final dated = [for (final p in prices) if ((p.asOf ?? '').trim().isNotEmpty) p]
    ..sort((a, b) => b.asOf!.trim().compareTo(a.asOf!.trim()));
  final undated = [for (final p in prices) if ((p.asOf ?? '').trim().isEmpty) p];
  return [...dated, ...undated];
}

/// 가게 이름으로 건물 찾기. (건물 id, 가게) 쌍을 돌려준다. 순수 함수 — 테스트 대상.
List<(String, HousingShop)> findShops(
  Map<String, HousingBuildingOverride> overrides,
  String query,
  bool Function(String text, String query) matches,
) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return [
    for (final e in overrides.entries)
      if (e.value.isDeleted != true)
        for (final shop in e.value.shops)
          if (matches(shop.name, q) || (shop.category != null && matches(shop.category!, q))) (e.key, shop),
  ];
}

/// 건물 하나에 대한 관리자 수정 정보. 학생 제보 다수결로 정해지는 이름·구역을
/// 개발자가 직접 바로잡고 싶을 때 이 건물 id로 덮어쓴다([HousingService.fetchOverrides]가
/// 있으면 항상 이 값이 이긴다).
class HousingBuildingOverride {
  final String buildingId;
  final String name;
  final HousingZone zone;
  final int? builtYear;
  final String? note;

  /// 도로명주소. VWorld 대장 값이 틀렸거나(신축·분할) 비어 있을 때 덮어쓴다.
  /// 비워두면 대장 값을 그대로 쓴다.
  final String? address;

  /// 집주인·관리인 연락처. **공개 화면에는 띄우지 않는다** — 개인정보이고,
  /// 동의 없이 앱에 뿌리면 곤란해진다. 관리자 화면에서만 보인다.
  final String? landlordName;
  final String? landlordPhone;
  final String? landlordPhone2;

  /// 파싱된 집주인 및 관리인 연락처 목록 (최대 2개 이상)
  List<String> get allLandlordPhones =>
      parseContactPhones([landlordPhone, landlordPhone2]);

  /// 관리자가 아는 실제 층수·세대수. 대장 값이 틀린 건물이 있다.
  /// 화면에 "지상 n층"으로 **보여주는** 값이다.
  final int? floors;

  /// 지도에 그릴 높이(층 단위). 층고가 높은 건물은 실제 층수대로 그리면
  /// 낮아 보여서(종합교육관: 7층인데 11층만큼 높다) 표시 층수와 따로 둔다.
  /// 비우면 [floors]로 그린다.
  final int? mapFloors;
  final int? unitCount;

  /// 개발자/관리자가 직접 지정한 건물 고유 색상 (16진수 HEX 예: "#4CAF50")
  final String? customColorHex;

  /// 개발자가 직접 추가하거나 수정한 건물 외곽선 (정점 목록)
  final List<Offset>? customRing;

  /// 건물이 삭제(숨김)되었는지 여부
  final bool? isDeleted;

  /// 다른 건물과 합쳐져서 병합된 경우, 대표 건물 ID
  final String? mergedWith;

  /// 지도에서 이 건물의 이름표를 숨길지. 이름표가 몰려 겹치는 곳을 정리할 때
  /// 개발자가 [이름표] 도구로 끈다. 이름·색은 그대로 둔다.
  final bool? hideLabel;

  /// 벽에 창문을 낼지. null이면 기본(자취방 건물만 창문).
  final bool? showWindows;

  /// 상가 건물에 든 가게들. 건물을 누르면 목록이 뜨고, 가게 이름으로 검색하면
  /// 이 건물로 지도가 옮겨 간다.
  final List<HousingShop> shops;

  /// 개발자가 직접 적어 넣은 시세. 학생 제보(다수결 평균)와 따로 모두 보여준다.
  final List<HousingPriceEntry> prices;

  /// 이름을 정해 둔 수정인지. 건물 모양만 고친 문서는 이름이 비어 있고,
  /// 이때는 이름·구역 색을 덮어쓰지 않는다 — 모양을 고쳤다고 건물이 갑자기
  /// 원룸 구역 색으로 칠해지거나 이름표가 붙으면 안 된다.
  bool get isNamed => name.trim().isNotEmpty;

  /// customColorHex에 이 값을 넣으면 "시스템" 색이다. 고정 색을 칠하지 않고
  /// 밝은/다크 모드마다 바뀌는 기본 건물 색을 따른다.
  static const String systemColor = 'system';

  /// "시스템" 색으로 정해 둔 건물인지. 구역 색·도로 색도 칠하지 않는다.
  bool get usesSystemColor =>
      customColorHex?.trim().toLowerCase() == systemColor;

  Color? get customColor {
    if (customColorHex == null || customColorHex!.trim().isEmpty) return null;
    if (usesSystemColor) return null;
    try {
      final hex = customColorHex!.trim().replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      } else if (hex.length == 8) {
        return Color(int.parse('0x$hex'));
      }
    } catch (_) {}
    return null;
  }

  const HousingBuildingOverride({
    required this.buildingId,
    required this.name,
    required this.zone,
    this.builtYear,
    this.note,
    this.address,
    this.landlordName,
    this.landlordPhone,
    this.landlordPhone2,
    this.floors,
    this.mapFloors,
    this.unitCount,
    this.customColorHex,
    this.customRing,
    this.isDeleted,
    this.mergedWith,
    this.hideLabel,
    this.showWindows,
    this.shops = const [],
    this.prices = const [],
  });

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'zone': zone.name,
        if (builtYear != null) 'builtYear': builtYear,
        if (_clean(note) != null) 'note': _clean(note),
        if (_clean(address) != null) 'address': _clean(address),
        if (_clean(landlordName) != null) 'landlordName': _clean(landlordName),
        if (_clean(landlordPhone) != null)
          'landlordPhone': _clean(landlordPhone),
        if (_clean(landlordPhone2) != null)
          'landlordPhone2': _clean(landlordPhone2),
        if (floors != null) 'floors': floors,
        if (mapFloors != null) 'mapFloors': mapFloors,
        if (unitCount != null) 'unitCount': unitCount,
        if (_clean(customColorHex) != null)
          'customColorHex': _clean(customColorHex),
        if (customRing != null)
          'customRing': encodeRing(customRing!),
        if (isDeleted != null) 'isDeleted': isDeleted,
        if (_clean(mergedWith) != null) 'mergedWith': _clean(mergedWith),
        if (hideLabel == true) 'hideLabel': true,
        if (showWindows != null) 'showWindows': showWindows,
        if (shops.isNotEmpty) 'shops': [for (final x in shops) x.toMap()],
        if (prices.isNotEmpty) 'prices': [for (final x in prices) x.toMap()],
      };

  static HousingBuildingOverride? fromMap(String buildingId, Map<String, dynamic> d) {
    // 이름이 비어 있어도 모양을 담았으면 모양만 고친 문서다([isNamed]).
    final name = d['name'] is String ? d['name'] as String : '';
    HousingZone? zone;
    for (final z in HousingZone.values) {
      if (z.name == d['zone']) {
        zone = z;
        break;
      }
    }
    if (zone == null) return null;

    final decoded = decodeRing(d['customRing']);
    final ring = decoded.isEmpty ? null : decoded;
    // 이름도 모양도 색도 없고 삭제·병합 표시도 아니면 쓸 게 없는 깨진 문서다.
    final color = d['customColorHex'];
    final hasColor = color is String && color.trim().isNotEmpty;
    final merged = d['mergedWith'];
    final hidden = d['isDeleted'] == true ||
        (merged is String && merged.isNotEmpty) ||
        d['hideLabel'] == true;
    final shops = HousingShop.listFrom(d['shops']);
    final prices = HousingPriceEntry.listFrom(d['prices']);
    final hasFloors = d['floors'] is num || d['mapFloors'] is num || d['showWindows'] is bool;
    if (name.trim().isEmpty &&
        ring == null &&
        !hasColor &&
        !hidden &&
        !hasFloors &&
        shops.isEmpty &&
        prices.isEmpty) {
      return null;
    }

    return HousingBuildingOverride(
      buildingId: buildingId,
      name: name,
      zone: zone,
      builtYear: (d['builtYear'] as num?)?.toInt(),
      note: d['note'] as String?,
      address: d['address'] as String?,
      landlordName: d['landlordName'] as String?,
      landlordPhone: d['landlordPhone'] as String?,
      landlordPhone2: d['landlordPhone2'] as String?,
      floors: (d['floors'] as num?)?.toInt(),
      mapFloors: (d['mapFloors'] as num?)?.toInt(),
      unitCount: (d['unitCount'] as num?)?.toInt(),
      customColorHex: d['customColorHex'] as String?,
      customRing: ring,
      isDeleted: d['isDeleted'] as bool?,
      mergedWith: d['mergedWith'] as String?,
      hideLabel: d['hideLabel'] as bool?,
      showWindows: d['showWindows'] as bool?,
      shops: shops,
      prices: prices,
    );
  }

  HousingBuildingOverride copyWith({
    String? name,
    HousingZone? zone,
    int? builtYear,
    String? note,
    String? address,
    String? landlordName,
    String? landlordPhone,
    String? landlordPhone2,
    int? floors,
    int? mapFloors,
    int? unitCount,
    String? customColorHex,
    List<Offset>? customRing,
    bool? isDeleted,
    String? mergedWith,
    bool? hideLabel,
    bool? showWindows,
    List<HousingShop>? shops,
    List<HousingPriceEntry>? prices,
  }) =>
      HousingBuildingOverride(
        buildingId: buildingId,
        name: name ?? this.name,
        zone: zone ?? this.zone,
        builtYear: builtYear ?? this.builtYear,
        note: note ?? this.note,
        address: address ?? this.address,
        landlordName: landlordName ?? this.landlordName,
        landlordPhone: landlordPhone ?? this.landlordPhone,
        landlordPhone2: landlordPhone2 ?? this.landlordPhone2,
        floors: floors ?? this.floors,
        mapFloors: mapFloors ?? this.mapFloors,
        unitCount: unitCount ?? this.unitCount,
        customColorHex: customColorHex ?? this.customColorHex,
        customRing: customRing ?? this.customRing,
        isDeleted: isDeleted ?? this.isDeleted,
        mergedWith: mergedWith ?? this.mergedWith,
        hideLabel: hideLabel ?? this.hideLabel,
        showWindows: showWindows ?? this.showWindows,
        shops: shops ?? this.shops,
        prices: prices ?? this.prices,
      );

  /// 화면 표시용으로 [OneRoomName]과 같은 모양으로 바꾼다 — 지도·검색이
  /// 제보 다수결로 정해진 이름과 덮어쓴 이름을 구분 없이 다룰 수 있게.
  OneRoomName toOneRoomName() => OneRoomName(
        id: 'override:$buildingId',
        name: name,
        zone: zone,
        // 연도를 따로 적지 않았으면 이름으로 원룸 사전에서 찾는다. 예전엔
        // 이름만 고쳐도 사전의 연도가 가려져 "준공연도"가 비어 보였다.
        builtYear: builtYear ?? builtYearByName(name),
        note: note,
      );
}

/// 원룸으로 볼 만한 건물인지 판단한다(교내 건물 제외, 3층 이상·50㎡ 이상,
/// 또는 이미 제보가 달려 있으면 조건과 무관하게 포함).
/// [HousingScreen]의 지도와 관리자 화면의 건물 목록이 같은 기준을 써야
/// 관리자가 고친 건물이 지도에도 그대로 나타난다.
bool looksLikeOneRoom(
  BaseBuilding b,
  Map<String, HousingSummary> summaries, {
  int minFloors = 3,
  double minArea = 50.0,
}) =>
    !b.isCampus &&
    (summaries.containsKey(b.id) ||
        (b.floors >= minFloors && b.footprintArea >= minArea));

/// 자취방 추천 장점 프리셋
/// 예전 제보 폼이 쓰던 긴 장점 문구 → [kHousingFeatures]의 짧은 이름.
///
/// 한동안 제보 폼이 "도시가스 난방"·"풀옵션(전자레인지 등)" 같은 긴 문구를
/// 저장했는데 "내 조건 찾기"는 "도시가스"·"풀옵션"과 비교해서, 그 제보의
/// 장점은 조건 찾기에 **절대 안 걸렸다**. 집계할 때 짧은 이름으로 맞춘다.
const Map<String, String> _kLegacyFeatureAliases = {
  '도시가스 난방': '도시가스',
  '정문 도보 3분컷': '학교와 가까움',
  '방음 우수(콘크리트벽)': '방음 양호',
  '채광/남향': '햇빛 잘 듦',
  '수압 강함/온수 양호': '수압 좋음',
  '1.5룸/넓은 분리형': '분리형',
  '풀옵션(전자레인지 등)': '풀옵션',
  '엘리베이터 있음': '엘리베이터',
  '주차 공간 넉넉': '주차 가능',
};

/// 장점 문구를 조건 찾기와 같은 이름으로. 순수 함수 — 테스트 대상.
String canonicalFeature(String f) => _kLegacyFeatureAliases[f.trim()] ?? f.trim();

/// 자취방 솔직 주의점 프리셋 (교원대 실제 자취 환경 반영)
const List<String> kHousingCons = [
  '심야전기/LPG (겨울 난방비 폭탄 주의)',
  '벽간/층간 소음 있음 (방음 취약)',
  '수압 약함 / 온수 불안정',
  '1층/저층 벌레·습기 주의',
  '언덕길 / 도보 10분 이상',
  '골목 어두움 / 외진 위치',
  '주차 공간 협소 / 주차 불가',
  '세탁실 공용 / 베란다 없음',
  '옵션 노후 (냉장고·에어컨)',
  '외풍 있음 / 겨울철 추움',
];

/// 제보 금액 칸 검사(만원). 시세를 평균으로 내므로 오타 하나(300 → 3000,
/// 원 단위로 300000)가 건물 전체 시세를 끌고 간다 — 그런 값은 받지 않는다.
/// 넉넉히 잡은 상한이라 실제 월세·반전세는 다 들어온다.
String? housingAmountError(String? v, {required int max, bool required = true}) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return required ? '입력' : null;
  final n = int.tryParse(t);
  if (n == null || n < 0) return '숫자만';
  if (n > max) return '만원 단위로';
  return null;
}

/// 제보 금액 상한(만원).
const kMaxReportDeposit = 5000;
const kMaxReportRent = 200;
const kMaxReportFee = 50;

/// 같은 기기에서 같은 제보를 두 번 보냈는지 가리는 열쇠.
String housingReportSignature(HousingReport r) =>
    '${r.roomType?.key ?? '-'}|${r.deposit}|${r.monthlyRent}|${r.maintenanceFee ?? '-'}';

/// 평균(만원, 반올림). 비어 있으면 null.
int? housingAverage(List<int> values) =>
    values.isEmpty ? null : (values.reduce((a, b) => a + b) / values.length).round();

/// "제보 2건 · 시세 조사 3건" — [total]건 중 [survey]건이 시세 조사 값일 때.
String housingSourceLabel(int total, int survey) => [
      if (total - survey > 0) '제보 ${total - survey}건',
      if (survey > 0) '시세 조사 $survey건',
    ].join(' · ');

/// 한 건물의 제보를 모은 결과.
class HousingSummary {
  final int reportCount;

  /// 보증금·월세 평균(만원, 반올림). 제보가 없으면 null.
  ///
  /// 같은 건물도 방 위치마다 시세가 조금씩 달라서, 제보를 하나도 버리지 않고
  /// 평균을 낸다. 제보 하나하나는 [reports]로 볼 수 있다.
  final int? avgDeposit;
  final int? avgRent;

  /// 많이 언급된 특징(장점) 순. **상위 5개만** — 화면 표시용이다.
  final List<String> topFeatures;

  /// 한 번이라도 언급된 특징 전부. 필터는 이걸 봐야 한다 —
  /// [topFeatures]로 거르면 6번째로 밀린 특징은 조건에 영영 안 걸린다.
  final Set<String> allFeatures;

  /// 많이 언급된 솔직 주의점/단점 순. **상위 5개만**.
  final List<String> topDrawbacks;

  /// 한 번이라도 언급된 솔직 주의점 전부.
  final Set<String> allDrawbacks;

  /// 외벽 현수막/관리인 임대 문의 연락처 (최신 유효 제보).
  final String? publicContactPhone;

  /// 외벽 현수막/관리인/집주인 복수 연락처 (보통 최대 2개)
  final List<String> publicContactPhones;

  /// 가장 최근 제보 시점.
  final DateTime? latestReport;

  /// 가장 많이 지목된 원룸 이름([OneRoomName.id]).
  /// 건축물대장에 원룸 이름이 없어 학생 제보로만 채워진다.
  final String? oneRoomId;

  /// 관리비 평균(만원). 관리비를 적은 제보만. 아무도 안 적었으면 null.
  final int? avgMaintenance;

  /// 관리비까지 포함한 월 부담액 평균(만원). 제보가 없으면 null.
  final int? avgMonthlyTotal;

  /// 이 건물에서 제보된 방 구조들.
  final Set<HousingRoomType> roomTypes;

  /// 이 건물에 남겨진 최근 거주 후기 (최대 10건, 최신순).
  final List<String> recentReviews;

  /// 이 건물 제보들에서 언급된 포함 관리비 항목 (예: 수도, 인터넷 등).
  final Set<String> commonUtilities;

  /// 방 구조별(원룸, 1.5룸, 2룸) 집계 시세
  final Map<HousingRoomType, HousingRoomPricing> roomPricingMap;

  /// [reportCount] 중 시세 조사 값의 수. 나머지가 학생 제보다.
  final int surveyCount;

  /// 금액이 있는 제보 전부(최신순). 겹치는 값도 버리지 않는다 — 평균이
  /// 어디서 나왔는지 화면에서 하나하나 보여준다.
  final List<HousingReport> reports;

  const HousingSummary({
    required this.reportCount,
    this.surveyCount = 0,
    this.reports = const [],
    required this.avgDeposit,
    required this.avgRent,
    required this.topFeatures,
    required this.latestReport,
    this.oneRoomId,
    this.avgMaintenance,
    this.avgMonthlyTotal,
    this.roomTypes = const {},
    this.allFeatures = const {},
    this.topDrawbacks = const [],
    this.allDrawbacks = const {},
    this.publicContactPhone,
    this.publicContactPhones = const [],
    this.recentReviews = const [],
    this.commonUtilities = const {},
    this.roomPricingMap = const {},
  });

  static const empty = HousingSummary(
    reportCount: 0,
    avgDeposit: null,
    avgRent: null,
    topFeatures: [],
    latestReport: null,
    topDrawbacks: [],
    allDrawbacks: {},
    publicContactPhone: null,
    publicContactPhones: [],
    recentReviews: [],
    commonUtilities: {},
    roomPricingMap: {},
  );

  bool get hasData => reportCount > 0;

  /// "제보 2건 · 시세 조사 3건"처럼 출처를 나눠 센 글자.
  String get sourceLabel => housingSourceLabel(reportCount, surveyCount);

  /// 제보가 적으면 화면에서 "참고용"이라고 알려주기 위한 기준.
  bool get isThin => reportCount < 3;

  /// 방 구조(원룸·1.5룸·2룸)별 시세. **제보가 있을 때만** 준다.
  ///
  /// 예전엔 제보가 없으면 "교원대 원룸 표준 가이드"라며 보증금 200 / 월세 34
  /// 같은 지어낸 값을, 원룸 제보만 있으면 1.5룸·2룸을 "+100/+7"식으로 만들어
  /// 보여줬다. 확인되지 않은 숫자는 띄우지 않는다.
  HousingRoomPricing? getPricing(HousingRoomType type, {HousingZone? zone}) {
    final byType = roomPricingMap[type];
    if (byType != null) return byType;
    // 방 구조를 안 적은 제보만 있으면 건물 전체 평균을 원룸 시세로 쓴다
    // (실제 제보 값이다).
    if (type == HousingRoomType.oneRoom &&
        roomPricingMap.isEmpty &&
        hasData &&
        avgDeposit != null &&
        avgRent != null) {
      final fee = avgMaintenance ?? 0;
      return HousingRoomPricing(
        deposit: avgDeposit!,
        monthlyRent: avgRent!,
        maintenanceFee: fee,
        totalMonthly: avgRent! + fee,
        reportCount: reportCount,
        isEstimated: false,
        sourceDescription: '$sourceLabel 기준',
      );
    }
    return null;
  }

  factory HousingSummary.from(Iterable<HousingReport> reports) {
    final list = reports.toList();
    if (list.isEmpty) return empty;

    // 방마다 층·향·크기가 달라 값이 갈리는 게 정상이라, 겹치는 제보도 전부
    // 두고 평균을 낸다.
    int? avg(List<int> values) => housingAverage(values);

    // 장점 집계
    final featureCount = <String, int>{};
    for (final r in list) {
      // 한 제보 안에서 옛 문구·새 문구가 같은 뜻으로 겹쳐도 한 번만 센다.
      for (final f in {for (final x in r.features) canonicalFeature(x)}) {
        featureCount[f] = (featureCount[f] ?? 0) + 1;
      }
    }
    final sortedFeatures = featureCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 단점/주의점 집계
    final drawbackCount = <String, int>{};
    for (final r in list) {
      for (final d in r.drawbacks) {
        drawbackCount[d] = (drawbackCount[d] ?? 0) + 1;
      }
    }
    final sortedDrawbacks = drawbackCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 최근 작성된 거주 후기들을 최신순으로 정렬해 수집 (최대 10개)
    final reviewsWithDate = list
        .where((r) => r.review != null && r.review!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final recentReviews =
        reviewsWithDate.map((r) => r.review!.trim()).take(10).toList();

    // 임대 문의처 전화번호 최신순 추출 및 복수(보통 2개) 파싱
    final phonesWithDate = list
        .where((r) => r.contactPhone != null && r.contactPhone!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final publicContactPhone =
        phonesWithDate.isNotEmpty ? phonesWithDate.first.contactPhone : null;
    final publicContactPhones =
        parseContactPhones(phonesWithDate.map((r) => r.contactPhone).toList())
            .take(2)
            .toList();

    // 포함 관리비 항목 집계
    final utilities = <String>{};
    for (final r in list) {
      utilities.addAll(r.includedUtilities);
    }

    // 이름 다수결
    final nameCount = <String, int>{};
    for (final r in list) {
      final id = r.oneRoomId;
      if (id != null) nameCount[id] = (nameCount[id] ?? 0) + 1;
    }
    final topName = nameCount.entries.isEmpty
        ? null
        : (nameCount.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    // 시세 계산 시 유효한(0보다 큰) 금액만 필터링하여 전화번호 단독 제보로 인한 왜곡 방지
    final validDeposits = list.map((r) => r.deposit).where((v) => v > 0).toList();
    final validRents = list.map((r) => r.monthlyRent).where((v) => v > 0).toList();
    final validTotals = list.map((r) => r.monthlyTotal).where((v) => v > 0).toList();

    final fees = list
        .map((r) => r.maintenanceFee)
        .whereType<int>()
        .where((v) => v > 0)
        .toList();

    // 방 구조별(원룸, 1.5룸, 2룸) 개별 제보 집계
    final pricingMap = <HousingRoomType, HousingRoomPricing>{};
    for (final type in [
      HousingRoomType.oneRoom,
      HousingRoomType.onePointFive,
      HousingRoomType.twoRoom,
    ]) {
      final sub = list.where((r) => r.roomType == type).toList();
      if (sub.isNotEmpty) {
        final sDeps = sub.map((r) => r.deposit).where((v) => v > 0).toList();
        final sRents = sub.map((r) => r.monthlyRent).where((v) => v > 0).toList();
        final sFees = sub.map((r) => r.maintenanceFee).whereType<int>().where((v) => v > 0).toList();
        final dep = avg(sDeps.isNotEmpty ? sDeps : sub.map((r) => r.deposit).toList()) ?? 200;
        final rent = avg(sRents.isNotEmpty ? sRents : sub.map((r) => r.monthlyRent).toList()) ?? 35;
        // 관리비를 아무도 안 적었으면 0(모름) — 예전엔 3만원을 지어 넣었다.
        final fee = avg(sFees) ?? 0;
        pricingMap[type] = HousingRoomPricing(
          deposit: dep,
          monthlyRent: rent,
          maintenanceFee: fee,
          totalMonthly: rent + fee,
          reportCount: sub.length,
          isEstimated: false,
          sourceDescription: '${housingSourceLabel(sub.length, sub.where((r) => r.survey).length)} 기준',
        );
      }
    }

    return HousingSummary(
      reportCount: list.length,
      surveyCount: list.where((r) => r.survey).length,
      reports: [
        for (final r in list)
          if (r.deposit > 0 || r.monthlyRent > 0) r,
      ]..sort((a, b) => b.reportedAt.compareTo(a.reportedAt)),
      avgDeposit: avg(validDeposits.isNotEmpty ? validDeposits : list.map((r) => r.deposit).toList()),
      avgRent: avg(validRents.isNotEmpty ? validRents : list.map((r) => r.monthlyRent).toList()),
      avgMaintenance: avg(fees),
      avgMonthlyTotal: avg(validTotals.isNotEmpty ? validTotals : list.map((r) => r.monthlyTotal).toList()),
      roomTypes: list.map((r) => r.roomType).whereType<HousingRoomType>().toSet(),
      topFeatures: sortedFeatures.take(5).map((e) => e.key).toList(),
      allFeatures: featureCount.keys.toSet(),
      topDrawbacks: sortedDrawbacks.take(5).map((e) => e.key).toList(),
      allDrawbacks: drawbackCount.keys.toSet(),
      publicContactPhone: publicContactPhone,
      publicContactPhones: publicContactPhones,
      recentReviews: recentReviews,
      commonUtilities: utilities,
      roomPricingMap: pricingMap,
      latestReport: list
          .map((r) => r.reportedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      oneRoomId: topName,
    );
  }
}

/// 자취방 제보 저장·조회.
class HousingService {
  static const String _collection = 'housing_reports';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 건물별 제보 요약. 한 번에 전부 받아 건물 id로 묶는다 —
  /// 건물마다 따로 조회하면 90번을 왕복하게 된다.
  static Future<Map<String, HousingSummary>> fetchSummaries() async {
    final byBuilding = await fetchReportsByBuilding();
    return byBuilding?.map((id, reports) => MapEntry(id, HousingSummary.from(reports))) ?? const {};
  }

  /// 건물 id별 학생 제보 원본. 받아오지 못하면 null(제보 0건과 구별한다).
  /// 화면은 이걸 시세 조사([kHousingSurvey])와 섞어 요약한다.
  static Future<Map<String, List<HousingReport>>?> fetchReportsByBuilding() async {
    if (!FirestoreHealth.isAvailable) return null;
    try {
      final snap =
          await _db.collection(_collection).get().timeout(const Duration(seconds: 5));
      FirestoreHealth.reportSuccess();

      final byBuilding = <String, List<HousingReport>>{};
      for (final doc in snap.docs) {
        final r = HousingReport.fromMap(doc.data());
        if (r == null) continue;
        byBuilding.putIfAbsent(r.buildingId, () => []).add(r);
      }
      return byBuilding;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchReportsByBuilding error: $e');
      return null;
    }
  }

  /// 제보 남기기. 같은 건물이라도 방마다 시세가 달라서 몇 번이든 받는다
  /// (다른 방·다른 사람의 제보가 겹쳐도 전부 기록한다). 이 기기에서 **똑같은
  /// 내용**(구조·보증금·월세·관리비)을 또 보낼 때만 막는다 — 두 번 눌러
  /// 평균이 쏠리는 걸 막으려는 것이다.
  static Future<HousingSubmitResult> submit(HousingReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'housing_reported_sigs_${report.buildingId}';
    final sent = prefs.getStringList(key) ?? const <String>[];
    final sig = housingReportSignature(report);
    if (sent.contains(sig)) {
      return HousingSubmitResult.alreadyReported;
    }
    try {
      await _db
          .collection(_collection)
          .add(report.toFirestore())
          .timeout(const Duration(seconds: 6));
      await prefs.setStringList(key, [...sent, sig]);
      FirestoreHealth.reportSuccess();
      return HousingSubmitResult.ok;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.submit error: $e');
      return HousingSubmitResult.failed;
    }
  }

  /// 외벽 현수막/관리인 임대 문의 연락처만 빠르게 제보 (보통 집주인/관리인 2개까지)
  static Future<bool> submitContactPhone({
    required String buildingId,
    required String phone,
    String? phone2,
    String? oneRoomId,
  }) async {
    try {
      final p1 = phone.trim();
      final p2 = phone2?.trim();
      final combined = (p2 != null && p2.isNotEmpty) ? '$p1, $p2' : p1;
      final report = HousingReport(
        buildingId: buildingId,
        deposit: 0,
        monthlyRent: 0,
        contactPhone: combined,
        oneRoomId: oneRoomId,
        features: const [],
        drawbacks: const [],
        reportedAt: DateTime.now(),
      );
      await _db
          .collection(_collection)
          .add(report.toFirestore())
          .timeout(const Duration(seconds: 6));
      FirestoreHealth.reportSuccess();
      return true;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.submitContactPhone error: $e');
      return false;
    }
  }

  /// 이 기기에서 이미 제보한 건물인지.
  /// 이 기기에서 이 건물에 제보한 적이 있는지. 막는 데 쓰지 않고, 버튼을
  /// "다른 방 시세 알려주기"로 바꾸는 데만 쓴다.
  static Future<bool> hasReported(String buildingId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('housing_reported_$buildingId') ?? false) ||
        (prefs.getStringList('housing_reported_sigs_$buildingId')?.isNotEmpty ?? false);
  }

  // ── 관리자 전용 ──────────────────────────────────────────────

  /// 문서 id를 포함한 제보 전체 목록. 관리 화면에서 개별 수정·삭제하려면
  /// [fetchSummaries]처럼 뭉개서 집계한 값이 아니라 원본 문서가 필요하다.
  static Future<List<HousingReport>> fetchAllReportsRaw() async {
    final snap = await _db
        .collection(_collection)
        .orderBy('reportedAt', descending: true)
        .get()
        .timeout(const Duration(seconds: 8));
    return snap.docs
        .map((d) => HousingReport.fromMap(d.data(), id: d.id))
        .whereType<HousingReport>()
        .toList();
  }

  /// 제보 수정. 원문 그대로 덮어쓰면 reportedAt이 갱신 시각으로 밀리므로,
  /// 여기서는 바뀔 수 있는 필드만 골라 update한다.
  ///
  /// ⚠️ set()으로 바꾸지 말 것 — 여기 안 적힌 roomType 같은 필드가 통째로
  /// 날아간다(관리자가 금액만 고쳐도 방 구조가 사라져 필터에서 빠진다).
  static Future<void> updateReport({
    required String id,
    required int deposit,
    required int monthlyRent,
    int? maintenanceFee,
    required List<String> features,
    String? oneRoomId,
  }) async {
    await _db.collection(_collection).doc(id).update({
      'deposit': deposit,
      'monthlyRent': monthlyRent,
      'maintenanceFee': maintenanceFee,
      'oneRoomId': oneRoomId,
      'features': features,
    });
  }

  static Future<void> deleteReport(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }

  static const String _overrideCollection = 'housing_building_overrides';

  /// 관리자가 바로잡은 건물 정보. 건물 id로 색인해 지도가 바로 찾아 쓴다.
  static Future<Map<String, HousingBuildingOverride>> fetchOverrides() async {
    if (!FirestoreHealth.isAvailable) return const {};
    try {
      final snap = await _db
          .collection(_overrideCollection)
          .get()
          .timeout(const Duration(seconds: 5));
      FirestoreHealth.reportSuccess();
      return _overridesFrom(snap.docs);
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchOverrides error: $e');
      return const {};
    }
  }

  static Map<String, HousingBuildingOverride> _overridesFrom(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final result = <String, HousingBuildingOverride>{};
    for (final doc in docs) {
      final o = HousingBuildingOverride.fromMap(doc.id, doc.data());
      if (o != null) result[doc.id] = o;
    }
    return result;
  }

  /// 관리자 수정을 실시간으로 받는다. 누가 어느 기기에서 고치든 열려 있는
  /// 지도에 바로 반영된다. 내가 쓴 값은 서버 응답을 기다리지 않고 곧장 온다.
  ///
  /// [fetchOverrides]와 달리 [FirestoreHealth]를 보지 않는다. 한 번 받아오고
  /// 끝나는 방식은 앱 어딘가에서 요청이 한 번 실패하면 5분 동안 건너뛰어,
  /// 저장된 수정이 화면에 안 나와 "저장이 안 됐다"처럼 보였다. 리스너는
  /// 연결이 돌아오면 알아서 다시 받는다.
  static Stream<Map<String, HousingBuildingOverride>> watchOverrides() => _db
      .collection(_overrideCollection)
      .snapshots()
      .map((snap) => _overridesFrom(snap.docs));

  /// 관리자 쓰기를 기다리는 한도. Firestore는 하루 쓰기 한도에 걸린 쓰기를
  /// "잠시 뒤 다시"로 보고 끝없이 붙잡고 있어서, 기다리기만 하면 저장 창이
  /// 안 닫히고 삭제가 멈춘 채로 아무 안내도 없었다.
  static const Duration adminWriteTimeout = Duration(seconds: 10);

  static Future<void> setOverride(HousingBuildingOverride override) async {
    await _db
        .collection(_overrideCollection)
        .doc(override.buildingId)
        .set(override.toFirestore())
        .timeout(adminWriteTimeout);
  }

  /// 이 기기에서 보낸 쓰기가 모두 서버에 닿을 때까지 기다린다. 오프라인이면
  /// [timeout] 뒤 TimeoutException.
  static Future<void> waitForPendingWrites({
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _db.waitForPendingWrites().timeout(timeout);

  /// 덮어쓴 정보를 지우고 학생 제보 다수결로 정해지는 이름으로 되돌린다.
  static Future<void> clearOverride(String buildingId) async {
    await _db
        .collection(_overrideCollection)
        .doc(buildingId)
        .delete()
        .timeout(adminWriteTimeout);
  }

  static const String _customBuildingsCollection = 'housing_custom_buildings';

  /// 개발자/관리자가 직접 추가한 커스텀 건물 목록
  static Future<List<BaseBuilding>> fetchCustomBuildings() async {
    if (!FirestoreHealth.isAvailable) return const [];
    try {
      final snap = await _db
          .collection(_customBuildingsCollection)
          .get()
          .timeout(const Duration(seconds: 5));
      FirestoreHealth.reportSuccess();
      return _customBuildingsFrom(snap.docs);
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchCustomBuildings error: $e');
      return const [];
    }
  }

  static List<BaseBuilding> _customBuildingsFrom(
          Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      [
        for (final doc in docs)
          if (customBuildingFromMap(doc.id, doc.data()) case final b?) b,
      ];

  /// 직접 추가하거나 합친 건물을 실시간으로 받는다([watchOverrides] 참고).
  static Stream<List<BaseBuilding>> watchCustomBuildings() => _db
      .collection(_customBuildingsCollection)
      .snapshots()
      .map((snap) => _customBuildingsFrom(snap.docs));

  /// 새 건물을 생성하여 저장 (건물 도형 + 관리자 오버라이드 동시 등록)
  static Future<void> saveCustomBuilding({
    required BaseBuilding building,
    required HousingBuildingOverride override,
  }) async {
    await _db.collection(_customBuildingsCollection).doc(building.id).set({
      'name': override.name,
      'floors': building.floors,
      'road': building.road,
      'buildingNo': building.buildingNo,
      'isCampus': building.isCampus,
      if (building.use != null) 'use': building.use!.name,
      'ring': encodeRing(building.ring),
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(adminWriteTimeout);
    await setOverride(override);
  }

  /// 커스텀 건물 삭제
  static Future<void> deleteCustomBuilding(String buildingId) async {
    await _db
        .collection(_customBuildingsCollection)
        .doc(buildingId)
        .delete()
        .timeout(adminWriteTimeout);
    await clearOverride(buildingId);
  }

  // ── 즐겨찾기(찜) 로컬 저장소 ──────────────────────────────
  static const String _favKey = 'housing_favorite_building_ids';

  /// 사용자가 찜(즐겨찾기)한 건물 ID 목록을 불러온다.
  static Future<Set<String>> fetchFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favKey) ?? [];
    return list.toSet();
  }

  /// 특정 건물의 찜 상태를 토글하고 새로운 상태(true=찜됨)를 반환한다.
  static Future<bool> toggleFavorite(String buildingId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_favKey) ?? []).toSet();
    final isFav = set.contains(buildingId);
    if (isFav) {
      set.remove(buildingId);
    } else {
      set.add(buildingId);
    }
    await prefs.setStringList(_favKey, set.toList());
    return !isFav;
  }

  /// 특정 건물이 찜되어 있는지 확인한다.
  static Future<bool> isFavorite(String buildingId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favKey) ?? [];
    return list.contains(buildingId);
  }
}

enum HousingSubmitResult { ok, alreadyReported, failed }

/// 제보 화면에서 고르는 특징 목록.
/// 자유 입력 대신 미리 정해두면 같은 뜻의 표현이 흩어지지 않아
/// "많이 언급된 특징" 집계가 의미를 갖는다.
/// ⚠️ 여기 문자열이 곧 Firestore에 저장되는 값이고, "내 조건 찾기"가 이 값으로
/// 제보를 거른다. 철자를 바꾸면 **기존 제보가 그 조건에 영영 안 걸린다.**
///
/// 예전엔 목록이 두 벌이었다 — 제보 폼은 '방음 양호'를 저장하는데 관리자
/// 화면은 '방음 좋음'을 보여줬고, 제보 폼에만 있던 '베란다'는 관리자
/// 화면에 없었다. 같은 뜻인데 문자열이 달라 필터가 걸릴 수 없는 상태였다.
/// 앞쪽 10개가 실제로 제보에 쌓여 있는 값이라 철자를 그대로 유지한다.
const List<String> kHousingFeatures = [
  // 제보 폼이 써 온 값 (기존 데이터와 일치해야 함)
  '풀옵션',
  '엘리베이터',
  '주차 가능',
  '베란다',
  '복층',
  '심야전기',
  '도시가스',
  '햇빛 잘 듦',
  '방음 양호',
  '벌레 적음',
  // 이후 추가된 항목
  '분리형',
  '신축급',
  '관리비 저렴',
  '학교와 가까움',
  '조용함',
  '수압 좋음',
];

/// "내 조건 찾기" 조건 묶음.
///
/// 비어 있는(=아무 조건도 안 건) 항목은 거르지 않는다. 전부 비면 [isEmpty].
class HousingFilter {
  /// 비어 있으면 방 구조를 안 따진다.
  final Set<HousingRoomType> roomTypes;

  /// 보증금 상한(만원). null이면 안 따진다.
  final int? maxDeposit;

  /// 월 부담 상한(만원). null이면 안 따진다.
  final int? maxMonthly;

  /// true면 [maxMonthly]를 **월세+관리비**와 비교하고, false면 월세만 본다.
  /// 관리비가 월 10만원씩 붙는 집이 흔해서 이 토글이 결과를 크게 바꾼다.
  final bool includeMaintenance;

  /// 전부 갖춰야 하는 조건. 하나라도 빠지면 제외한다.
  final Set<String> requiredFeatures;

  /// 시세가 없어 판단할 수 없는 원룸도 결과에 넣을지.
  final bool includeUnknown;

  const HousingFilter({
    this.roomTypes = const {},
    this.maxDeposit,
    this.maxMonthly,
    this.includeMaintenance = true,
    this.requiredFeatures = const {},
    this.includeUnknown = false,
  });

  bool get isEmpty =>
      roomTypes.isEmpty &&
      maxDeposit == null &&
      maxMonthly == null &&
      requiredFeatures.isEmpty;

  HousingFilter copyWith({
    Set<HousingRoomType>? roomTypes,
    int? maxDeposit,
    int? maxMonthly,
    bool? includeMaintenance,
    Set<String>? requiredFeatures,
    bool? includeUnknown,
    bool clearDeposit = false,
    bool clearMonthly = false,
  }) =>
      HousingFilter(
        roomTypes: roomTypes ?? this.roomTypes,
        maxDeposit: clearDeposit ? null : (maxDeposit ?? this.maxDeposit),
        maxMonthly: clearMonthly ? null : (maxMonthly ?? this.maxMonthly),
        includeMaintenance: includeMaintenance ?? this.includeMaintenance,
        requiredFeatures: requiredFeatures ?? this.requiredFeatures,
        includeUnknown: includeUnknown ?? this.includeUnknown,
      );
}

/// 비교에 쓰는 방 시세 한 건. 학생 제보(방 구조별 평균)나 개발자가 확인해
/// 넣은 시세에서 온다. 금액은 만원 단위.
@immutable
class HousingPricePoint {
  /// null이면 방 구조를 모른다.
  final HousingRoomType? roomType;
  final int deposit;
  final int monthlyRent;

  /// 월세+관리비. 관리비를 모르면 월세와 같다.
  final int monthlyTotal;
  final bool maintenanceKnown;

  /// true: 학생 제보, false: 개발자가 확인해 넣은 시세.
  final bool fromReports;
  final String? asOf;

  const HousingPricePoint({
    required this.roomType,
    required this.deposit,
    required this.monthlyRent,
    required this.monthlyTotal,
    required this.maintenanceKnown,
    required this.fromReports,
    this.asOf,
  });

  int monthly({required bool withMaintenance}) => withMaintenance ? monthlyTotal : monthlyRent;
}

/// 개발자가 적은 방 구조 글자 → 방 구조. 순수 함수 — 테스트 대상.
HousingRoomType? roomTypeFromText(String? t) {
  final s = (t ?? '').replaceAll(' ', '').toLowerCase();
  if (s.isEmpty) return null;
  if (s.contains('1.5') || s.contains('일점오') || s.contains('분리형')) return HousingRoomType.onePointFive;
  if (s.contains('3룸') || s.contains('쓰리') || s.contains('3room') || s.contains('이상')) return HousingRoomType.threeRoomPlus;
  if (s.contains('2룸') || s.contains('투룸') || s.contains('2room')) return HousingRoomType.twoRoom;
  if (s.contains('원룸') || s.contains('1룸') || s.contains('oneroom')) return HousingRoomType.oneRoom;
  return null;
}

/// 건물 하나의 방 시세 목록. 순수 함수 — 테스트 대상.
///
/// - 학생 제보: 방 구조별 평균. 구조별 값이 없으면 건물 전체 평균을 그
///   구조에 쓰고, 아무도 구조를 안 적었으면 "구조 모름" 한 건으로 둔다.
/// - 개발자 확인 시세: 적은 그대로 한 건씩.
List<HousingPricePoint> housingPricePoints(HousingSummary? s, HousingBuildingOverride? o) {
  final out = <HousingPricePoint>[];
  if (s != null && s.hasData) {
    for (final e in s.roomPricingMap.entries) {
      out.add(HousingPricePoint(
        roomType: e.key,
        deposit: e.value.deposit,
        monthlyRent: e.value.monthlyRent,
        monthlyTotal: e.value.totalMonthly,
        maintenanceKnown: e.value.maintenanceFee > 0,
        fromReports: true,
      ));
    }
    final d = s.avgDeposit, r = s.avgRent;
    if (d != null && r != null) {
      final total = s.avgMonthlyTotal ?? r;
      final missing = [for (final t in s.roomTypes) if (!s.roomPricingMap.containsKey(t)) t];
      final types = s.roomTypes.isEmpty ? <HousingRoomType?>[null] : missing;
      for (final t in types) {
        out.add(HousingPricePoint(
          roomType: t,
          deposit: d,
          monthlyRent: r,
          monthlyTotal: total,
          maintenanceKnown: s.avgMaintenance != null,
          fromReports: true,
        ));
      }
    }
  }
  for (final p in o?.prices ?? const <HousingPriceEntry>[]) {
    out.add(HousingPricePoint(
      roomType: roomTypeFromText(p.roomType),
      deposit: p.deposit,
      monthlyRent: p.monthlyRent,
      monthlyTotal: p.monthlyRent + (p.maintenanceFee ?? 0),
      maintenanceKnown: p.maintenanceFee != null,
      fromReports: false,
      asOf: p.asOf,
    ));
  }
  return out;
}

/// "내 조건 찾기" 판정. 맞음·모름(비교할 시세·정보가 없음)·안 맞음.
enum HousingFilterVerdict { match, unknown, miss }

/// 이 건물이 조건에 맞는지와, 맞는 방 중 가장 싼 것. 순수 함수 — 테스트 대상.
///
/// 건물 **평균**이 아니라 **방 하나하나**로 본다 — 원룸 35만원·투룸 55만원이
/// 섞인 건물은 "원룸, 월 40 이하"에 걸려야 한다(평균으로 보면 빠졌다). 방 구조·
/// 보증금·월 부담은 **같은 방**이 모두 만족해야 한다. 비교할 시세가 없으면
/// "모름"이다 — 조건에 맞는다고 섞어 보여주면 오해하고, 무조건 빼면 시세가
/// 적은 지금은 결과가 거의 비어서 쓸 수가 없었다(제보 2건뿐, 2026-09).
({HousingFilterVerdict verdict, HousingPricePoint? best}) evaluateHousingFilter(
  HousingSummary? s,
  HousingBuildingOverride? o,
  HousingFilter f,
) {
  final points = housingPricePoints(s, o);
  final hasReports = s != null && s.hasData;

  // 특징(풀옵션·도시가스…)은 학생 제보에만 있다.
  var featureVerdict = HousingFilterVerdict.match;
  if (f.requiredFeatures.isNotEmpty) {
    if (!hasReports) {
      featureVerdict = HousingFilterVerdict.unknown;
    } else if (!f.requiredFeatures.every(s.allFeatures.contains)) {
      featureVerdict = HousingFilterVerdict.miss;
    }
  }

  final priceConditions = f.roomTypes.isNotEmpty || f.maxDeposit != null || f.maxMonthly != null;
  HousingFilterVerdict priceVerdict;
  HousingPricePoint? best;
  bool fitsMoney(HousingPricePoint p) =>
      (f.maxDeposit == null || p.deposit <= f.maxDeposit!) &&
      (f.maxMonthly == null || p.monthly(withMaintenance: f.includeMaintenance) <= f.maxMonthly!);
  int cmp(HousingPricePoint a, HousingPricePoint b) {
    final m = a.monthly(withMaintenance: f.includeMaintenance).compareTo(b.monthly(withMaintenance: f.includeMaintenance));
    return m != 0 ? m : a.deposit.compareTo(b.deposit);
  }

  if (points.isEmpty) {
    priceVerdict = (priceConditions || !hasReports) ? HousingFilterVerdict.unknown : HousingFilterVerdict.match;
  } else {
    final fits = [
      for (final p in points)
        if ((f.roomTypes.isEmpty || (p.roomType != null && f.roomTypes.contains(p.roomType))) && fitsMoney(p)) p,
    ]..sort(cmp);
    if (fits.isNotEmpty) {
      priceVerdict = HousingFilterVerdict.match;
      best = fits.first;
    } else if (f.roomTypes.isNotEmpty && points.any((p) => p.roomType == null && fitsMoney(p))) {
      // 금액은 맞는데 방 구조를 모르는 시세만 있다.
      priceVerdict = HousingFilterVerdict.unknown;
    } else {
      priceVerdict = HousingFilterVerdict.miss;
    }
    best ??= (List.of(points)..sort(cmp)).first;
  }

  final verdict = [featureVerdict, priceVerdict].reduce((a, b) => a.index > b.index ? a : b);
  return (verdict: verdict, best: best);
}

/// 제보만으로 판정하던 예전 함수. 제보가 없는 건물은 어떤 조건에도 안 걸린다.
/// 순수 함수 — 테스트 대상.
bool housingMatchesFilter(HousingSummary s, HousingFilter f) {
  if (!s.hasData) return false;
  return evaluateHousingFilter(s, null, f).verdict == HousingFilterVerdict.match;
}

/// "내 조건 찾기"를 걸면 보여줄 건물. 맞는 건물, 그리고 [HousingFilter.includeUnknown]
/// 이면 시세를 몰라 판단할 수 없는 원룸도. 순수 함수 — 테스트 대상.
bool housingPassesFilter(HousingFilterVerdict v, HousingFilter f) =>
    v == HousingFilterVerdict.match || (f.includeUnknown && v == HousingFilterVerdict.unknown);

/// 자취방 지도에 건물마다 무엇을 칠하고 어떤 이름표를 달지.
///
/// 화면(HousingScreen)과 지도 미리보기 도구(test/map_preview.dart)가
/// **같은 규칙**을 쓰게 하려고 순수 함수로 뺐다. 예전엔 화면 안에만 있어서,
/// 미리보기로는 월탄3길 초록·이름표를 앱 그대로 확인할 수가 없었다.
@immutable
class HousingMapStyle {
  /// 원룸으로 볼 만한 건물. 연녹색 바탕으로 칠한다.
  final Set<String> oneRoomIds;

  /// 건물별 지붕색(구역색·도로별 색).
  final Map<String, Color> zoneColors;

  /// 건물별 이름표.
  final Map<String, String> displayNames;

  /// 벽에 창문을 낼 건물. 기본은 자취방 건물이고, 건물 편집의 "창문 표시"로
  /// 건물마다 켜고 끈다.
  final Set<String> windowIds;

  const HousingMapStyle({
    required this.oneRoomIds,
    required this.zoneColors,
    required this.displayNames,
    this.windowIds = const {},
  });
}

/// 건물 외곽선을 Firestore에 넣을 모양으로 바꾼다.
///
/// Firestore는 **배열 안의 배열을 받지 않는다**. `[[x, y], …]`로 넣으면
/// 쓰기 자체가 invalid-argument로 거부돼서, 건물 합치기·추가가 한 번도
/// 저장되지 못했다. 그래서 점 하나를 `{x, y}` 맵으로 둔다.
List<Map<String, double>> encodeRing(List<Offset> ring) => [
      for (final p in ring) {'x': p.dx, 'y': p.dy},
    ];

/// [encodeRing]의 반대. 옛 `[x, y]` 모양도 읽는다(로컬 캐시 등에 남아 있을
/// 수 있다). 알아볼 수 없는 점은 건너뛴다.
List<Offset> decodeRing(Object? raw) {
  if (raw is! List) return const [];
  final out = <Offset>[];
  for (final p in raw) {
    if (p is Map && p['x'] is num && p['y'] is num) {
      out.add(Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
    } else if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
      out.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
    }
  }
  return out;
}

/// `housing_custom_buildings` 문서 하나를 건물로 읽는다. 외곽선 점이 셋이
/// 안 되면 그릴 수 없으니 null. 순수 함수 — 테스트 대상.
BaseBuilding? customBuildingFromMap(String id, Map<String, dynamic> d) {
  final ring = decodeRing(d['ring']);
  if (ring.length < 3) return null;
  return BaseBuilding(
    id: id,
    officialName: d['name'] as String?,
    floors: (d['floors'] as num?)?.toInt() ?? 3,
    road: d['road'] as String?,
    buildingNo: d['buildingNo'] as String?,
    ring: ring,
    isCampus: (d['isCampus'] as bool?) ?? false,
    use: BuildingUse.from(d['use'] as String?),
  );
}

/// 여러 동을 합칠 때 결과 건물이 이어받을 교내 여부·용도. 합친 조각 중
/// 교내 건물이 있으면 교내이고, 용도는 교내 조각들에서 가장 많은 것.
/// 순수 함수 — 테스트 대상.
({bool isCampus, BuildingUse? use}) mergedCampusTraits(Iterable<BaseBuilding> parts) {
  final campus = [for (final p in parts) if (p.isCampus) p];
  if (campus.isEmpty) return (isCampus: false, use: null);
  final counts = <BuildingUse, int>{};
  for (final p in campus) {
    final u = p.use;
    if (u != null) counts[u] = (counts[u] ?? 0) + 1;
  }
  BuildingUse? best;
  for (final e in counts.entries) {
    if (best == null || e.value > counts[best]!) best = e.key;
  }
  return (isCampus: true, use: best);
}

/// 이미 합쳐 둔 건물이 교내 여부·용도를 잃은 경우 되살린다. 예전 합치기는
/// 교내 건물을 합쳐도 결과를 "교외 건물"로 만들어서, 기숙사·강의동이 원룸처럼
/// 칠해졌다. 원래 조각들은 수정 문서의 mergedWith로 결과를 가리키고 있으니
/// 그 조각들에서 다시 이어받는다. 순수 함수 — 테스트 대상.
///
/// 개발자가 구역을 "캠퍼스 시설"로 정한 건물도 여기서 교내 건물이 된다 —
/// 주소(태성탑연로 250)·용도 색·시세 숨김이 모두 교내 규칙을 따른다.
List<BaseBuilding> inheritMergedCampus(
  List<BaseBuilding> buildings,
  Map<String, HousingBuildingOverride> overrides,
) {
  final partsOf = <String, List<BaseBuilding>>{};
  for (final b in buildings) {
    final target = overrides[b.id]?.mergedWith;
    if (target != null && target.isNotEmpty) (partsOf[target] ??= []).add(b);
  }
  bool taggedCampus(BaseBuilding b) {
    final o = overrides[b.id];
    return o != null && o.isNamed && o.zone == HousingZone.campus;
  }

  return [
    for (final b in buildings)
      () {
        if (partsOf[b.id] case final parts?) {
          final t = mergedCampusTraits(parts);
          if (t.isCampus) return b.copyWith(isCampus: true, use: b.use ?? t.use);
        }
        if (!b.isCampus && taggedCampus(b)) return b.copyWith(isCampus: true);
        return b;
      }(),
  ];
}

/// 화면에 보여줄 주소. 교내 건물은 수정 문서에 다른 주소가 적혀 있어도
/// 모두 태성탑연로 250이다. 순수 함수 — 테스트 대상.
String displayAddress(BaseBuilding b, HousingBuildingOverride? o) =>
    b.isCampus ? kCampusAddress : (o?.address ?? b.addressLabel);

/// 구역 딱지. 교내 건물은 수정 문서에 원룸 구역이 적혀 있어도(예전엔 기본값
/// "정문상가 뒷편"으로 저장됐다) "캠퍼스 시설"로 보여준다.
HousingZone badgeZone(BaseBuilding b, OneRoomName known) =>
    b.isCampus ? HousingZone.campus : known.zone;

/// 지도 데이터에 구워진 건물 뒤에 직접 추가·병합한 건물을 붙인다. 같은 id가
/// 이미 있으면 구워진 쪽을 쓴다. 순수 함수 — 테스트 대상.
List<BaseBuilding> withCustomBuildings(
  List<BaseBuilding> base,
  Iterable<BaseBuilding> custom,
) {
  final ids = {for (final b in base) b.id};
  return [...base, ...custom.where((c) => !ids.contains(c.id))];
}

/// 관리자 수정을 지도에 그릴 건물 목록에 반영한다. 순수 함수 — 테스트 대상.
///
/// - 삭제됐거나 다른 건물로 합쳐진 건물은 뺀다.
/// - 외곽선을 고쳤으면 그 모양으로 바꾼다.
/// - 층수를 고쳤으면 그 층수로 바꾼다. 건물 높이는 층수에 비례하므로
///   (IsoProjection.heightOf) 대장 값이 틀려 납작하게 보이던 건물이
///   고친 층수만큼 올라선다.
List<BaseBuilding> applyBuildingOverrides(
  Iterable<BaseBuilding> buildings,
  Map<String, HousingBuildingOverride> overrides,
) {
  final out = <BaseBuilding>[];
  for (final b in buildings) {
    final o = overrides[b.id];
    if (o == null) {
      out.add(b);
      continue;
    }
    if (o.isDeleted == true || o.mergedWith != null) continue;
    final ring = o.customRing;
    // 높이는 지도 높이가 따로 있으면 그걸로(표시 층수는 그대로 floors).
    final floors = o.mapFloors ?? o.floors;
    out.add(b.copyWith(
      ring: (ring != null && ring.length >= 3) ? ring : null,
      floors: (floors != null && floors >= 1) ? floors : null,
    ));
  }
  return out;
}

/// 순수 함수 — 테스트 대상.
///
/// 이름표 우선순위: 관리자 수정 > 학생 제보 > 조사해 넣은 이름.
/// 조사한 이름은 tool/mapsrc/building_names.json에서 지도 데이터에 구워져
/// 온다([BaseBuilding.officialName]). 이름이 없으면 이름표를 달지 않는다 —
/// 예전엔 번지수("48", "26-4")로 대신 채웠는데, 숫자 마커가 지도를 어지럽혀
/// 뺐다. 관리자가 [이름표] 도구로 끈 건물(hideLabel)도 이름표가 없다.
///
/// [matches]가 비어 있지 않으면("내 조건 찾기"를 건 상태) 맞는 건물만
/// 색·이름표를 남겨 후보가 지도에서 바로 눈에 띄게 한다.
HousingMapStyle housingMapStyle(
  Iterable<BaseBuilding> buildings, {
  Map<String, HousingSummary> summaries = const {},
  Map<String, HousingBuildingOverride> overrides = const {},
  Set<String> matches = const {},
}) {
  OneRoomName? known(String id) {
    final o = overrides[id];
    if (o != null && o.isNamed) return o.toOneRoomName();
    final oid = summaries[id]?.oneRoomId;
    return oid == null ? null : kOneRoomNameById[oid];
  }

  final oneRoomIds = <String>{};
  final zoneColors = <String, Color>{};
  final displayNames = <String, String>{};
  final windowIds = <String>{};

  for (final b in buildings) {
    final isOneRoom = looksLikeOneRoom(b, summaries);
    if (isOneRoom) oneRoomIds.add(b.id);

    final o = overrides[b.id];
    if (o?.showWindows ?? (isOneRoom && !b.isCampus)) windowIds.add(b.id);
    final k = known(b.id);
    if (o != null && o.usesSystemColor) {
      // 시스템 색: 칠하지 않아 밝은/다크 모드 기본 색을 따른다. 이름표만 단다.
      final label = o.isNamed ? o.name : (k?.name ?? b.officialName);
      if (label != null && label.isNotEmpty) displayNames[b.id] = label;
      continue;
    }
    if (o?.customColor != null) {
      zoneColors[b.id] = o!.customColor!;
      final label = o.isNamed ? o.name : (k?.name ?? b.officialName);
      if (label != null && label.isNotEmpty) displayNames[b.id] = label;
    } else if (k != null) {
      zoneColors[b.id] = k.zone.color;
      displayNames[b.id] = k.name;
    } else if (isOneRoom) {
      final official = b.officialName;
      if (official != null && official.isNotEmpty) {
        displayNames[b.id] = official;
      }
    }

    // 도로별 색. 이름표만으로는 어느 골목인지 한눈에 안 들어온다.
    final roadColor = kHousingRoadColors[b.road];
    if (roadColor != null) zoneColors[b.id] ??= roadColor;

    // 교내 건물은 용도별 색(강의동·기숙사…)이 기본이다. 관리자가 직접 칠한
    // 색만 그 위에 얹고, 원룸 구역 색·도로 색은 칠하지 않는다.
    if (b.isCampus && o?.customColor == null) zoneColors.remove(b.id);
  }

  // 관리자가 이름표를 끈 건물.
  displayNames.removeWhere((id, _) => overrides[id]?.hideLabel == true);

  if (matches.isNotEmpty) {
    zoneColors.removeWhere((id, _) => !matches.contains(id));
    displayNames.removeWhere((id, _) => !matches.contains(id));
  }

  return HousingMapStyle(
    oneRoomIds: oneRoomIds,
    zoneColors: zoneColors,
    displayNames: displayNames,
    windowIds: windowIds,
  );
}

/// 관리자 쓰기 실패를 알릴 문구. 원인마다 할 일이 달라서 나눠 알린다.
/// [what]은 '저장'·'삭제'처럼 무엇을 못 했는지. 순수 함수 — 테스트 대상.
String adminWriteErrorMessage(Object error, {String what = '저장'}) {
  if (error is TimeoutException) {
    return '서버가 응답하지 않아 $what하지 못했어요. Firebase 하루 쓰기 한도(2만 건)를 '
        '넘겼거나 네트워크가 끊겼을 수 있어요.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'resource-exhausted':
        return '오늘 Firebase 쓰기 한도를 넘겨 $what하지 못했어요. 한국 시각 오후 4~5시 이후에 다시 해 주세요.';
      case 'permission-denied':
        // 이 기기에 권한이 없거나, 새로 만든 저장 대상의 규칙이 아직 서버에
        // 게시되지 않은 경우다(위치 찍기를 처음 넣었을 때 실제로 이랬다).
        return '서버가 권한 문제로 $what 요청을 거부했어요. 개발자 비밀번호를 다시 넣어 보고, '
            '그래도 안 되면 Firestore 규칙이 게시됐는지 확인해 주세요.';
    }
  }
  return '$what하지 못했어요. 네트워크를 확인해 주세요.';
}

/// 제보 화면에서 고르는 관리비 포함 공과금 항목 목록.
const List<String> kHousingUtilities = [
  '수도',
  '인터넷',
  '전기',
  '도시가스',
];

/// 자취방 목록 정렬 기준.
enum HousingSortType {
  monthlyTotalAsc('월 부담 싼 순'),
  depositAsc('보증금 싼 순'),
  distanceMainGateAsc('정문 가까운 순'),
  distanceLibraryAsc('도서관 가까운 순'),
  reportCountDesc('제보 많은 순'),
  nameAsc('이름 순');

  final String label;
  const HousingSortType(this.label);
}

/// 자취방 목록 정렬 순수 함수 — 테스트 대상.
List<T> sortHousingItems<T>({
  required List<T> items,
  required HousingSortType sortType,
  required HousingSummary Function(T) getSummary,
  required BaseBuilding Function(T) getBuilding,
  required String Function(T) getName,
}) {
  final copy = List<T>.from(items);
  copy.sort((a, b) {
    switch (sortType) {
      case HousingSortType.monthlyTotalAsc:
        final am = getSummary(a).avgMonthlyTotal ?? (1 << 30);
        final bm = getSummary(b).avgMonthlyTotal ?? (1 << 30);
        if (am != bm) return am.compareTo(bm);
        final ad = getSummary(a).avgDeposit ?? (1 << 30);
        final bd = getSummary(b).avgDeposit ?? (1 << 30);
        if (ad != bd) return ad.compareTo(bd);
        return getName(a).compareTo(getName(b));

      case HousingSortType.depositAsc:
        final ad = getSummary(a).avgDeposit ?? (1 << 30);
        final bd = getSummary(b).avgDeposit ?? (1 << 30);
        if (ad != bd) return ad.compareTo(bd);
        final am = getSummary(a).avgMonthlyTotal ?? (1 << 30);
        final bm = getSummary(b).avgMonthlyTotal ?? (1 << 30);
        if (am != bm) return am.compareTo(bm);
        return getName(a).compareTo(getName(b));

      case HousingSortType.distanceMainGateAsc:
        final ad = walkingDistanceMeters(getBuilding(a).center, CampusLandmark.mainGate);
        final bd = walkingDistanceMeters(getBuilding(b).center, CampusLandmark.mainGate);
        if (ad != bd) return ad.compareTo(bd);
        return getName(a).compareTo(getName(b));

      case HousingSortType.distanceLibraryAsc:
        final ad = walkingDistanceMeters(getBuilding(a).center, CampusLandmark.library);
        final bd = walkingDistanceMeters(getBuilding(b).center, CampusLandmark.library);
        if (ad != bd) return ad.compareTo(bd);
        return getName(a).compareTo(getName(b));

      case HousingSortType.reportCountDesc:
        final ac = getSummary(a).reportCount;
        final bc = getSummary(b).reportCount;
        if (ac != bc) return bc.compareTo(ac);
        return getName(a).compareTo(getName(b));

      case HousingSortType.nameAsc:
        return getName(a).compareTo(getName(b));
    }
  });
  return copy;
}
