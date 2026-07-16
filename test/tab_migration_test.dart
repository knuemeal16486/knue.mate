import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  test('기존 5탭 저장값 → 새 5탭 구조 마이그레이션', () {
    final result = PreferencesService.migrateTabOrder(
        ['meal', 'bus', 'run', 'map', 'settings']);
    expect(result.first, AppTab.home); // 홈이 맨 앞에 삽입
    expect(result.last, AppTab.more); // 더보기가 맨 뒤에
    expect(result, isNot(contains(AppTab.run))); // run/settings는 더보기로 흡수
    expect(result, isNot(contains(AppTab.settings)));
    // 기존 사용자의 식단→버스→지도 상대 순서 유지
    expect(result.indexOf(AppTab.meal), lessThan(result.indexOf(AppTab.bus)));
    expect(result.indexOf(AppTab.bus), lessThan(result.indexOf(AppTab.map)));
  });

  test('알 수 없는 탭 이름은 무시', () {
    final result = PreferencesService.migrateTabOrder(['meal', 'ghost']);
    expect(result, contains(AppTab.home));
    expect(result, contains(AppTab.meal));
    expect(result, contains(AppTab.more));
  });

  test('신규 사용자(빈 저장값)는 기본 순서', () {
    final result = PreferencesService.migrateTabOrder([]);
    expect(result,
        [AppTab.home, AppTab.meal, AppTab.bus, AppTab.map, AppTab.more]);
  });
}
