import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

void main() {
  group('상가 가게 목록', () {
    test('저장했다 되읽으면 그대로 — 이름 없는 가게는 버린다', () {
      const o = HousingBuildingOverride(
        buildingId: 'mall',
        name: '교원상가',
        zone: HousingZone.gateBack,
        shops: [
          HousingShop(name: '메이커피', category: '카페', floor: '1층'),
          HousingShop(name: 'CU'),
        ],
      );
      final back = HousingBuildingOverride.fromMap('mall', o.toFirestore())!;
      expect(back.shops, o.shops);
      expect(back.shops.first.detail, '1층 · 카페');
      expect(HousingShop.listFrom([
        {'name': ' '},
        {'category': '카페'},
        'x',
        {'name': '빵집'},
      ]).map((s) => s.name), ['빵집']);
    });

    test('이름 없이 가게만 적은 문서도 읽힌다', () {
      final m = const HousingBuildingOverride(
        buildingId: 'b',
        name: '',
        zone: HousingZone.gateBack,
        shops: [HousingShop(name: 'PC방')],
      ).toFirestore();
      expect(HousingBuildingOverride.fromMap('b', m)?.shops.single.name, 'PC방');
    });

    test('가게 이름·업종으로 건물을 찾는다(지운 건물은 빼고)', () {
      bool contains(String text, String q) => text.contains(q);
      final overrides = {
        'a': const HousingBuildingOverride(
          buildingId: 'a',
          name: '교원상가',
          zone: HousingZone.gateBack,
          shops: [HousingShop(name: '메이커피', category: '카페'), HousingShop(name: '김밥천국', category: '식당')],
        ),
        'b': const HousingBuildingOverride(
          buildingId: 'b',
          name: '',
          zone: HousingZone.gateBack,
          isDeleted: true,
          shops: [HousingShop(name: '메이커피 2호점')],
        ),
      };
      expect(findShops(overrides, '메이', contains).map((r) => r.$1), ['a']);
      expect(findShops(overrides, '식당', contains).single.$2.name, '김밥천국');
      expect(findShops(overrides, '  ', contains), isEmpty);
    });
  });

  group('직접 입력한 시세', () {
    test('저장했다 되읽으면 그대로 — 금액이 없는 항목은 버린다', () {
      const o = HousingBuildingOverride(
        buildingId: 'x',
        name: '',
        zone: HousingZone.gateBack,
        prices: [
          HousingPriceEntry(deposit: 300, monthlyRent: 35, maintenanceFee: 5, roomType: '원룸', asOf: '2026-09'),
        ],
      );
      final back = HousingBuildingOverride.fromMap('x', o.toFirestore())!;
      expect(back.prices, o.prices);
      expect(back.prices.single.priceText, '보증금 300 / 월세 35 (관리비 5)');
      expect(HousingPriceEntry.listFrom([
        {'deposit': 100},
        {'deposit': 200, 'monthlyRent': 30},
      ]).single.deposit, 200);
    });

    test('최근 시세부터 — 시기를 안 적은 건 입력 순서대로 뒤에', () {
      const a = HousingPriceEntry(deposit: 1, monthlyRent: 1, asOf: '2025-03');
      const b = HousingPriceEntry(deposit: 2, monthlyRent: 2);
      const c = HousingPriceEntry(deposit: 3, monthlyRent: 3, asOf: '2026-09');
      const d = HousingPriceEntry(deposit: 4, monthlyRent: 4);
      expect(sortedPriceEntries([a, b, c, d]), [c, a, b, d]);
    });
  });
}
