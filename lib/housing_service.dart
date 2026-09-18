import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'housing_iso.dart' show BaseBuilding;
import 'housing_model.dart';
import 'offline_cache.dart';

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

  const HousingReport({
    required this.buildingId,
    required this.deposit,
    required this.monthlyRent,
    required this.features,
    required this.reportedAt,
    this.maintenanceFee,
    this.oneRoomId,
    this.id,
  });

  Map<String, dynamic> toFirestore() => {
        'buildingId': buildingId,
        'deposit': deposit,
        'monthlyRent': monthlyRent,
        if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
        if (oneRoomId != null) 'oneRoomId': oneRoomId,
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

  const HousingBuildingOverride({
    required this.buildingId,
    required this.name,
    required this.zone,
    this.builtYear,
    this.note,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'zone': zone.name,
        if (builtYear != null) 'builtYear': builtYear,
        if (note != null && note!.isNotEmpty) 'note': note,
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
    );
  }

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

  /// 많이 언급된 특징 순.
  final List<String> topFeatures;

  /// 가장 최근 제보 시점.
  final DateTime? latestReport;

  /// 가장 많이 지목된 원룸 이름([OneRoomName.id]).
  /// 건축물대장에 원룸 이름이 없어 학생 제보로만 채워진다.
  final String? oneRoomId;

  const HousingSummary({
    required this.reportCount,
    required this.medianDeposit,
    required this.medianRent,
    required this.topFeatures,
    required this.latestReport,
    this.oneRoomId,
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

    return HousingSummary(
      reportCount: list.length,
      medianDeposit: median(list.map((r) => r.deposit).toList()),
      medianRent: median(list.map((r) => r.monthlyRent).toList()),
      topFeatures: sortedFeatures.take(5).map((e) => e.key).toList(),
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
const List<String> kHousingFeatures = [
  '풀옵션',
  '복층',
  '분리형',
  '주차 가능',
  '엘리베이터',
  '신축급',
  '방음 좋음',
  '벌레 적음',
  '햇빛 잘 듦',
  '관리비 저렴',
  '학교와 가까움',
  '조용함',
];
