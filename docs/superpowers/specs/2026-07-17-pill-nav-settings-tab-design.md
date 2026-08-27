# 원본 느낌 복원 (1차) — pill 하단바 + 설정 탭 복귀 설계

날짜: 2026-07-17
상태: 사용자 승인 완료

## 목표

Phase 1 재구조화 과정에서 사라진 KNUE Mate 원본(2026-03, `880efcf`)의 "느낌"을 되살린다. 이번 1차 범위는 (A) 시그니처였던 pill 스타일 하단 네비게이션 복원과, (B) 원본에서 하단 탭 중 하나였던 설정을 하단 탭으로 복귀시키는 것이다. 홈 헤더 리디자인은 보류(후속).

## 범위

### 포함
- pill 스타일 하단 네비게이션 (3월 원본 `_BottomNavBar` 패턴)
- 설정을 하단 탭으로 복귀 (6탭: 홈·식단·버스·지도·더보기·설정, 설정이 맨 오른쪽)
- 더보기 화면에서 "설정" 타일 제거 (중복 제거)

### 제외 (이번 범위 아님)
- 홈 화면 브랜디드 리치 헤더 (후속 논의)
- 5탭 구조 자체의 기능 변경 (탭 목록만 6개로)
- 3월 원본의 앱 전환(app-switch) 다이얼로그 모델

## 핵심 결정 사항

| 결정 | 선택 | 근거 |
|---|---|---|
| 하단바 스타일 | pill (선택 탭만 컬러 알약+라벨, 나머지 아이콘) | 원본의 시그니처 비주얼 |
| 설정 위치 | 하단 탭 최우측 | 3월 원본 "환경설정 마지막" 느낌, 사용자가 키포인트로 지목 |
| 더보기 위치 | 설정 바로 왼쪽 (뒤에서 2번째) | 오버플로 메뉴는 우측 유지하되 설정을 최우측으로 |
| 설정 중복 | 더보기 목록에서 설정 타일 제거 | 하단 탭과 중복 방지 |

## 화면/코드 구조

### 하단 네비게이션 (`root_screen.dart`)
현재 표준 Material `BottomNavigationBar` + `BackdropFilter` 블러 바를 3월 원본 pill 패턴으로 교체:
- 컨테이너: `Theme.of(context).cardColor` 배경 + 부드러운 그림자(`BoxShadow(color: black.withValues(alpha: 0.05), blurRadius: 20)`), `SafeArea` + 좌우 패딩
- `Row(mainAxisAlignment: spaceAround)`로 탭 항목 배치
- 각 항목(`GestureDetector`, `HitTestBehavior.opaque`):
  - **선택**: `themeColor.value` 채운 둥근 사각(`borderRadius: 20`) 안에 아이콘(흰색) + 라벨(흰색 볼드)
  - **비선택**: 아이콘만 (다크=white38 / 라이트=grey)
  - 라벨은 `Flexible` + `overflow: ellipsis`로 감싸 좁은 화면 오버플로 방지
- 탭 목록/순서/라우팅은 기존 `PreferencesService.tabOrder` + `_getScreenForTab`(이미 `AppTab.settings` 케이스 존재) 재사용

### 탭 구성/마이그레이션 (`constants.dart`)
- `navigableTabs`와 기본 `tabOrder`에 `AppTab.settings` 추가 → `[home, meal, bus, map, more, settings]`
- `migrateTabOrder`의 고정 규칙 변경: 기존 "more는 항상 마지막" → **마지막 2개를 `[…, more, settings]`로 고정** (more와 settings를 제거 후 순서대로 재추가). home은 없으면 맨 앞 삽입, 나머지 navigableTabs는 없으면 백필. 기존 사용자(설정 미보유)는 백필+고정으로 설정이 자동으로 맨 뒤에 추가됨.
- 저장 키 `tab_order_v2` 유지 (구조 확장이지 스키마 변경 아님 — 기존 저장값도 마이그레이션이 흡수)

### 더보기 (`more_screen.dart`)
- "앱" 섹션의 "설정" 타일 제거 (하단 탭으로 이동했으므로)
- 설정 제거 후 "앱" 섹션에는 디버그 빌드 전용 "키워드 알림 즉시 테스트" 타일만 남음 → 릴리스에서 섹션이 비지 않도록 정리(디버그 타일이 없으면 "앱" 섹션 헤더도 숨김). 버전 텍스트(숨김 관리자 7탭 진입)는 그대로 유지
- 나머지 "기능" 타일(캠퍼스런·교직원 연락처·청람공지·청람일정)은 변경 없음

## 데이터/호환성

- 기존 사용자의 저장된 `tab_order_v2`는 `migrateTabOrder`가 흡수: 설정이 없으면 백필로 맨 뒤 추가, 홈은 맨 앞 보장, 마지막 2개는 more/settings로 정렬
- 시작 화면 지정 기능(기존)은 그대로 — 설정을 시작 화면으로 지정한 사용자는 없었으므로 회귀 없음
- `AppTab.run`은 여전히 enum에만 존재(더보기 내 캠퍼스런으로 진입), navigableTabs 미포함 유지

## 검증

- 단위: `migrateTabOrder` 테스트 갱신 — (a) 기본/신규 사용자 → `[home, meal, bus, map, more, settings]`, (b) 기존 5탭 저장값 → 설정이 백필되어 맨 뒤, (c) more/settings 마지막 2개 고정 순서 확인
- 스모크: 기존 home/more/root 관련 테스트 통과 유지 (more에서 "설정" 타일 사라지는 것 외 회귀 없음 — more 스모크가 "설정" 텍스트를 단언하면 그 단언 제거/수정)
- 정적: `flutter analyze` error/warning 0, info 기존 172 수준 이하, 새 opacity는 `.withValues(alpha:)`
- 육안: 웹 빌드로 pill 하단바(선택 알약 확장/비선택 아이콘), 6탭 가로 여백, 다크모드, 설정 탭 진입, 더보기에서 설정 사라짐 확인

## 후속 (별도)

- 홈 화면 브랜디드 리치 헤더 (오늘 브리핑을 컬러 헤더 히어로로)
