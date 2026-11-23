# 공지·버스 홈 위젯 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱을 열지 않고 홈 화면에서 학교 출발 버스 다음 차와 즐겨찾기 게시판 최신 글을 보는 위젯을 Android·iOS에 더한다.

**Architecture:** 규칙(다음 차 고르기, 게시판별 최신 글 고르기, 링크 허용)은 Dart 순수 함수(`lib/home_widgets.dart`)로 두고 테스트한다. 앱은 home_widget 저장소에 JSON을 넣고, 위젯(Swift·Kotlin)은 같은 규칙을 옮겨 그린다. 버스는 위젯이 시각마다 스스로 넘어가고, iOS 공지 위젯은 GitHub Pages 수집 파일을 직접 받는다.

**Tech Stack:** Flutter `home_widget ^0.8.1`, SwiftUI WidgetKit(iOS 15+, 기존 `MealWidget` 확장), Android `AppWidgetProvider` + RemoteViews + `AlarmManager`.

**Spec:** `docs/superpowers/specs/2026-11-23-notice-bus-widgets-design.md`

## Global Constraints

- 위젯은 학교 서버(knue.ac.kr 계열)에 요청하지 않는다. 받는 곳은 `notice_feed_base`(기본 `https://knuemeal16486.github.io/knue.mate/feed`)뿐.
- 위젯은 Firestore를 읽거나 쓰지 않는다.
- 비상 직접 모드(`NoticeFeedSettings.direct == true`)면 iOS 위젯은 자체 받기를 하지 않는다.
- 지난 버스 시각을 "다음 차"로 그리지 않는다 — 그리는 순간에도 다시 거른다.
- 평일/주말: 토·일 → `holiday`, 그 밖 → `weekday`. 913 경유 시각은 요일 구분 없음.
- 공지 대상 게시판: 저장값(`fav_boards`) 없음 → `['대학소식','학사공지']`(PreferencesService.loadSettings와 같음), 빈 목록 → `kDefaultFavoriteBoards`.
- 위젯 링크는 `https://`이면서 호스트가 `knue.ac.kr` 또는 `*.knue.ac.kr`일 때만 연다.
- 테마·투명도는 기존 키 `themeMode`(int), `transparency`(String) 재사용.
- iOS 최소 15.0. 새 iOS 타깃을 만들지 않는다(`MealWidgetBundle`에 추가).
- 위젯 저장소 키(Dart 상수 = Swift·Kotlin 문자열): `bus_timetable_json`, `notice_rows_json`, `notice_boards_json`, `notice_feed_base`, `notice_feed_direct`(bool).
- iOS kind: `BusWidget`, `NoticeWidget`. Android 클래스: `com.knue.knuemate.BusWidgetProvider`, `com.knue.knuemate.NoticeWidgetProvider`.
- 확인 절차(CLAUDE.md): `flutter analyze lib test`(error·warning 0) → `flutter test` → `flutter build apk --debug`, iOS는 `flutter build ios --no-codesign`.

## Review Focus

- 자정 직후(00:05) — 오늘 첫 차를 보여야 하고 어제 막차가 남으면 안 된다. → Task 1 테스트 `nextDepartures 자정 직후`.
- 막차 지난 뒤(23:30) — "오늘 운행 끝". → Task 1 `nextDepartures 막차 이후 빈 목록`.
- 출발 시각과 같은 분(14:27:30에 14:27 차) — 방금 떠난 차로 보고 뺀다(규칙: `출발시각 > 지금 분`). → Task 1 `nextDepartures 같은 분은 지난 차`.
- 즐겨찾기 게시판이 수집 파일에 없는 이름(옛 이름) — 그 줄은 조용히 빠진다, 오류 아님. → Task 1 `noticeWidgetRows 없는 게시판은 건너뜀`.
- 위젯 저장소의 링크가 학교 밖 주소 — 열지 않는다. → Task 1 `widgetLinkAllowed`, Task 2 `noticeLinkFromWidgetUri`.

---

### Task 1: Dart 규칙 함수

**Files:**
- Create: `lib/home_widgets.dart`
- Test: `test/home_widgets_test.dart`

**Interfaces:**
- Produces:
  - 키 상수 `kWidgetBusTimetableKey = 'bus_timetable_json'`, `kWidgetNoticeRowsKey = 'notice_rows_json'`, `kWidgetNoticeBoardsKey = 'notice_boards_json'`, `kWidgetNoticeFeedBaseKey = 'notice_feed_base'`, `kWidgetNoticeDirectKey = 'notice_feed_direct'`, `kIosBusWidgetKind = 'BusWidget'`, `kIosNoticeWidgetKind = 'NoticeWidget'`, `kAndroidBusWidget = 'com.knue.knuemate.BusWidgetProvider'`, `kAndroidNoticeWidget = 'com.knue.knuemate.NoticeWidgetProvider'`.
  - `List<String> nextDepartures(List<String> times, DateTime now, int n)` — "HH:mm" 중 `분 > now의 분`(오늘 기준)인 것 앞에서 n개.
  - `bool isBusHoliday(DateTime now)` — 토·일.
  - `String busWidgetTimetableJson()` — `{"v":1,"routes":[{"label":"513","sub":"교원문화관","weekday":[...],"holiday":[...]}, ...]}`. 줄 순서: 513, 514, 518, `913 평동행`(sub `교원대 경유`, `route913MihoToPyeongdong[].knueTime`을 weekday·holiday 둘 다), `913 미호행`(`route913PyeongdongToMiho[].knueTime`). 513·514·518은 `BusTimetableData.schedules[n]["outgoing"]`.
  - `List<String> noticeWidgetBoards(List<String>? stored)` — Global Constraints 규칙.
  - `class NoticeWidgetRow { String board; String title; String date; String link; Map toJson(); }` (키 `b`,`t`,`d`,`l`).
  - `List<NoticeWidgetRow> noticeWidgetRows(List<Notice> cache, List<String> boards, {int max = 8})` — 게시판마다 date 최신 1개, 게시판끼리는 date 내림차순(같으면 `boards` 순서), max개.
  - `bool widgetLinkAllowed(String url)`.

- [ ] **Step 1: 실패하는 테스트 작성** — `test/home_widgets_test.dart`:
  - `nextDepartures(['06:20','14:27','15:35'], DateTime(2026,11,23,14,0), 2)` == `['14:27','15:35']`
  - 같은 분은 지난 차: `DateTime(2026,11,23,14,27,30)` → `['15:35']`
  - 자정 직후: `DateTime(2026,11,24,0,5)`, n=1 → `['06:20']`
  - 막차 이후: `DateTime(2026,11,23,23,30)` → `[]`
  - `isBusHoliday(DateTime(2026,11,22))` true(일), `DateTime(2026,11,23)` false(월)
  - `busWidgetTimetableJson()` 디코드 → labels `['513','514','518','913 평동행','913 미호행']`, 513 weekday 첫 값 `'06:20'`, 913 평동행 weekday == `route913MihoToPyeongdong.map((t)=>t.knueTime)`
  - `noticeWidgetBoards(null)` == `['대학소식','학사공지']`, `([])` == `kDefaultFavoriteBoards.toList()`, `(['학사공지'])` == `['학사공지']`
  - `noticeWidgetRows`: 학사공지 2개(11-20, 11-19)·장학금 1개(11-21)·boards `['학사공지','장학금','없는게시판']` → `[장학금 11-21, 학사공지 11-20]` (게시판당 1개, 없는 게시판 건너뜀); max=1이면 장학금만
  - `widgetLinkAllowed`: `https://www.knue.ac.kr/www/x` true, `https://lib.knue.ac.kr/a` true, `http://www.knue.ac.kr` false, `https://evil.com/knue.ac.kr` false, `https://knue.ac.kr.evil.com` false
- [ ] **Step 2: 실패 확인** — `flutter test test/home_widgets_test.dart` → 컴파일 실패(파일 없음)
- [ ] **Step 3: `lib/home_widgets.dart` 구현** — 위 시그니처. 시각 비교는 분 단위 정수(`h*60+m`).
- [ ] **Step 4: 통과 확인** — `flutter test test/home_widgets_test.dart` → All tests passed
- [ ] **Step 5: 커밋** — `feat(widget): 공지·버스 위젯 규칙 함수`

### Task 2: Dart 연결 (저장소에 넣기 · 링크 열기)

**Files:**
- Modify: `lib/home_widgets.dart` (동기화 함수), `lib/main.dart:414-449`, `lib/notice_service.dart:410-420` (`NoticeCache.save`), `lib/constants.dart:1264` 근처(즐겨찾기 저장), `lib/notice_feed.dart:189` 근처(`direct` 반영)
- Test: `test/home_widgets_test.dart`

**Interfaces:**
- Consumes: Task 1 전부.
- Produces:
  - `Future<void> pushBusWidgetTimetable()` — 저장된 값과 다를 때만 `HomeWidget.saveWidgetData` + `updateWidget(iOSName: kIosBusWidgetKind, qualifiedAndroidName: kAndroidBusWidget)`. 예외는 삼킨다(debugPrint).
  - `Future<void> pushNoticeWidget()` — SharedPreferences에서 `fav_boards` 읽어 `noticeWidgetBoards` → `NoticeCache.load()` → `noticeWidgetRows` → 네 키(`rows`, `boards`, `NoticeFeed.base`, `NoticeFeedSettings.direct`) 저장 + 공지 위젯 갱신. 백그라운드 isolate에서도 돈다(Flutter UI 의존 금지).
  - `String? noticeLinkFromWidgetUri(Uri? uri)` — `knuemate://notice?u=<링크>`에서 링크를 꺼내 `widgetLinkAllowed`면 반환, 아니면 null.
  - `widgetTabForUri`: `notice` → `AppTab.home`(공지는 홈 카드에 있다).

- [ ] **Step 1: 실패하는 테스트** — `noticeLinkFromWidgetUri(Uri.parse('knuemate://notice?u=${Uri.encodeComponent("https://www.knue.ac.kr/www/a?b=1")}'))` == 원래 링크; `u`가 `https://evil.com`이면 null; `knuemate://notice`(u 없음) null; `widgetTabForUri(Uri.parse('knuemate://notice'))` == `AppTab.home`.
- [ ] **Step 2: 실패 확인** — `flutter test test/home_widgets_test.dart`
- [ ] **Step 3: 구현**
  - `_initializeHomeWidget`: `setAppGroupId` 뒤 `unawaited(pushBusWidgetTimetable())`, `unawaited(pushNoticeWidget())`.
  - `_handleWidgetUri`: 먼저 `noticeLinkFromWidgetUri`가 링크를 주면 `launchUrl(externalApplication)` 하고 끝, 아니면 기존 탭 이동.
  - `NoticeCache.save`: `changed`면 `unawaited(pushNoticeWidget())`.
  - 즐겨찾기 저장(`prefs.setStringList(keyFavBoards, …)`) 뒤 `unawaited(pushNoticeWidget())`.
  - `NoticeFeedSettings`에서 `direct` 값이 바뀌어 기기에 적힐 때 `unawaited(pushNoticeWidget())`.
  - `home_widgets.dart`가 `notice_service.dart`를 import하고 `notice_service.dart`도 `home_widgets.dart`를 import하게 되면 순환 import — Dart는 허용하지만 초기화 순서 문제가 없도록 top-level 상수만 공유.
- [ ] **Step 4: 통과 확인** — `flutter test` 전체 통과, `flutter analyze lib test` error·warning 0
- [ ] **Step 5: 커밋** — `feat(widget): 앱이 공지·버스 위젯 데이터를 넣는다`

### Task 3: iOS 버스 위젯

**Files:**
- Create: `ios/MealWidget/BusWidget.swift`, `ios/MealWidget/WidgetShared.swift` (테마·투명도 읽기, `widgetBackground`, 색 — `MealWidget.swift`에서 옮김)
- Modify: `ios/MealWidget/MealWidget.swift` (공용 부분 제거, `MealWidgetBundle`에 `BusWidget()` 추가), `ios/Runner.xcodeproj/project.pbxproj` (새 swift 파일을 MealWidget 타깃 Sources에 — 세션에서 쓴 xcodeproj 스크립트 방식, `GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec /opt/homebrew/opt/ruby/bin/ruby`)
- Test: `test/native_id_consistency_test.dart` (kind·키 문자열이 Swift 파일에 있는지)

**Interfaces:**
- Consumes: 키 `bus_timetable_json` 형식(Task 1), kind `BusWidget`.
- Produces: `func nextDepartures(_ times: [String], now: Date, n: Int) -> [String]` (Swift, Dart와 같은 규칙), `WidgetShared.swift`의 `readTheme(defaults) -> (isDark: Bool?, transparency: Double)`, `View.widgetBackground(_:)`.

- [ ] **Step 1: 실패하는 테스트** — `native_id_consistency_test.dart`에 그룹 추가: `ios/MealWidget/BusWidget.swift`가 `kind: String = "BusWidget"`과 `"bus_timetable_json"`을 포함, `MealWidget.swift`의 번들에 `BusWidget()`.
- [ ] **Step 2: 실패 확인** — `flutter test test/native_id_consistency_test.dart`
- [ ] **Step 3: 구현** — 타임라인: 오늘 남은 모든 출발 시각 +1분마다 엔트리, 다음날 00:00 엔트리, 정책 `.atEnd`. 엔트리마다 그 시각 기준으로 노선별 다음 차를 다시 고른다. small: 노선별 1대(5줄), medium: 2대 + 가장 가까운 차 "N분 뒤". 남은 차 없음 → "오늘 운행 끝". 데이터 없음 → "앱을 한 번 열어 주세요". `widgetURL(knuemate://bus)`. Swift 함수 위에 Task 1 테스트 표(자정·같은 분·막차)를 주석으로.
- [ ] **Step 4: 통과·빌드** — `flutter test test/native_id_consistency_test.dart` PASS, `flutter build ios --no-codesign` → `✓ Built`
- [ ] **Step 5: 미리보기** — 세션 방식(macOS `swiftc` + `ImageRenderer`, `if #available(iOS 17.0, *)` → `if false`)으로 small·medium·라이트·다크 PNG를 만들어 사용자에게 보여준다.
- [ ] **Step 6: 커밋** — `feat(ios): 버스 시간표 위젯`

### Task 4: iOS 공지 위젯 (수집 파일 직접 받기)

**Files:**
- Create: `ios/MealWidget/NoticeWidget.swift`
- Modify: `MealWidgetBundle`에 `NoticeWidget()`, `project.pbxproj`
- Test: `test/native_id_consistency_test.dart`

**Interfaces:**
- Consumes: 키 `notice_rows_json`, `notice_boards_json`, `notice_feed_base`, `notice_feed_direct`; 수집 파일 형식 `index.json`의 `boards[].{category,file,fetchedAt,hash}`, `b/<id>.json`의 `items[].{t,l,d}`(날짜 내림차순 — 2026-11-23 확인).
- Produces: kind `NoticeWidget`.

- [ ] **Step 1: 실패하는 테스트** — `NoticeWidget.swift`에 `"NoticeWidget"`, 네 키 문자열, 그리고 `knue.ac.kr`이 아닌 호스트로 요청하지 않도록 base가 `https://`로 시작하는지 검사하는 코드(`hasPrefix("https://")`) 포함.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**
  - `getTimeline`: `notice_feed_direct`면 받기 생략. 아니면 `URLSession`(timeout 10초)으로 `index.json` → 대상 게시판 중 `hash`가 App Group 파일(`notice_widget_cache.json`: board→{hash, item, fetchedAt})과 다른 것만 `b/<id>.json` → 첫 항목 저장. 실패하면 저장분, 그다음 `notice_rows_json`. 정렬·개수 규칙은 Dart `noticeWidgetRows`와 같게. 다음 갱신 `.after(1시간)`.
  - 머리: "공지" + 가장 이른 `fetchedAt`이 3시간 넘으면 "갱신 지연". 머리 탭 `knuemate://notice`.
  - 줄: `Link(destination: knuemate://notice?u=<percent-encoded link>)` — medium 4줄, large 8줄. `supportedFamilies([.systemMedium, .systemLarge])`.
- [ ] **Step 4: 통과·빌드** — 테스트 PASS, `flutter build ios --no-codesign` 성공
- [ ] **Step 5: 미리보기** — medium·large PNG(가짜 rows 주입)
- [ ] **Step 6: 커밋** — `feat(ios): 공지 위젯 — 수집 파일 직접 받기`

### Task 5: Android 버스 위젯

**Files:**
- Create: `android/app/src/main/kotlin/com/knue/knuemate/BusWidgetProvider.kt`, `WidgetTheme.kt`(테마·투명도 공용 — `MealWidgetProvider`의 색 로직을 옮김), `res/layout/bus_widget_layout.xml`, `res/xml/bus_widget_info.xml`
- Modify: `AndroidManifest.xml`(receiver + `com.knue.knuemate.BUS_TICK` 액션), `MealWidgetProvider.kt`(공용 함수 사용)
- Test: `test/native_id_consistency_test.dart`

**Interfaces:**
- Consumes: `bus_timetable_json`, `themeMode`, `transparency`.
- Produces: `fun nextDepartures(times: List<String>, nowMinutes: Int, n: Int): List<String>` (Kotlin, 같은 규칙).

- [ ] **Step 1: 실패하는 테스트** — Manifest에 `.BusWidgetProvider` receiver, Kotlin 파일에 `"bus_timetable_json"`.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** — `HomeWidgetProvider` 상속. 5줄 고정 TextView(노선·다음 차 2대·N분 뒤). `onUpdate` 끝에 `AlarmManager.set(RTC, 다음 출발+1분, PendingIntent.getBroadcast(…BUS_TICK, FLAG_IMMUTABLE|FLAG_UPDATE_CURRENT))`, 남은 차 없으면 다음날 00:01. `onReceive(BUS_TICK)` → 모든 위젯 id로 `onUpdate`. `onDisabled`에서 알람 취소. `updatePeriodMillis=1800000`. 탭 `knuemate://bus`(`HomeWidgetLaunchIntent`).
- [ ] **Step 4: 통과·빌드** — `flutter test`, `flutter build apk --debug`
- [ ] **Step 5: 커밋** — `feat(android): 버스 시간표 위젯`

### Task 6: Android 공지 위젯

**Files:**
- Create: `NoticeWidgetProvider.kt`, `res/layout/notice_widget_layout.xml`(머리 + 8줄 고정, 크기에 따라 4줄만 보이게 `onAppWidgetOptionsChanged`의 높이로), `res/xml/notice_widget_info.xml`
- Modify: `AndroidManifest.xml`
- Test: `test/native_id_consistency_test.dart`

**Interfaces:**
- Consumes: `notice_rows_json`(앱·백그라운드 작업이 넣음 — Android는 직접 받지 않는다).

- [ ] **Step 1: 실패하는 테스트** — Manifest `.NoticeWidgetProvider`, Kotlin에 `"notice_rows_json"`.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** — 줄마다 `PendingIntent.getActivity(ACTION_VIEW, Uri.parse(link))`, 단 Kotlin에서도 `https` + `knue.ac.kr` 호스트 검사(Dart `widgetLinkAllowed`와 같은 규칙), 아니면 클릭 없음. 머리 탭 `knuemate://notice`. 빈 데이터 → "앱을 한 번 열어 주세요".
- [ ] **Step 4: 통과·빌드** — `flutter test`, `flutter build apk --debug`
- [ ] **Step 5: 커밋** — `feat(android): 공지 위젯`

### Task 7: 마무리 확인 · 문서

**Files:**
- Modify: `CLAUDE.md`(위젯 절: 키 표, 규칙이 세 곳(Dart·Swift·Kotlin)에 있다는 것, 위젯은 학교·Firestore에 요청하지 않는다), `lib/meal_screen.dart:1748` 근처 위젯 설정 제목 아래 "모든 위젯에 적용" 안내 한 줄

- [ ] **Step 1:** `flutter analyze lib test` → error·warning 0
- [ ] **Step 2:** `flutter test` → All tests passed
- [ ] **Step 3:** `flutter build apk --debug` → `✓ Built`
- [ ] **Step 4:** `flutter build ios --no-codesign` → `✓ Built`, `Runner.app/PlugIns/MealWidget.appex` 존재
- [ ] **Step 5:** 커밋 — `docs: 공지·버스 위젯 인수인계`
