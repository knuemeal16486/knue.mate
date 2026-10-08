# KNUE Mate — 작업 지침

한국교원대학교 학생용 Flutter 앱(`com.knue.knuemate`). Android는 Play 스토어,
iOS는 Codemagic으로 빌드한다(로컬 iOS 빌드 없음).

이 파일은 **어느 기기에서 열어도** 같이 읽히는 인수인계 노트다. 기기에 저장된
메모리는 따라오지 않으므로, 저장소를 따라다녀야 할 것은 여기 적는다.

## 확인 절차

고친 뒤에는 이 순서로 돌린다. 하나라도 건너뛰지 않는다.

```bash
flutter analyze lib test     # error·warning 0
flutter test                 # 전부 통과
flutter build apk --debug    # 실제로 빌드되는지
```

Android 리소스 축소: `android.r8.optimizedResourceShrinking=true`(gradle.properties).
이름 문자열로만 찾는 리소스(알림 아이콘 `ic_stat_notify`, 네이티브 광고 레이아웃)는
`res/raw/keep.xml`에 남겨 둔다 — 새로 이런 리소스를 쓰면 거기 더한다.
스플래시 `styles.xml`의 `windowLayoutInDisplayCutoutMode shortEdges`는 Android 15에서
지원 중단이라 뺐다. `flutter_native_splash:create`를 다시 돌리면 도로 생기니 또 지운다.

`flutter clean` 뒤 처음 빌드는 느리다. 플러그인을 추가하면 Gradle이 옛 상태를
들고 있어 "cannot find symbol"이 나는데, `flutter clean && flutter pub get`이면
풀린다(실제 의존성 문제가 아니다).

## 순수 함수 + 테스트

로직은 화면에서 떼어내 순수 함수로 두고 테스트를 붙이는 게 이 저장소의 관행이다
(`dedupeCalendarEvents`, `widgetMealSlot`, `housingMapStyle`, `pickHomeBusSummary` …).
화면 안에만 있는 로직은 확인할 방법이 없어서 조용히 틀린 채로 남는다.

## 자취방 지도

### 눈으로 확인할 땐 앱 painter로

```bash
flutter test test/map_preview.dart   # → build/map_preview.png, build/map_preview_dark.png
dart run tool/crop_ov.dart build/map_preview.png <x> <y> <w> <h> <배율> <out.png>
```

`test/map_preview.dart`는 앱의 `HousingMapPainter`를 **그대로** 호출한다.
`tool/preview_iso.dart`는 칠하는 순서를 따로 흉내 낸 재구현이라 앱과 어긋난다 —
실제로 OSM 도로를 교내 지형이 덮어 가리는 버그를 그쪽으로는 못 봤다.

map_preview는 google_fonts 예외로 "실패"가 찍히지만 **PNG는 정상 생성된다**.
이름표는 대체 글꼴이라 검은 네모로 보인다.

### 지도 데이터 다시 만들기

```bash
dart run tool/trace_map.dart     # 캡처 → tool/mapsrc/traced_raw.json  (약 15초)
dart run tool/build_index.dart   # → assets/housing/campus_traced.json
node tool/fetch_osm_roads.js     # OSM 도로 → assets/housing/campus_roads.json
```

두 dart 도구는 **결정적**이다. 고치기 전에 그대로 돌려 같은 파일이 나오는지
먼저 확인하면, 이후 차이가 내 변경 때문임을 알 수 있다.

⚠️ **지금은 같은 파일이 안 나온다(2026-09-26 확인).** 커밋된
`campus_traced.json`에는 원본에서 다시 만들 수 없는 **교내 21동의 이름·용도**
(황새생태연구원·제2대학·부설중학교 …)가 들어 있어서, `build_index`를 돌리면
그 값이 사라진다. 그 값이 어느 입력에서 왔는지 찾아 원본에 옮기기 전까지는
다시 만들지 말고, 이름 하나 고칠 땐 `building_names.json`과
`campus_traced.json`을 둘 다 손으로 고친다.

### 개발자 수정 굽기

개발자 모드에서 고친 **외형·위치**(외곽선·층수·삭제·병합·추가 건물)는
Firestore에 쌓인다. 앱은 에셋으로 먼저 그리고 수정을 받아 다시 그리므로,
확정된 외형은 에셋에 구워 둘 수 있다.

⚠️ **아직 굽지 않았다(2026-09-26).** 구우면 `campus_traced_test`가 깨진다.
합친 건물이 교내 여부·용도를 잃던 건 고쳤다(`mergedCampusTraits`·
`inheritMergedCampus`, 굽기 도구도 같은 규칙). 남은 건 두 가지다:
교내 건물을 합치면 **교내 번호(1..N)**가 비고, 층고 때문에 층수를 올려 둔
건물(종합교육관 11층, 실제 7층)은 층수를 되돌리고 **지도 높이(mapFloors)**로
옮겨야 한다 — 표시 층수와 지도 높이는 따로다. 들어갈 때 건물이 바뀌어 보이던
건 굽지 않아도 된다 — 화면이 첫 수정 데이터를 받은 뒤에 지도를 보여준다.

```bash
dart run tool/bake_overrides.dart           # 바뀔 내용만 본다
dart run tool/bake_overrides.dart --write   # campus_traced.json에 쓴다
```

반복해서 돌려도 안전하다(두 번째엔 바뀌는 게 0). Firestore 수정 문서는
지우지 않는다 — 같은 모양을 한 번 더 덮을 뿐이고, 이름·색·이름표 숨김·
가게·시세는 계속 거기서 온다. 구운 에셋은 **새 버전을 배포해야** 사용자에게
간다.

레이어마다 맡는 일이 다르다:

- **도로** = OSM 중심선(ODbL)을 굵기로 그어 그린다. 래스터에서 면으로 떠내던
  방식은 천장이 있었다 — 충실도를 올리면 굽고, 곧게 펴면 길이 제자리를 벗어났다.
- **포장면** = 광장·주차 앞마당만. OSM 도로가 덮는 통로는 빼둔다(안 빼면 매끈한
  도로선 옆으로 옛 가장자리가 톱니처럼 비어져 나온다).
- **건물** = 캡처에서 뽑아 직각으로 세운다.

### 누를 수 있는 건물·시세 제보 (2026-10-08)

손님 화면에서는 **색이 칠해진 건물과 교내 건물만** 눌린다(`isHousingTappable`).
예외로 `kHousingUntappableNames`(퇴계관 — 철거 예정, 지도 데이터 이름은
청람천문대)는 교내여도 안 눌리고 지도 검색에도 안 나온다.
흰 건물은 눌러도 아무 일이 없다 — 개발자(관리자)는 흰 건물에도 이름·색을
붙여야 하므로 전부 눌린다. 시세 제보·연락처·비교 같은 자취방 부분은 색이 칠해진
**주거 건물**에만 나온다(`isHousingReportable`). **파란색(`kHousingShopColor`,
#2196F3)이 상가 색**이라 제보를 받지 않는다 — 다만 상가주택
(`kHousingMixedUseNames`: 가온빌·디저트 39·원더빌)과 이미 시세가 있는 건물은
받는다. 색이 있어도 주거가 아닌 건물은 `kHousingNonResidentialNames`(월탄2리
경로당)에 이름을 넣는다. 둘 다 지도에 뜨는 이름으로 맞추고 사용자가 정했다.
새 건물을 원룸으로 열려면 개발자 모드에서 파란색이 아닌 색을 칠하면 된다.

### 원본 캡처는 벡터 지도다

`tool/mapsrc/*.jpg|png`는 항공사진이 아니라 네이버가 **벡터로 그린 지도**다.
모서리가 이미 칼같이 서 있으니 흐리면 그걸 우리 손으로 뭉개는 셈이다. 래스터
계단은 흐리기가 아니라 단순화 허용오차(`preEps`)로 타 넘는다. **`preEps`는
미터가 아니라 셀 단위**다(`res` = 0.3m).

네이버는 **한 건물 안에도** 날개를 나누는 칸막이 선을 긋는다. 그걸 건물 사이
틈으로 읽으면 한 동이 여러 조각으로 쪼개진다. 폭으로 가른다 — 칸막이는 약 2셀,
진짜 틈은 6~10셀.

### 라이선스 (필수)

OSM 데이터·타일은 ODbL이라 **"© OpenStreetMap 기여자" 표기가 의무**다.
3D 지도(자취방·캠퍼스맵 지도 탭 공용)와 캠퍼스맵 건물 상세의 작은 지도에 있다.
지도를 새로 띄우는 화면을 만들면 같이 넣는다.

캠퍼스맵의 일반 지도(flutter_map 타일 위 시설 마커·산책로·내 위치·날씨)는
2026-09-26에 3D 지도 하나로 합치면서 걷어냈다. 캠퍼스맵 **지도** 탭은
`HousingScreen(campusMode: true)`이고, 장소 탭의 "지도에서 보기"는
`HousingFocusRequest`로 캠퍼스맵 위도·경도를 넘긴다. 교내 건물 정보(설명·
층별 호실)는 `matchCampusInfo`로 이름 먼저, 안 되면 좌표로 3D 건물에 잇는다
— 캠퍼스맵 좌표는 마커 한 점이라 건물 윤곽에서 10~65m 떨어져 있다.

네이버 캡처는 **추적 원본으로만** 쓴다. 이미지를 앱에 담아 배포하면 저작권
문제가 된다 — 그래서 벡터로 추출하는 파이프라인이 있는 것이다.

## Firestore 보안

지금은 **1단계**다. 스토어의 구버전(1.6.1)에는 익명 로그인이 없어서, 학생 쓰기를
지금 조이면 그 사용자들의 별점·제보가 화면상 성공한 것처럼 보이며 조용히 실패한다.

- 관리자 컬렉션(`club_events`·`sponsors`·`admin_map_facilities`·
  `housing_building_overrides`)과 `app_config`는 이미 잠갔다.
- 학생 쓰기·공용 캐시는 `firestore.rules`의 `studentWrite()`를 거친다.
- **2단계**: 새 버전이 스토어에 퍼진 뒤 `studentWrite()` 본문을 `signedIn()`으로
  바꾸면 끝이다.

**하루 쓰기 한도(무료 요금제 2만 건)**가 차면 읽기는 되는데 쓰기만 멈춘다.
Firestore는 한도에 걸린 쓰기를 끝없이 재시도해서 저장 창이 안 닫히는 식으로
보인다. 한국 시각 오후 4~5시에 풀린다. 모든 기기가 반복해서 쓰는 코드를
넣지 않는다(예전엔 앱을 켤 때마다 건물 16건을 다시 써서 한도를 먹었다).
버스 화면은 사용자마다 30초에 한 번 `realtime/bus_locations`를 쓴다.

관리자 인증: 비밀번호를 앱이 들고 있지 않다. `admin_grants/{uid}` 문서를 만들 때
**보안 규칙이 서버에서** `app_config/admin`과 대조한다.

이름이 비슷한 두 컬렉션을 헷갈리지 않는다:

- `app_config` — 관리자 비밀번호. **읽기까지 막혀 있다.** 콘솔에서만 건드린다.
- `app_settings` — 관리자가 앱 안에서 켜고 끄는 **공개** 설정. 모든 앱이 읽어야
  화면이 맞춰지므로 읽기는 열려 있고 쓰기만 `isAdmin()`이다.
  (`exit_promo/fillWithAdmob` — 종료 팝업의 빈 행사 자리를 애드몹으로 채울지)

## 학교 서버 부담 (필수)

2026-09-28 정보전산원(강동욱)이 메일을 보냈다. 이 앱의 공지 요청이 학교 게시판
목록 전송량의 약 70%(하루 약 7.5GB, 9/23 약 8만 3천 건)를 차지한다는 내용이다.
원인은 기기마다 2시간마다 48개 게시판을 한꺼번에 받던 백그라운드 작업이었다.
학교는 막지 않고 협조를 구했으니 **다시 늘리지 않는다.**

- 학교 서버(knue.ac.kr 계열)로 가는 요청에는 `SchoolHttp.headers()`로
  `KNUE-Mate/<버전> (KNUE MOA; +knuemeal16486@gmail.com)`을 붙인다.
- 같은 서버에는 동시에 4개까지만 보낸다(`kSchoolMaxConcurrent`). 하나씩 보내면
  새로 고침이 10~20초 걸려 불편했다. 요청 간격은 기기에 저장된
  `PersistentThrottle`로 제한하고, 메모리에만 있는 `RefreshThrottle`로 대신하지
  않는다(앱을 다시 켜면 풀린다).
- **사용자가 불편을 느끼지 않는 선에서만 줄인다(사용자 결정, 2026-09-29).**
  당겨서 새로 고침(공지 화면·홈 화면)은 제한 없이 매번 받는다.
- 공지: **기기는 학교가 아니라 수집 파일을 받는다**(`lib/notice_feed.dart`,
  1.6.4부터). 목록(`index.json`, 7KB)을 보고 지문이 바뀐 게시판 파일만 받는다.
  자동 확인은 5분 간격(`kNoticeFeedAutoGap`), 당겨서 새로 고침은 매번. 실측:
  처음 48개 2.8초, 바뀐 게 없으면 46ms. 마지막 수집이 3시간 넘은 게시판을
  보고 있으면 "공지 갱신이 늦어지고 있어요" 안내만 띄우고 **학교로 가지 않는다**.
- 백그라운드는 1시간마다(`kNoticeCheckInterval`, iOS는 AppDelegate.swift에도
  같은 값) 수집 파일을 받아 알릴 게시판(`feedAlertBoards`)을 본다 — 즐겨찾기,
  없고 키워드만 있으면 전체, 둘 다 없으면 기본 4개. 글 번호가 바뀌어서(아래)
  업데이트 뒤 첫 실행은 알림 없이 적어만 둔다(`notice_alert_seeded_feed`).
- **비상 직접 모드**: 수집기가 멈췄을 때만 Firestore `app_settings/notice_feed`에
  `direct: true`를 넣는다(콘솔). 앱이 켜질 때 읽어 기기에 적고, 그때부터 예전처럼
  **보고 있는 게시판만** 학교에서 받는다(`noticeFetchScope` — [공지사항] 탭은 그
  탭의 게시판, [대학/대학원]은 고른 대학·학과, "전체"면 ★ 학과만, 게시판마다
  30분). 백그라운드는 알릴 게시판만 4시간에 한 번(`backgroundNoticeBoards`,
  키워드만 있으면 대표 홈페이지 13개). 같은 문서의 `base`로 수집 파일 주소를
  옮길 수 있다(https만). 학과 선택 화면은 넣지 않기로 했다(사용자 결정).
- 학사일정: `academic_calendar/{학년도}` 공용 캐시를 쓰고, 하루 한 번 기기 한 대만
  학교에서 받는다. 학교 페이지는 **학년도(3월~이듬해 2월)** 단위다.
- 식단: 학교가 알려 준 API를 쓴다(`lib/meal_api.dart`,
  `rssDietInfoList.do?siteSe=one|cafe&stdde=YYYYMMDD` → 그 주 월~일 XML 약 5KB.
  예전 HTML 페이지는 215KB였다). 식당마다 한 주에 한 번 받아 7일을 채우고,
  같은 주·식당은 기기당 1시간에 한 번만 다시 받는다. 지난 날짜는 다시 안 받는다.
  값 앞뒤 공백·"조식 : " 머리글·CDATA 안 `&amp;`·"정보 없음"을 처리하고,
  응답의 날짜 범위·식당 이름이 요청과 다르면 버린다(200만 믿지 않는다).
- 기기마다 학교 서버를 긁는 기능이나 주기를 새로 넣지 않는다.
- 1.3.0~1.6.1은 원격으로 끌 방법이 없어서, 업데이트될 때까지 옛 방식으로 요청한다.

### 2단계 — 공지 중앙 수집 (수집기 2026-10-02에 켬 · 앱은 1.6.4부터 수집 파일을 읽음)

학교는 해외 IP를 막지 않으며 GitHub Actions 수집을 허락했다(2026-10-02 메일).

```bash
dart run tool/collect_notices.dart --out build/feed --force   # 손으로 한 번(학교에 48건)
gh run list --workflow collect-notices.yml --limit 5          # 최근 회차
gh workflow run collect-notices.yml                           # 지금 한 번 돌리기
gh workflow disable collect-notices.yml                       # 멈추기(배포본은 남는다)
```

한 회차는 Flutter 캐시가 있으면 40초쯤, 전부 받는 회차는 2~4분 걸린다.
첫 회차에 `tot.knue.ac.kr`(종합연수원·영유아연수원)만 20초 시간 초과가 났고
4분 뒤 회차에는 받혔다 — 가끔 그런다. 실패한 게시판은 다음 회차에 다시 받는다.

- `.github/workflows/collect-notices.yml`이 30분마다(매시 7·37분) 돌려
  GitHub Pages(`https://knuemeal16486.github.io/knue.mate/feed/`)에 올린다.
  **타이머는 cron-job.org다**(사용자 계정): 30분마다 GitHub API로
  `workflow_dispatch`를 부른다. GitHub 예약 실행은 켜 두었지만 실측 3~5시간에
  한 번꼴로만 돌아서(2026-10-03, 27시간에 7번) 예비일 뿐이다. 토큰은 이 저장소
  하나·Actions 권한만 가진 fine-grained 토큰이고 만료가 있다 — **만료되면 수집이
  멈춘다**(cron-job.org가 실패 메일을 보낸다). 헤더 `X-GitHub-Api-Version`은
  `2026-03-10`(응답 200 + 실행 번호). 옛 `2022-11-28`(응답 204)은 2028-03-10에
  끊긴다. 워크플로에 입력값(force 등)을
  두지 않는다 — 토큰이 새도 정해진 간격 이상으로 학교를 두드리지 못하게.
  `index.json`(게시판별 마지막 수집 시각·지문) + `b/<id>.json`(제목·링크·날짜·
  부서만, 본문 없음). 전체 416KB.
- **학교에 가는 양은 `kCollectIntervalMinutes`(lib/notice_collector.dart)로만
  정해진다.** 이용자 수와 무관하다. 전부 30분이면 하루 1,920건·약 1.5GB
  (한 회차 실측 30.8MB — MAIN·LIFE 8MB, DEPT·GRAD 22MB). 간격은 사용자가 정한다.
- knue.ac.kr 게시판 40개는 학교가 권한 RSS(`/rssBbsNtt.do?bbsNo=N`)로 받는다.
  게시판당 50건, 56KB~2.5MB(94%가 본문). ETag·개수 파라미터·압축이 없어
  "바뀐 것만 받기"가 안 된다. 나머지 8개(도서관·기숙사 등 다른 서버)는 목록 화면.
- 서버마다 한 번에 하나씩, 1.5초 간격. 한 서버가 3번 연달아 실패하면 그 회차는
  그만둔다. 실패·차례 아님은 지난 배포본 내용을 다시 싣는다(배포가 사이트를
  통째로 갈아 끼운다). User-Agent는 `KNUE-Mate-Collector/1.0 (+메일)`.
- 글 번호는 `stableNoticeId`(그룹|게시판|링크의 FNV-1a) — 앱이 직접 받던 때의
  번호(`Object.hash`)와 다르다. 그래서 백그라운드 알림이 수집 파일로 처음 돌 때
  "이미 알린 글"을 조용히 다시 채운다(받기에 실패하면 채우지 않고 다음에).
- 수집 파일이 묵어도 **모든 기기가 직접 긁게 하지 않는다**(학교 요청) —
  마지막 데이터 + 지연 안내(3시간 넘으면).
- 공개 저장소는 **60일 동안 커밋이 없으면 예약 실행이 꺼진다.** 꺼지는 건
  예비인 schedule뿐이고 cron-job.org가 부르는 실행은 계속 돈다. **예약 실행을
  살리려고 빈 커밋·재활성화 API를 자동으로 돌리지 않는다** — 그 용도로 널리
  쓰이던 `keepalive-workflow` 저장소가 약관 위반으로 GitHub에 차단됐다(2025-04).
- 학교는 **버전·일정·두 User-Agent**를 알려 주면 로그로 효과를 확인해 주기로
  했다. 수집기를 켠 사실과 앱 배포 일정을 회신한다. 간격이나 수집기 이름을
  바꾸면 다시 알린다.

## 남은 일

**사용자 입력이 필요**
- 태성탑연로 386 **디저트39** — 위치를 모른다. 382(x=122)와 396-28(x=158) 사이,
  태성탑연로 북쪽 끝인 것까지만 좁혀 뒀다.
- 월탄3길 **26-4, 26-2** — 이름을 모른다.

**콘솔 작업이 필요**
- 보상형 광고 단위는 이제 아무도 안 쓴다(무지개 모드가 전면 광고로 바뀌었다).
  콘솔에서 정리해도 된다.
- **Firebase Storage가 활성화돼 있지 않다.** 행사 포스터·제휴 이미지 업로드가
  전부 실패한다. Blaze 요금제가 필요할 수 있다.
- iOS 식단 위젯: Xcode에서 `ios/MealWidget/`을 Widget Extension 타깃으로
  등록해야 한다.

**알려진 한계**
- 체육관/제2체육관 경계는 두 이름표의 중간에 생겨 실제 칸막이 자리와 다르다
  (체육관 910㎡ / 제2체육관 2202㎡, 실제로는 본관이 더 크다).
- 앱 용량 41MB. 스플래시 이미지 약 8MB가 2048px 원본에서 밀도별로 생성된 것이라,
  원본을 줄이면 같이 줄어든다(스플래시 화질에 영향).

## 사람 손질 데이터

`tool/mapsrc/`의 이 파일들은 생성물이 아니라 **사람이 조사해 넣은 값**이다.

- `building_names.json` — 조사한 건물 이름(도로명주소 또는 VWorld id 기준)
- `manual_fixes.json` — 조각난 건물 통합·삭제. 좌표로 맞춘다
- `seeds.json` — 캡처의 건물 이름표 좌표. 붙은 동을 가르는 데 쓴다
- `meta_pos.json` — 건축물대장 이름의 좌표

`lib/housing_survey.dart`의 `kHousingSurvey`(월세)·`kHousingJeonse`(아파트 전세, 단지 모든 동에 표시)도 사람이 물어 모은 시세다
(2026-09). **지도에 뜨는 이름**(개발자 모드에서 고친 이름 포함)으로 건물에
붙으므로, 건물 이름을 바꾸면 여기도 같이 고친다 — `housing_survey_test`가
안 붙는 이름을 잡는다. 학생 제보와 함께 평균에 섞이고 Firestore엔 안 쓴다. 시세는 중앙값이 아니라 **평균**이다 — 방마다 값이 달라 겹치는 제보도 전부 두기로 했다(2026-09-27). 오타 하나가 평균을 끌고 가므로 제보 폼의 금액 상한(`housingAmountError`)을 풀지 않는다.

추출이 좋아지면 `manual_fixes.json` 항목이 죽는다. `build_index`가 "아직 쓰이는
merge 항목"을 찍으니 줄어들면 정리한다(한 번 22그룹 → 4그룹으로 줄였다).
