# 홈 화면 리디자인 (브랜디드 히어로 헤더 + 컬러 액센트 카드) 설계

날짜: 2026-07-17
상태: 사용자 승인 완료 (비주얼 컴패니언으로 A+B 조합 확정)

## 목표

밋밋한 "홈" AppBar + 검은 배경의 동일한 회색 카드 나열을, 브랜디드 그라디언트 히어로 헤더 + 종류별 컬러 액센트 카드로 리디자인해 첫인상과 시각 위계를 개선한다. 기능·데이터·탭 구조는 변경하지 않는다.

## 범위

### 포함
- 홈 상단: 플레인 `AppBar("홈")` 제거 → themeColor 그라디언트 히어로 헤더(둥근 하단 모서리). 날짜 + 큰 인사말 + "오늘 브리핑"(식단·버스) 반투명 타일 2개를 헤더 안으로 이동
- 홈 정보 카드(키워드 알림·즐겨찾는 공지·다가오는 일정·동아리 공연·행사): 왼쪽 컬러 액센트 띠 + 같은 색 아이콘 칩

### 제외
- 홈 외 화면 (식단/버스/공지/캘린더/더보기 등) — 변경 없음
- 카드의 데이터 로직/탭 이동 동작 — 기존 그대로

## 통일성 제약 (사용자 명시)

- **폰트**: 앱 전역 `GoogleFonts.notoSansKrTextTheme` 사용 → 홈 위젯은 `fontFamily`를 명시하지 않고 테마 상속(자동 통일). 새 폰트 도입 금지
- **아이콘**: 이모지 금지, 기존 홈 카드가 쓰는 Material 아이콘 유지(키워드=`notifications_active_outlined`, 공지=`campaign_outlined`, 일정=`event_note_outlined`, 동아리=`celebration_outlined`, 식단=`restaurant_menu_rounded`, 버스=`directions_bus_rounded`)
- **색**: 하드코딩 파랑 금지. 헤더 그라디언트·포인트는 `themeColor.value` 기반 → 설정에서 앱 색 변경 시 헤더도 함께 변경. 카드 액센트 색만 종류 구분용 고정 팔레트 사용
- **카드 스타일**: 기존 `_SectionCard`의 `Theme.of(context).cardColor` 배경·radius(16)·테두리 관례 유지, 다크모드 대응
- 새 opacity는 `.withValues(alpha:)`

## 화면 구조 (`home_screen.dart`)

### 히어로 헤더 (`_buildHeroHeader`, 기존 `_buildTodayBriefingHeader` 대체)
- 전체 폭 컨테이너, `themeColor` 그라디언트(`LinearGradient`: color → color 약간 어둡게), 하단 모서리 `Radius.circular(30)`
- 상단 `SafeArea`(top) 여백으로 상태바 아래 배치 (AppBar 제거하므로)
- 내용(흰색 텍스트): 날짜(`M월 d일 EEEE`, ko_KR) + 인사말(`_greeting`, 크게 w800) + 가로 2타일
  - 식단 타일: 반투명 흰색(`Colors.white.withValues(alpha: 0.16)`) 배경, `restaurant_menu_rounded` + `_nextMealType.label` + 메뉴 상위 요약. 탭 → `switchTab(AppTab.meal)`
  - 버스 타일: 동일 스타일, `directions_bus_rounded` + "다음 버스" + `_busLabel`. 탭 → `switchTab(AppTab.bus)`
  - 로딩/실패/빈 상태는 흰색 계열로 헤더 위에서 읽히게 처리
- 기존 `_buildMealBriefCard`/`_buildBusBriefCard`/`_BriefCard`는 헤더용 흰색 타일 위젯(`_HeroTile`)으로 대체

### 정보 카드 (`_SectionCard`에 액센트 파라미터 추가)
- `_SectionCard`에 `accentColor` 추가: 카드 왼쪽에 4px 컬러 띠 + 헤더의 아이콘을 `accentColor` 색 아이콘 칩(둥근 사각 배경 `accentColor.withValues(alpha: 0.12)`)으로
- 각 카드 호출부에 액센트 색 지정:
  - 키워드 알림: `Color(0xFFF59E0B)` (amber)
  - 즐겨찾는 공지: `Color(0xFFFB923C)` (orange)
  - 다가오는 일정: `Color(0xFF8B5CF6)` (violet)
  - 동아리 공연·행사: `Color(0xFFEC4899)` (pink)
- 카드 내부 콘텐츠·"전체 보기"·데이터는 기존 그대로

### build() 구조
- `Scaffold`에서 `appBar` 제거. `body`는 `SingleChildScrollView(padding: zero)` →
  `Column([ _buildHeroHeader(...), Padding(fromLTRB(12,14,12,24), Column([정보 카드 4개])) ])`
- 기존 `ValueListenableBuilder<Color>(themeColor)` 래핑 유지

## 검증

- 기존 `test/home_screen_test.dart` 스모크(렌더 크래시 없음) 유지 — AppBar 제거로 "홈" 텍스트 단언이 있으면 헤더 인사말/다른 안정 요소로 대체
- `flutter analyze` error/warning 0, info ≤ 기존 수준, `.withOpacity` 미사용
- 웹 육안: 헤더 그라디언트·둥근 모서리·오늘 브리핑 타일·카드 컬러 액센트·다크모드·themeColor 변경 시 헤더 색 반영·헤더/카드 탭 이동 동작

## 후속 (별도)
- 필요 시 헤더 스크롤 시 접힘(SliverAppBar) 고도화 — 이번엔 단순 스크롤로 시작
