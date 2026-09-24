import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, Offset;
import 'package:shared_preferences/shared_preferences.dart';

import 'housing_iso.dart' show BaseBuilding;
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

  /// 관리자가 아는 실제 층수·세대수. 대장 값이 틀린 건물이 있다.
  final int? floors;
  final int? unitCount;

  /// 개발자/관리자가 직접 지정한 건물 고유 색상 (16진수 HEX 예: "#4CAF50")
  final String? customColorHex;

  Color? get customColor {
    if (customColorHex == null || customColorHex!.trim().isEmpty) return null;
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
    this.floors,
    this.unitCount,
    this.customColorHex,
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
        if (floors != null) 'floors': floors,
        if (unitCount != null) 'unitCount': unitCount,
        if (_clean(customColorHex) != null)
          'customColorHex': _clean(customColorHex),
      };

  static HousingBuildingOverride? fromMap(String buildingId, Map<String, dynamic> d) {
    final name = d['name'];
    if (name is! String || name.isEmpty) return null;
    HousingZone? zone;
    for (final z in HousingZone.values) {
      if (z.name == d['zone']) {
        zone = z;
        break;
      }
    }
    if (zone == null) return null;
    return HousingBuildingOverride(
      buildingId: buildingId,
      name: name,
      zone: zone,
      builtYear: (d['builtYear'] as num?)?.toInt(),
      note: d['note'] as String?,
      address: d['address'] as String?,
      landlordName: d['landlordName'] as String?,
      landlordPhone: d['landlordPhone'] as String?,
      floors: (d['floors'] as num?)?.toInt(),
      unitCount: (d['unitCount'] as num?)?.toInt(),
      customColorHex: d['customColorHex'] as String?,
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
    int? floors,
    int? unitCount,
    String? customColorHex,
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
        floors: floors ?? this.floors,
        unitCount: unitCount ?? this.unitCount,
        customColorHex: customColorHex ?? this.customColorHex,
      );

  /// 화면 표시용으로 [OneRoomName]과 같은 모양으로 바꾼다 — 지도·검색이
  /// 제보 다수결로 정해진 이름과 덮어쓴 이름을 구분 없이 다룰 수 있게.
  OneRoomName toOneRoomName() => OneRoomName(
        id: 'override:$buildingId',
        name: name,
        zone: zone,
        builtYear: builtYear,
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
const List<String> kHousingPros = [
  '도시가스 난방',
  '정문 도보 3분컷',
  '방음 우수(콘크리트벽)',
  '채광/남향',
  '수압 강함/온수 양호',
  '1.5룸/넓은 분리형',
  '풀옵션(전자레인지 등)',
  '엘리베이터 있음',
  '주차 공간 넉넉',
  '집주인 친절/빠른 수리',
  '심야 안심/밝은 가로등',
];

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

/// 한 건물의 제보를 모은 결과.
class HousingSummary {
  final int reportCount;

  /// 보증금·월세 중앙값(만원). 제보가 없으면 null.
  ///
  /// 평균이 아니라 **중앙값**을 쓴다. 제보가 몇 건 안 되는 상태에서 이상한
  /// 값 하나가 섞이면 평균은 크게 흔들리지만 중앙값은 버틴다.
  final int? medianDeposit;
  final int? medianRent;

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

  /// 가장 최근 제보 시점.
  final DateTime? latestReport;

  /// 가장 많이 지목된 원룸 이름([OneRoomName.id]).
  /// 건축물대장에 원룸 이름이 없어 학생 제보로만 채워진다.
  final String? oneRoomId;

  /// 관리비 중앙값(만원). 아무도 안 적었으면 null.
  final int? medianMaintenance;

  /// 관리비까지 포함한 월 부담액 중앙값(만원). 제보가 없으면 null.
  final int? medianMonthlyTotal;

  /// 이 건물에서 제보된 방 구조들.
  final Set<HousingRoomType> roomTypes;

  /// 이 건물에 남겨진 최근 거주 후기 (최대 10건, 최신순).
  final List<String> recentReviews;

  /// 이 건물 제보들에서 언급된 포함 관리비 항목 (예: 수도, 인터넷 등).
  final Set<String> commonUtilities;

  const HousingSummary({
    required this.reportCount,
    required this.medianDeposit,
    required this.medianRent,
    required this.topFeatures,
    required this.latestReport,
    this.oneRoomId,
    this.medianMaintenance,
    this.medianMonthlyTotal,
    this.roomTypes = const {},
    this.allFeatures = const {},
    this.topDrawbacks = const [],
    this.allDrawbacks = const {},
    this.publicContactPhone,
    this.recentReviews = const [],
    this.commonUtilities = const {},
  });

  static const empty = HousingSummary(
    reportCount: 0,
    medianDeposit: null,
    medianRent: null,
    topFeatures: [],
    latestReport: null,
    topDrawbacks: [],
    allDrawbacks: {},
    publicContactPhone: null,
    recentReviews: [],
    commonUtilities: {},
  );

  bool get hasData => reportCount > 0;

  /// 제보가 적으면 화면에서 "참고용"이라고 알려주기 위한 기준.
  bool get isThin => reportCount < 3;

  factory HousingSummary.from(Iterable<HousingReport> reports) {
    final list = reports.toList();
    if (list.isEmpty) return empty;

    int? median(List<int> values) {
      if (values.isEmpty) return null;
      values.sort();
      final mid = values.length ~/ 2;
      return values.length.isOdd
          ? values[mid]
          : ((values[mid - 1] + values[mid]) / 2).round();
    }

    // 장점 집계
    final featureCount = <String, int>{};
    for (final r in list) {
      for (final f in r.features) {
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

    // 임대 문의처 전화번호 최신순 추출
    final phonesWithDate = list
        .where((r) => r.contactPhone != null && r.contactPhone!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final publicContactPhone =
        phonesWithDate.isNotEmpty ? phonesWithDate.first.contactPhone : null;

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

    return HousingSummary(
      reportCount: list.length,
      medianDeposit: median(validDeposits.isNotEmpty ? validDeposits : list.map((r) => r.deposit).toList()),
      medianRent: median(validRents.isNotEmpty ? validRents : list.map((r) => r.monthlyRent).toList()),
      medianMaintenance: median(fees),
      medianMonthlyTotal: median(validTotals.isNotEmpty ? validTotals : list.map((r) => r.monthlyTotal).toList()),
      roomTypes: list.map((r) => r.roomType).whereType<HousingRoomType>().toSet(),
      topFeatures: sortedFeatures.take(5).map((e) => e.key).toList(),
      allFeatures: featureCount.keys.toSet(),
      topDrawbacks: sortedDrawbacks.take(5).map((e) => e.key).toList(),
      allDrawbacks: drawbackCount.keys.toSet(),
      publicContactPhone: publicContactPhone,
      recentReviews: recentReviews,
      commonUtilities: utilities,
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
    if (!FirestoreHealth.isAvailable) return const {};
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
      return byBuilding
          .map((id, reports) => MapEntry(id, HousingSummary.from(reports)));
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchSummaries error: $e');
      return const {};
    }
  }

  /// 제보 남기기. 같은 건물에 이미 남겼으면 막는다(로컬 기록 기준).
  /// 완전한 중복 방지는 아니지만, 실수로 여러 번 눌러 평균이 쏠리는 건 막는다.
  static Future<HousingSubmitResult> submit(HousingReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'housing_reported_${report.buildingId}';
    if (prefs.getBool(key) ?? false) {
      return HousingSubmitResult.alreadyReported;
    }
    try {
      await _db
          .collection(_collection)
          .add(report.toFirestore())
          .timeout(const Duration(seconds: 6));
      await prefs.setBool(key, true);
      FirestoreHealth.reportSuccess();
      return HousingSubmitResult.ok;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.submit error: $e');
      return HousingSubmitResult.failed;
    }
  }

  /// 외벽 현수막/관리인 임대 문의 연락처만 빠르게 제보
  static Future<bool> submitContactPhone({
    required String buildingId,
    required String phone,
    String? oneRoomId,
  }) async {
    try {
      final report = HousingReport(
        buildingId: buildingId,
        deposit: 0,
        monthlyRent: 0,
        contactPhone: phone.trim(),
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
  static Future<bool> hasReported(String buildingId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('housing_reported_$buildingId') ?? false;
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
      final result = <String, HousingBuildingOverride>{};
      for (final doc in snap.docs) {
        final o = HousingBuildingOverride.fromMap(doc.id, doc.data());
        if (o != null) result[doc.id] = o;
      }
      return result;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchOverrides error: $e');
      return const {};
    }
  }

  static Future<void> setOverride(HousingBuildingOverride override) async {
    await _db
        .collection(_overrideCollection)
        .doc(override.buildingId)
        .set(override.toFirestore());
  }

  /// 덮어쓴 정보를 지우고 학생 제보 다수결로 정해지는 이름으로 되돌린다.
  static Future<void> clearOverride(String buildingId) async {
    await _db.collection(_overrideCollection).doc(buildingId).delete();
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
      final list = <BaseBuilding>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final rawRing = d['ring'] as List?;
        final ring = <Offset>[];
        if (rawRing != null) {
          for (final p in rawRing) {
            if (p is List && p.length >= 2) {
              ring.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
            }
          }
        }
        if (ring.length >= 3) {
          list.add(BaseBuilding(
            id: doc.id,
            officialName: d['name'] as String?,
            floors: (d['floors'] as num?)?.toInt() ?? 3,
            road: d['road'] as String?,
            buildingNo: d['buildingNo'] as String?,
            ring: ring,
            isCampus: (d['isCampus'] as bool?) ?? false,
          ));
        }
      }
      return list;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('HousingService.fetchCustomBuildings error: $e');
      return const [];
    }
  }

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
      'ring': [
        for (final p in building.ring) [p.dx, p.dy],
      ],
      'createdAt': FieldValue.serverTimestamp(),
    });
    await setOverride(override);
  }

  /// 커스텀 건물 삭제
  static Future<void> deleteCustomBuilding(String buildingId) async {
    await _db.collection(_customBuildingsCollection).doc(buildingId).delete();
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

  const HousingFilter({
    this.roomTypes = const {},
    this.maxDeposit,
    this.maxMonthly,
    this.includeMaintenance = true,
    this.requiredFeatures = const {},
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
    bool clearDeposit = false,
    bool clearMonthly = false,
  }) =>
      HousingFilter(
        roomTypes: roomTypes ?? this.roomTypes,
        maxDeposit: clearDeposit ? null : (maxDeposit ?? this.maxDeposit),
        maxMonthly: clearMonthly ? null : (maxMonthly ?? this.maxMonthly),
        includeMaintenance: includeMaintenance ?? this.includeMaintenance,
        requiredFeatures: requiredFeatures ?? this.requiredFeatures,
      );
}

/// 이 건물이 조건에 맞는지.
///
/// 제보가 없는 건물은 비교할 값이 없으므로 **항상 제외**한다 — 조건을 걸었는데
/// 정보가 없는 건물이 섞여 나오면 "조건에 맞다"고 오해하게 된다.
///
/// 순수 함수 — 테스트 대상.
bool housingMatchesFilter(HousingSummary s, HousingFilter f) {
  if (!s.hasData) return false;
  if (f.isEmpty) return true;

  if (f.roomTypes.isNotEmpty) {
    // 방 구조를 아무도 안 적은 건물은 알 수 없으므로 제외한다.
    if (s.roomTypes.isEmpty) return false;
    if (!s.roomTypes.any(f.roomTypes.contains)) return false;
  }

  final maxDeposit = f.maxDeposit;
  if (maxDeposit != null) {
    final d = s.medianDeposit;
    if (d == null || d > maxDeposit) return false;
  }

  final maxMonthly = f.maxMonthly;
  if (maxMonthly != null) {
    final m = f.includeMaintenance ? s.medianMonthlyTotal : s.medianRent;
    if (m == null || m > maxMonthly) return false;
  }

  if (f.requiredFeatures.isNotEmpty) {
    if (!f.requiredFeatures.every(s.allFeatures.contains)) return false;
  }

  return true;
}

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

  const HousingMapStyle({
    required this.oneRoomIds,
    required this.zoneColors,
    required this.displayNames,
  });
}

/// 순수 함수 — 테스트 대상.
///
/// 이름표 우선순위: 관리자 수정 > 학생 제보 > 조사해 넣은 이름 > 건물번호.
/// 조사한 이름은 tool/mapsrc/building_names.json에서 지도 데이터에 구워져
/// 오고([BaseBuilding.officialName]), 그마저 없으면 건물번호로 대신한다 —
/// 번호는 교외 건물이 전부 갖고 있어 빈 이름표가 안 생긴다. 도로명까지
/// 붙이면("월탄3길 5") 이름표가 길어져 서로 많이 겹친다. 어느 길인지는 도로별
/// 색이 알려주고, 건물을 누르면 전체 주소가 뜬다.
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
    if (o != null) return o.toOneRoomName();
    final oid = summaries[id]?.oneRoomId;
    return oid == null ? null : kOneRoomNameById[oid];
  }

  final oneRoomIds = <String>{};
  final zoneColors = <String, Color>{};
  final displayNames = <String, String>{};

  for (final b in buildings) {
    final isOneRoom = looksLikeOneRoom(b, summaries);
    if (isOneRoom) oneRoomIds.add(b.id);

    final o = overrides[b.id];
    final k = known(b.id);
    if (o?.customColor != null) {
      zoneColors[b.id] = o!.customColor!;
      displayNames[b.id] = o.name;
    } else if (k != null) {
      zoneColors[b.id] = k.zone.color;
      displayNames[b.id] = k.name;
    } else if (isOneRoom) {
      final official = b.officialName;
      final no = b.buildingNo;
      if (official != null && official.isNotEmpty) {
        displayNames[b.id] = official;
      } else if (no != null && no.isNotEmpty) {
        displayNames[b.id] = no;
      }
    }

    // 도로별 색. 이름표만으로는 어느 골목인지 한눈에 안 들어온다.
    final roadColor = kHousingRoadColors[b.road];
    if (roadColor != null) zoneColors[b.id] ??= roadColor;
  }

  if (matches.isNotEmpty) {
    zoneColors.removeWhere((id, _) => !matches.contains(id));
    displayNames.removeWhere((id, _) => !matches.contains(id));
  }

  return HousingMapStyle(
    oneRoomIds: oneRoomIds,
    zoneColors: zoneColors,
    displayNames: displayNames,
  );
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
        final am = getSummary(a).medianMonthlyTotal ?? (1 << 30);
        final bm = getSummary(b).medianMonthlyTotal ?? (1 << 30);
        if (am != bm) return am.compareTo(bm);
        final ad = getSummary(a).medianDeposit ?? (1 << 30);
        final bd = getSummary(b).medianDeposit ?? (1 << 30);
        if (ad != bd) return ad.compareTo(bd);
        return getName(a).compareTo(getName(b));

      case HousingSortType.depositAsc:
        final ad = getSummary(a).medianDeposit ?? (1 << 30);
        final bd = getSummary(b).medianDeposit ?? (1 << 30);
        if (ad != bd) return ad.compareTo(bd);
        final am = getSummary(a).medianMonthlyTotal ?? (1 << 30);
        final bm = getSummary(b).medianMonthlyTotal ?? (1 << 30);
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
