import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

HousingReport _r(int deposit, int rent, {int? fee, HousingRoomType? type, List<String> features = const []}) =>
    HousingReport(
      buildingId: 'b',
      deposit: deposit,
      monthlyRent: rent,
      maintenanceFee: fee,
      roomType: type,
      features: features,
      reportedAt: DateTime(2026, 9, 1),
    );

HousingBuildingOverride _prices(List<HousingPriceEntry> prices) =>
    HousingBuildingOverride(buildingId: 'b', name: '', zone: HousingZone.gateBack, prices: prices);

void main() {
  group('방 하나하나로 판정한다', () {
    // 원룸 35·투룸 55가 섞인 건물 — 평균으로 보면 "원룸, 월 40 이하"에서 빠졌다.
    final mixed = HousingSummary.from([
      _r(300, 35, type: HousingRoomType.oneRoom),
      _r(300, 35, type: HousingRoomType.oneRoom),
      _r(500, 55, type: HousingRoomType.twoRoom),
    ]);

    test('원룸이 조건에 맞으면 걸리고, 가장 싼 맞는 방을 알려준다', () {
      final r = evaluateHousingFilter(
        mixed,
        null,
        const HousingFilter(roomTypes: {HousingRoomType.oneRoom}, maxMonthly: 40, includeMaintenance: false),
      );
      expect(r.verdict, HousingFilterVerdict.match);
      expect(r.best?.roomType, HousingRoomType.oneRoom);
      expect(r.best?.monthlyRent, 35);
    });

    test('방 구조·금액은 같은 방이 모두 만족해야 한다', () {
      // 투룸이 있고(55), 월 40 이하 방도 있지만(원룸) "투룸이면서 40 이하"는 없다.
      final r = evaluateHousingFilter(
        mixed,
        null,
        const HousingFilter(roomTypes: {HousingRoomType.twoRoom}, maxMonthly: 40, includeMaintenance: false),
      );
      expect(r.verdict, HousingFilterVerdict.miss);
    });
  });

  group('개발자가 확인한 시세도 쓴다', () {
    test('제보가 없어도 확인 시세로 걸린다', () {
      final r = evaluateHousingFilter(
        null,
        _prices(const [HousingPriceEntry(deposit: 200, monthlyRent: 33, maintenanceFee: 5, roomType: '원룸', asOf: '2026-09')]),
        const HousingFilter(maxMonthly: 40),
      );
      expect(r.verdict, HousingFilterVerdict.match);
      expect(r.best?.fromReports, isFalse);
      expect(r.best?.monthly(withMaintenance: true), 38);
    });

    test('관리비 포함 여부로 결과가 바뀐다', () {
      final o = _prices(const [HousingPriceEntry(deposit: 200, monthlyRent: 35, maintenanceFee: 8)]);
      expect(evaluateHousingFilter(null, o, const HousingFilter(maxMonthly: 40)).verdict, HousingFilterVerdict.miss);
      expect(
        evaluateHousingFilter(null, o, const HousingFilter(maxMonthly: 40, includeMaintenance: false)).verdict,
        HousingFilterVerdict.match,
      );
    });
  });

  group('모름', () {
    test('시세가 하나도 없으면 "모름" — 켜야 결과에 들어간다', () {
      const f = HousingFilter(maxMonthly: 40);
      final r = evaluateHousingFilter(null, null, f);
      expect(r.verdict, HousingFilterVerdict.unknown);
      expect(housingPassesFilter(r.verdict, f), isFalse);
      expect(housingPassesFilter(r.verdict, f.copyWith(includeUnknown: true)), isTrue);
    });

    test('금액은 맞는데 방 구조를 모르는 시세만 있으면 "모름"', () {
      final r = evaluateHousingFilter(
        null,
        _prices(const [HousingPriceEntry(deposit: 200, monthlyRent: 30)]),
        const HousingFilter(roomTypes: {HousingRoomType.oneRoom}, maxMonthly: 40),
      );
      expect(r.verdict, HousingFilterVerdict.unknown);
    });

    test('특징 조건은 제보가 있어야 판단한다', () {
      final withReports = HousingSummary.from([_r(300, 35, features: const ['풀옵션'])]);
      const f = HousingFilter(requiredFeatures: {'풀옵션'});
      expect(evaluateHousingFilter(withReports, null, f).verdict, HousingFilterVerdict.match);
      expect(
        evaluateHousingFilter(null, _prices(const [HousingPriceEntry(deposit: 1, monthlyRent: 1)]), f).verdict,
        HousingFilterVerdict.unknown,
      );
    });
  });

  test('방 구조 글자 → 구조', () {
    expect(roomTypeFromText('원룸'), HousingRoomType.oneRoom);
    expect(roomTypeFromText('1.5룸'), HousingRoomType.onePointFive);
    expect(roomTypeFromText('투룸'), HousingRoomType.twoRoom);
    expect(roomTypeFromText('2룸'), HousingRoomType.twoRoom);
    expect(roomTypeFromText('3룸 이상'), HousingRoomType.threeRoomPlus);
    expect(roomTypeFromText(''), isNull);
    expect(roomTypeFromText('복층'), isNull);
    // 편집 창의 칩이 저장하는 값(구조 이름)은 그대로 되읽힌다.
    for (final t in HousingRoomType.values) {
      expect(roomTypeFromText(t.label), t);
    }
  });

  test('관리비를 아무도 안 적은 방 구조는 관리비 0(모름) — 3만원을 지어 넣지 않는다', () {
    final s = HousingSummary.from([_r(300, 35, type: HousingRoomType.oneRoom)]);
    expect(s.roomPricingMap[HousingRoomType.oneRoom]?.maintenanceFee, 0);
    expect(s.roomPricingMap[HousingRoomType.oneRoom]?.totalMonthly, 35);
  });
}
