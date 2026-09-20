import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

  /// 자유 특징 — "풀옵션", "복층", "주차 가능" 등.
  final List<String> features;

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

  const HousingReport({
    required this.buildingId,
    required this.deposit,
    required this.monthlyRent,
    required this.features,
    required this.reportedAt,
    this.maintenanceFee,
    this.oneRoomId,
    this.id,
    this.roomType,
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
        'features': features,
        'reportedAt': FieldValue.serverTimestamp(),
      };

  static HousingReport? fromMap(Map<String, dynamic> d, {String? id}) {
    final buildingId = d['buildingId'];
    final deposit = d['deposit'];
    final rent = d['monthlyRent'];
    if (buildingId is! String || deposit is! num || rent is! num) return null;
    final ts = d['reportedAt'];
    return HousingReport(
      id: id,
      buildingId: buildingId,
      deposit: deposit.toInt(),
      monthlyRent: rent.toInt(),
      maintenanceFee: (d['maintenanceFee'] as num?)?.toInt(),
      oneRoomId: d['oneRoomId'] as String?,
      roomType: HousingRoomType.fromKey(d['roomType'] as String?),
      features: (d['features'] as List?)?.whereType<String>().toList() ?? const [],
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

/// 한 건물의 제보를 모은 결과.
class HousingSummary {
  final int reportCount;

  /// 보증금·월세 중앙값(만원). 제보가 없으면 null.
  ///
  /// 평균이 아니라 **중앙값**을 쓴다. 제보가 몇 건 안 되는 상태에서 이상한
  /// 값 하나가 섞이면 평균은 크게 흔들리지만 중앙값은 버틴다.
  final int? medianDeposit;
  final int? medianRent;

  /// 많이 언급된 특징 순. **상위 5개만** — 화면 표시용이다.
  final List<String> topFeatures;

  /// 한 번이라도 언급된 특징 전부. 필터는 이걸 봐야 한다 —
  /// [topFeatures]로 거르면 6번째로 밀린 특징은 조건에 영영 안 걸린다.
  final Set<String> allFeatures;

  /// 가장 최근 제보 시점.
  final DateTime? latestReport;

  /// 가장 많이 지목된 원룸 이름([OneRoomName.id]).
  /// 건축물대장에 원룸 이름이 없어 학생 제보로만 채워진다.
  final String? oneRoomId;

  /// 관리비 중앙값(만원). 아무도 안 적었으면 null.
  ///
  /// ⚠️ 이 값은 **관리비를 적어 낸 제보만** 모은 것이라 [medianRent]와
  /// 모집단이 다르다. 둘을 더하면 안 된다 — 그건 [medianMonthlyTotal]이
  /// 따로 있는 이유다.
  final int? medianMaintenance;

  /// 관리비까지 포함한 월 부담액 중앙값(만원). 제보가 없으면 null.
  ///
  /// 제보마다 월세+관리비를 먼저 더한 뒤 그 값들의 중앙값을 낸다.
  /// 예전엔 `medianRent + medianMaintenance`로 구했는데, 중앙값은 더할 수
  /// 있는 값이 아닌 데다 두 값의 모집단까지 달라서 실제로 없는 금액이
  /// 나왔다. 5건 중 4건이 관리비 미기재(월세 40)이고 1건만 40+20이면
  /// 40+20=60이 되어, 5명 중 4명이 40을 내는 건물이 "월 50 이하"
  /// 검색에서 빠졌다.
  final int? medianMonthlyTotal;

  /// 이 건물에서 제보된 방 구조들. 한 건물에 원룸과 2룸이 섞여 있을 수 있어
  /// 다수결로 하나만 고르지 않고 **전부** 들고 있는다 — "2룸 찾기"를 눌렀을 때
  /// 2룸 제보가 하나라도 있으면 후보로 보여줘야 한다.
  final Set<HousingRoomType> roomTypes;

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
  });

  static const empty = HousingSummary(
    reportCount: 0,
    medianDeposit: null,
    medianRent: null,
    topFeatures: [],
    latestReport: null,
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
      // 짝수 개면 가운데 두 값의 평균.
      return values.length.isOdd
          ? values[mid]
          : ((values[mid - 1] + values[mid]) / 2).round();
    }

    final featureCount = <String, int>{};
    for (final r in list) {
      for (final f in r.features) {
        featureCount[f] = (featureCount[f] ?? 0) + 1;
      }
    }
    final sortedFeatures = featureCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 이름은 다수결로 정한다. 한 사람이 잘못 지목해도 여러 명이 맞게 고르면
    // 바로잡히고, 아무도 안 골랐으면 이름 없이 남는다.
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

    // 관리비는 적은 사람만 적는다 — null을 0으로 치면 중앙값이 아래로
    // 끌려가므로, 적어 낸 제보만 모아 중앙값을 낸다.
    final fees = list
        .map((r) => r.maintenanceFee)
        .whereType<int>()
        .toList();

    return HousingSummary(
      reportCount: list.length,
      medianDeposit: median(list.map((r) => r.deposit).toList()),
      medianRent: median(list.map((r) => r.monthlyRent).toList()),
      medianMaintenance: median(fees),
      // 제보마다 먼저 더한 뒤 중앙값. 두 중앙값을 더하면 안 되는 이유는
      // medianMonthlyTotal 문서 주석 참고.
      medianMonthlyTotal: median(list.map((r) => r.monthlyTotal).toList()),
      roomTypes: list.map((r) => r.roomType).whereType<HousingRoomType>().toSet(),
      topFeatures: sortedFeatures.take(5).map((e) => e.key).toList(),
      allFeatures: featureCount.keys.toSet(),
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
