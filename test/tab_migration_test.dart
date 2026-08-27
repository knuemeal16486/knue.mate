import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  test('기존 6탭(더보기 포함) 저장값 → 더보기 제거된 5탭 구조', () {
    // 'more'는 더 이상 AppTab에 없는 이름 — 옛 저장값에 남아있어도 조용히 무시되는지 확인.
    final result = PreferencesService.migrateTabOrder(
        ['home', 'meal', 'bus', 'map', 'more', 'settings']);
    expect(result.first, AppTab.home);
    expect(result.length, 5);
    expect(result, contains(AppTab.settings));
    expect(result.indexOf(AppTab.meal), lessThan(result.indexOf(AppTab.bus)));
    expect(result.indexOf(AppTab.bus), lessThan(result.indexOf(AppTab.map)));
  });

  test('run은 하단 탭에서 제외(캠퍼스런 화면으로만 진입)', () {
    final result = PreferencesService.migrateTabOrder(
        ['meal', 'bus', 'run', 'map']);
    expect(result, isNot(contains(AppTab.run)));
  });

  test('설정 순서는 사용자가 옮긴 자리 그대로 유지된다', () {
    final result = PreferencesService.migrateTabOrder(
        ['home', 'settings', 'meal', 'bus', 'map']);
    expect(result, [
      AppTab.home,
      AppTab.settings,
      AppTab.meal,
      AppTab.bus,
      AppTab.map,
    ]);
  });

  test('알 수 없는 탭 이름은 무시', () {
    final result = PreferencesService.migrateTabOrder(['meal', 'ghost']);
    expect(result, contains(AppTab.home));
    expect(result, contains(AppTab.meal));
    expect(result, contains(AppTab.settings));
  });

  test('신규 사용자(빈 저장값)는 기본 순서', () {
    final result = PreferencesService.migrateTabOrder([]);
    expect(result, [
      AppTab.home,
      AppTab.meal,
      AppTab.bus,
      AppTab.map,
      AppTab.settings,
    ]);
  });
}
