import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  test('기존 5탭 저장값 → 6탭 구조(설정 백필)', () {
    final result = PreferencesService.migrateTabOrder(
        ['home', 'meal', 'bus', 'map', 'more']);
    expect(result.first, AppTab.home);
    expect(result.last, AppTab.settings); // 설정이 맨 뒤
    expect(result[result.length - 2], AppTab.more); // 더보기가 뒤에서 2번째
    expect(result, contains(AppTab.settings)); // 백필됨
    expect(result.indexOf(AppTab.meal), lessThan(result.indexOf(AppTab.bus)));
    expect(result.indexOf(AppTab.bus), lessThan(result.indexOf(AppTab.map)));
  });

  test('run은 하단 탭에서 제외(더보기 내 캠퍼스런으로만 진입)', () {
    final result = PreferencesService.migrateTabOrder(
        ['meal', 'bus', 'run', 'map']);
    expect(result, isNot(contains(AppTab.run)));
  });

  test('알 수 없는 탭 이름은 무시', () {
    final result = PreferencesService.migrateTabOrder(['meal', 'ghost']);
    expect(result, contains(AppTab.home));
    expect(result, contains(AppTab.meal));
    expect(result, contains(AppTab.more));
    expect(result, contains(AppTab.settings));
  });

  test('신규 사용자(빈 저장값)는 기본 순서', () {
    final result = PreferencesService.migrateTabOrder([]);
    expect(result, [
      AppTab.home,
      AppTab.meal,
      AppTab.bus,
      AppTab.map,
      AppTab.more,
      AppTab.settings,
    ]);
  });
}
