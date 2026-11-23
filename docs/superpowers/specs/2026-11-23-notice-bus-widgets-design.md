# 공지·버스 홈 위젯 설계

2026-11-23 · 상태: 승인됨

## 왜

학생이 **앱을 열지 않고** 홈 화면에서 바로 확인하게 하려는 것이다.

- 버스: "학교에서 나가는 다음 차가 언제냐"
- 공지: "내가 보는 게시판에 새 글이 올라왔냐"

## 목표

- **버스 위젯** — 학교에서 나가는 차의 다음 출발 시각. 앱을 안 열어도, 인터넷이
  없어도 시각이 맞아야 한다(지난 차가 "다음 차"로 남아 있으면 실패).
- **공지 위젯** — 즐겨찾기(★) 게시판마다 **가장 최신 글 하나씩**. 즐겨찾기가
  없으면 `kDefaultFavoriteBoards`(대학소식·학사공지·청람소양·장학금). 앱 홈의
  공지 카드와 같은 게시판 범위다.
- Android·iOS 둘 다.

## 하지 않는 것

- 버스 **실시간** 도착 정보(위젯 갱신 주기로는 낡은 값이 되고, 기기마다
  `realtime/bus_locations`를 읽으면 Firestore 하루 읽기 한도 5만 건을 압박한다).
- 학교로 오는 방향(탑승 정류장마다 시각이 달라 한 값으로 못 맞춘다).
- 위젯 전용 게시판 선택 화면, 키워드 위젯.
- 콜버스, 경유 노선(500·502·503·509·511·747 — 시간표가 없다).

## 실패로 치는 것 (동작은 해도)

- 위젯이 **학교 서버(knue.ac.kr 계열)에 요청**한다. CLAUDE.md "학교 서버 부담"
  — 기기마다 학교를 긁는 기능은 넣지 않는다. 위젯은 GitHub Pages 수집 파일만 본다.
- 위젯이 **Firestore를 읽거나 쓴다**(하루 한도).
- 지난 버스 시각이 "다음 차"로 보인다.

## 방식 (고른 것: 3)

| | 방식 | 장단점 |
|---|---|---|
| 1 | 앱·백그라운드가 계산해 넣고 위젯은 그리기만(식단 위젯 방식) | 가장 쉽다. iOS 백그라운드가 몇 시간씩 안 돌아 버스 시각이 낡는다 — 탈락 |
| 2 | 버스는 위젯이 시간표로 직접 계산, 공지는 앱이 넣기 | 버스는 항상 맞다. iOS 공지는 앱을 안 열면 낡는다 |
| **3** | 2 + **iOS 공지 위젯은 수집 파일을 직접 받는다** | 두 플랫폼 다 앱 없이 맞다. 수집 파일 읽기를 Swift로 한 번 더 짠다 |

사용자가 3을 골랐다. Android 공지는 1시간 백그라운드 작업이 믿을 만해서 앱이
넣어 주는 대로 둔다.

## 버스 위젯

### 보여 줄 것 (사용자 결정: 학교에서 나가는 차만)

| 줄 | 출처 | 기준 |
|---|---|---|
| 513 | `schedules["513"]["outgoing"]` | 교원문화관 출발 |
| 514 | `schedules["514"]["outgoing"]` | 교원문화관 출발 |
| 518 | `schedules["518"]["outgoing"]` | 교원문화관 출발 |
| 913 평동행 | `route913MihoToPyeongdong[].knueTime` | 교원대 경유 |
| 913 미호행 | `route913PyeongdongToMiho[].knueTime` | 교원대 경유 |

913을 방향별 두 줄로 나눈 건 **내 판단**이다 — 교원대가 경유지라 양쪽 다
학교에서 탈 수 있다.

평일/주말은 앱 버스 화면과 같은 규칙: 토·일이면 `holiday`, 아니면 `weekday`
(공휴일은 앱도 구분하지 않는다). 913 경유 시각 표는 요일 구분이 없으므로 그대로 쓴다.

- small: 노선마다 다음 차 1대.
- medium: 노선마다 다음 차 2대 + "N분 뒤"(가장 가까운 차만).
- 오늘 남은 차가 없는 노선은 "오늘 운행 끝".
- 누르면 `knuemate://bus`(이미 `widgetTabForUri`가 버스 탭으로 보낸다).

### 데이터 흐름

시간표는 앱에 들어 있는 상수(`BusTimetableData`)다. 앱이 시작할 때 위젯 저장소에
**JSON 한 덩이**로 넣는다(`bus_timetable_json`). 값이 바뀌었을 때만 쓴다(같으면
건너뛴다). 키 구조:

```json
{"v":1,"routes":[{"label":"513","weekday":["06:20",...],"holiday":[...]}, ...]}
```

시간표를 Swift·Kotlin에 하드코딩하지 않는 이유: Dart 한 곳만 고치면 되게.
JSON을 만드는 함수(`busWidgetTimetableJson`)와 "지금 이후 다음 차 n대"를 고르는
함수(`nextDepartures(times, now, n)`)는 **Dart 순수 함수 + 테스트**로 두고,
Swift·Kotlin은 같은 규칙을 옮긴다. 세 구현이 어긋나지 않게 Dart 테스트에 경계
사례 표(자정 넘김, 마지막 차 직후, 정각 같은 분)를 두고 같은 표를 주석으로
Swift·Kotlin 쪽에 남긴다.

### 제때 넘어가기

- **iOS**: `getTimeline`이 오늘 남은 출발 시각마다 엔트리를 만든다(각 출발 1분
  뒤에 다음 차로 넘어감) + 자정 엔트리. 정책 `.atEnd`. 엔트리 수가 많아도
  하루 약 80개라 문제없다. 위젯 갱신 예산을 쓰지 않는다.
- **Android**: `AlarmManager.set`(정확 알람 아님 — 권한 불필요, 몇 분 늦을 수 있음)
  으로 다음 출발 1분 뒤에 위젯 갱신 브로드캐스트를 예약한다. 갱신할 때마다 다음
  알람을 다시 건다. `updatePeriodMillis` 30분이 안전망. "N분 뒤"는 몇 분 늦게
  넘어갈 수 있다는 점을 감안해, 이미 지난 차는 그리는 순간 다시 걸러낸다.

## 공지 위젯

### 보여 줄 것

- 대상 게시판: `PreferencesService.favoriteBoards`, 비면 `kDefaultFavoriteBoards`.
- 게시판마다 최신 글 1개(수집 파일의 첫 항목 — 날짜 내림차순인지 확인 필요,
  아니면 `d`로 정렬). 줄 = `[게시판] 제목 · MM/DD`.
- 게시판이 줄 수보다 많으면 **최신 글 날짜가 늦은 게시판부터**(내 판단).
- medium 4줄, large 8줄. small은 제공하지 않는다(제목이 너무 잘린다, 내 판단).
- 머리에 마지막으로 받은 시각. 수집 파일 `fetchedAt`이 3시간 넘었으면 앱과 같은
  "갱신이 늦어지고 있어요" 표시.
- 줄을 누르면 그 글 링크를 **브라우저**로 연다(앱 공지 화면과 같다).
  - Android: 줄마다 `ACTION_VIEW` PendingIntent(앱을 거치지 않는다).
  - iOS: 위젯 `Link`는 앱으로 URL을 넘기므로 `knuemate://notice?u=<인코딩된 링크>`
    → Flutter가 `launchUrl(externalApplication)`. `widgetTabForUri`에 `notice`를
    추가(탭 이동 없이 링크만 연다). 링크는 `https://`이고 knue.ac.kr 계열일 때만
    연다(위젯 저장소를 거친 값이라도 아무 주소나 열지 않는다).
- 머리를 누르면 공지 탭(`knuemate://notice`).

### 데이터 흐름

- **앱 → 위젯 저장소** (두 플랫폼 공통): 공지 캐시가 바뀔 때(홈 화면
  `_loadNoticePreview`, 공지 화면 새로 고침, 백그라운드 공지 작업)
  `noticeWidgetRows(cache, favBoards)` 결과를 `notice_rows_json`에 쓰고
  `notice_boards_json`(대상 게시판 이름 목록), `notice_feed_base`
  (`NoticeFeed.base`)도 같이 쓴다. 이 함수도 Dart 순수 함수 + 테스트.
- **Android**: 이것으로 끝. 백그라운드 공지 작업(1시간)이 위젯도 갱신한다.
- **iOS 위젯 자체 받기**: `getTimeline`에서
  1. `notice_feed_base`의 `index.json`을 받는다(7KB).
  2. 대상 게시판 중 `hash`가 위젯이 기억한 값과 다른 것만 `b/<id>.json`을 받는다.
  3. 받은 결과를 App Group 파일에 저장하고 그린다. 실패하면 앱이 넣은
     `notice_rows_json` 또는 지난 저장분으로 그린다.
  4. 다음 갱신 요청: 1시간 뒤(`.after`). iOS가 실제로는 예산에 따라 늦출 수 있다.
  - 요청 한도: 위젯 한 번 갱신에 최대 `1 + 게시판 수`건, GitHub Pages만.
    학교 서버·Firestore 요청 0건.
  - 시간 제한 10초. 넘으면 저장분으로 그린다.
  - **비상 직접 모드**(`app_settings/notice_feed.direct = true`)일 때 위젯은 자체
    받기를 하지 않는다 — 앱이 넣어 준 값만 그린다(학교로 가지 않기 위해).
    앱이 `notice_feed_direct` 플래그를 위젯 저장소에 같이 쓴다.

## 공통

- 테마·투명도: 식단 위젯 설정(`themeMode`, `transparency`)을 그대로 따른다(내 판단
  — 설정 화면을 늘리지 않으려고). 위젯 설정 섹션 문구를 "모든 위젯에 적용"으로.
- iOS: 기존 `MealWidget` 확장 안의 `WidgetBundle`에 두 위젯을 더한다(타깃 추가
  없음, 서명·프로파일 그대로). 최소 iOS 15.
- Android: 위젯마다 `AppWidgetProvider` + 레이아웃 + `appwidget-provider` xml.
  리소스 축소에 걸리지 않게 이름으로만 찾는 리소스는 `res/raw/keep.xml`에 더한다.
- 위젯 저장소 키 이름은 Dart 상수 한 곳에 모으고 Swift·Kotlin 쪽 주석에 같은 표를
  둔다(식단 위젯과 같은 방식).

## 확인

- Dart: 새 순수 함수 테스트, `flutter analyze` / `flutter test` /
  `flutter build apk --debug`.
- iOS: `flutter build ios --no-codesign`, Mac 렌더러로 디자인 미리보기
  (식단 위젯 때와 같은 방식).
- Android: 에뮬레이터에 위젯을 올려 확인(가능하면).

## 빌더에게 맡기는 것

- 레이아웃 세부(글꼴 크기, 간격) — 식단 위젯과 같은 톤.
- 수집 파일 항목 순서 확인과 정렬.
- Android 알람 PendingIntent 구성 세부.
