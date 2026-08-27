# pill 하단바 + 설정 탭 복귀 Implementation Plan

> **For agentic workers:** 소규모 UI 변경 — 3개 파일 + 2개 테스트. 인라인 실행(executing-plans) 권장.

**Goal:** 3월 원본 pill 스타일 하단 네비게이션을 복원하고, 설정을 하단 탭 최우측으로 복귀시킨다.

**Architecture:** `constants.dart`의 탭 목록/마이그레이션에 settings 추가 → `root_screen.dart`의 Material 하단바를 pill 패턴으로 교체 → `more_screen.dart`에서 설정 타일 제거. 라우팅(`_getScreenForTab`)은 이미 `AppTab.settings` 케이스 보유 — 변경 불필요.

**Tech Stack:** Flutter, StatefulWidget+setState, SharedPreferences

## Global Constraints
- `flutter analyze` error/warning 0, info ≤ 172
- 새 opacity는 `.withValues(alpha:)` (`.withOpacity` 금지)
- StatefulWidget+setState, 신규 라이브러리 금지
- UI 한국어
- 커밋 끝에 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: 탭 목록 + 마이그레이션에 설정 추가

**Files:** Modify `lib/constants.dart`, `test/tab_migration_test.dart`

- [ ] **Step 1:** `test/tab_migration_test.dart` 를 새 기대값으로 교체:

```dart
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
```

- [ ] **Step 2:** Run `flutter test test/tab_migration_test.dart` → FAIL (settings 미포함)

- [ ] **Step 3:** `lib/constants.dart` 수정 — 기본 `tabOrder`(520-526행)에 `AppTab.settings,` 를 `AppTab.more,` 다음에 추가:

```dart
  static final ValueNotifier<List<AppTab>> tabOrder = ValueNotifier([
    AppTab.home,
    AppTab.meal,
    AppTab.bus,
    AppTab.map,
    AppTab.more,
    AppTab.settings,
  ]);
```

`navigableTabs`(538-544행)에도 동일하게 추가:

```dart
  /// 하단 탭에 배치 가능한 탭 (run은 더보기 내 캠퍼스런으로만 진입)
  static const List<AppTab> navigableTabs = [
    AppTab.home,
    AppTab.meal,
    AppTab.bus,
    AppTab.map,
    AppTab.more,
    AppTab.settings,
  ];
```

`migrateTabOrder`의 고정 로직(567-569행)을 "more 마지막" → "more·settings 마지막 2개 고정"으로 교체:

```dart
    // 더보기·설정을 항상 마지막 2개로 고정 (설정이 최우측)
    result.remove(AppTab.more);
    result.remove(AppTab.settings);
    result.add(AppTab.more);
    result.add(AppTab.settings);
    return result;
```

- [ ] **Step 4:** Run `flutter test test/tab_migration_test.dart` → PASS

- [ ] **Step 5:** `flutter analyze --no-pub 2>&1 | tail -3` → error/warning 0

- [ ] **Step 6:** Commit:
```bash
git add lib/constants.dart test/tab_migration_test.dart
git commit -m "feat: 설정을 하단 탭으로 복귀 (6탭, more·settings 마지막 고정)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: pill 스타일 하단 네비게이션

**Files:** Modify `lib/root_screen.dart`

- [ ] **Step 1:** `build()`의 `bottomNavigationBar:`(100-142행) 전체를 pill 패턴으로 교체:

```dart
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (int i = 0; i < tabs.length; i++)
                  _buildNavItem(tabs[i], i, color, isDark),
              ],
            ),
          ),
        ),
      ),
```

주의: `build()` 상단에서 `themeColor` 색을 `color`로 받도록 `ValueListenableBuilder<Color>(themeColor)` 래핑이 필요하다. 현재 build은 `theme.primaryColor`를 pill 색으로 쓰는데, 앱 전역 포인트 색은 `themeColor.value`이므로 이를 `color`로 사용한다. build 시그니처를 다음처럼 조정:

```dart
  @override
  Widget build(BuildContext context) {
    final tabs = PreferencesService.tabOrder.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = themeColor.value; // 전역 포인트 색
    ...
```

(간단히 `themeColor.value`를 직접 읽어도 됨 — root은 이미 `tabOrder`/테마 변경 시 재빌드되며, 색 변경 즉시 반영이 필수는 아님. 기존 코드가 `theme.primaryColor`를 쓰고 있었으므로 `theme.primaryColor`를 그대로 pill 색으로 써도 동작상 동일. 둘 중 기존 관행에 맞춰 `theme.primaryColor` 사용 가능.)

- [ ] **Step 2:** `_RootNavigationScreenState`(또는 State 클래스) 안에 `_buildNavItem` 추가 (3월 `_BottomNavBar._item` 이식):

```dart
  Widget _buildNavItem(AppTab tab, int index, Color color, bool isDark) {
    final isSel = index == _currentIndex;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 22,
              color: isSel
                  ? Colors.white
                  : (isDark ? Colors.white38 : Colors.grey),
            ),
            if (isSel) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3:** 사용하지 않게 된 import 정리: `dart:ui`(BackdropFilter용)가 더 이상 안 쓰이면 제거. `flutter analyze`가 unused import을 info로 잡으면 제거.

- [ ] **Step 4:** Run `flutter analyze --no-pub 2>&1 | tail -5` → error/warning 0, info ≤ 172. `flutter test` 전체 통과(기존 root 관련 스모크 유지).

- [ ] **Step 5:** Commit:
```bash
git add lib/root_screen.dart
git commit -m "feat: pill 스타일 하단 네비게이션 복원 (3월 원본 느낌)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 더보기에서 설정 타일 제거

**Files:** Modify `lib/more_screen.dart`, `test/more_screen_test.dart`

- [ ] **Step 1:** `test/more_screen_test.dart`에서 설정 단언(11행 `expect(find.text('설정'), findsOneWidget);`) 제거. 캠퍼스런/교직원 연락처 단언은 유지.

- [ ] **Step 2:** `lib/more_screen.dart`의 "앱" 섹션(98-129행 `_SectionHeader(title: "앱")` + 그 `_MoreTileGroup`)을 정리:
  - "설정" `_MoreTile`(103-112행) 제거
  - 설정 제거 후 그룹에는 디버그 타일만 남으므로, "앱" 섹션 헤더 + 그룹 전체를 `if (kDebugMode) ...[ ... ]`로 감싸 릴리스에서 빈 섹션이 뜨지 않게 함. 디버그 타일의 `showDivider`는 `false`로.
  - 버전 텍스트(131-139행, 숨김 관리자 7탭 진입)는 그대로 유지

구체적으로 "앱" 섹션을 다음으로 교체:

```dart
              if (kDebugMode) ...[
                const SizedBox(height: 24),
                _SectionHeader(title: "앱", isDark: isDark),
                const SizedBox(height: 8),
                _MoreTileGroup(
                  isDark: isDark,
                  children: [
                    _MoreTile(
                      icon: Icons.bug_report_outlined,
                      iconColor: Colors.redAccent,
                      title: "키워드 알림 즉시 테스트",
                      trailing: _testingAlert
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _runKeywordAlertTest,
                      showDivider: false,
                    ),
                  ],
                ),
              ],
```

(설정으로 진입하던 `SettingsPage` import가 더 이상 안 쓰이면 `flutter analyze` info에 따라 정리. 단, 다른 곳에서 쓰면 유지.)

- [ ] **Step 3:** Run `flutter test test/more_screen_test.dart` → PASS. `flutter test` 전체 통과.

- [ ] **Step 4:** `flutter analyze --no-pub 2>&1 | tail -3` → error/warning 0.

- [ ] **Step 5:** Commit:
```bash
git add lib/more_screen.dart test/more_screen_test.dart
git commit -m "feat: 더보기에서 설정 타일 제거 (하단 탭으로 이동됨)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 웹 육안 검증

- [ ] **Step 1:** `flutter test` 전체 PASS, `flutter analyze` error/warning 0.
- [ ] **Step 2:** 웹 빌드로 확인: (a) pill 하단바 — 선택 탭이 컬러 알약으로 확장+라벨, 비선택 아이콘만, (b) 6탭(홈·식단·버스·지도·더보기·설정) 가로 여백 정상, (c) 설정 탭 진입 → SettingsPage, (d) 더보기에서 "설정" 사라짐, (e) 다크모드, (f) 기존 탭(식단/버스/지도) 회귀 없음.

## Self-Review 체크
- Spec coverage: pill 하단바(T2), 설정 하단 탭 복귀+마이그레이션(T1), 더보기 설정 제거(T3), 검증(T4) — 전 항목 커버
- Type consistency: `AppTab.settings`는 enum 기존 멤버, `_getScreenForTab` 케이스 존재. `migrateTabOrder`는 순수 함수(T1 테스트=구현). `_buildNavItem(AppTab, int, Color, bool)`는 T2 내부 일관
