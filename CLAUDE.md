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

스플래시 로고는 원본(`knue_icon.png`, 흰 정사각형)이 아니라 바탕을 투명하게 뺀
`splash_*.png`다 — 원본을 다크 모드 검은 바탕에 올리면 흰 네모가 떴다(2026-11-25).
로고를 바꾸면 `python tool/make_splash_images.py` → `dart run flutter_native_splash:create`.
Android 12+는 가운데 원만 보여서 `splash_android12*.png`는 글자를 원 안으로 줄여 둔다.
앱 로딩 화면(`_buildLoadingScreen`)도 다크 모드면 같은 바탕색(#0D0D0F)·`knue_icon_dark.png`.

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

### 3D 둘러보기 (2026-11-15)

```bash
flutter test test/view3d_preview.dart   # → build/view3d/*.png (위에서·언덕)
```

지도 HUD의 3D 버튼(`_openView3D`)으로 여는 별도 화면이다
(`lib/housing_view3d.dart` 렌더러·순수 함수, `lib/housing_view3d_screen.dart` 조작).
기존 지도는 시점마다 건물 모양을 미리 만드는 아이소메트릭이라 손가락을 따라
매 프레임 돌리거나 눈높이로 내려갈 수 없어서, 카메라 하나로 매 프레임 전부
투영하는 원근 렌더러를 따로 뒀다. 기존 지도의 회전은 여전히 버튼(45°)이다.

- **위에서 보기**: 한 손가락 이동, 두 손가락 비틀기(회전)·벌리기(확대)·위아래(기울이기).
- **걸어보기는 없앴다**(2026-11-16, 사용자 결정). 눈높이로 내려가 조이스틱으로
  걷던 모드다. 커밋된 적이 없어 git 기록에도 없다.
- **땅** = 언덕 격자(20m)에 위에서 본 지도 그림을 입힌 것. 그림은 앱의
  `HousingMapPainter`(평면 시점, 건물 없이)로 한 번 굽는다 — 미터당 1.5픽셀,
  2670×2490(약 27MB). 올리면 메모리가 적은 폰에서 위험하다. 눈높이에선 그림이
  번지므로 카메라 240m 안의 길만 도형으로 덧그린다.
- **언덕은 실측 고도다**(`assets/housing/campus_dem.json`, 30m 격자 64×60,
  해발 12~105m). `dart run tool/fetch_dem.dart`로 다시 만든다 — AWS Terrain
  Tiles(SRTM) 타일 2장을 받는다(키 없음). 정문이 34m로 알려진 값과 맞는다.
  SRTM은 지표면 높이라 건물·숲이 조금 섞이고 물 위에도 잡음이 있어 한 번
  고른다. 실제 비탈이 2~8%라 그대로는 평지처럼 보여서 **높이를 1.6배
  과장한다**(`kView3ReliefScale`, 건물 높이는 그대로).
- **기존 지도는 여전히 손 모델**(`CampusElevation`, 봉우리 5개)이다. 봉우리
  자리부터 실측과 다르다(모델의 "청람동산 정상" 자리는 실제 40m). 기존 지도는
  땅은 평평한 채 건물·도로만 띄우는 방식이라 실측을 넣으면 어긋나 보일 수
  있어 바꾸지 않았다.
- 벽 밑동은 그려지는 땅
  (20m 격자의 평평한 삼각형, `meshHeightAt`)보다 0.6m 아래까지 내린다 —
  부드럽게 보간한 높이(`groundAt`)에 맞추면 비탈에서 벽 밑에 틈이 뜬다.
- 건물을 눌러 상세를 여는 기능은 없다(이름표만 뜬다).
- 기기에서 조작감·속도는 확인하지 못했다(미리보기 PNG와 위젯 테스트로만 봤다).

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
- **포장면** = 교내 포장면 전체(`pavementFull` — 광장·건물 앞마당·주차장 바닥·
  보행로)를 **도로와 다른 크림색으로 도로 아래에** 깐다(2026-11-16). 그 전엔
  포장면을 아예 안 그려서 교내가 파란 바탕에 길과 건물만 뜬 것처럼 휑했다.
  색이 다르니 도로선 옆으로 나온 가장자리는 보도·마당으로 읽힌다 — 예전에 같은
  흰색으로 칠했을 땐 톱니로 보여서 OSM 통로를 뺀 조각(`pavement`)만 남겼던
  것이다. 조각은 에셋에 남아 있지만 앱은 더 안 쓴다.
  **면은 포장 픽셀이 아니라 잔디 쪽 경계에서 뜬다**(2026-11-16):
  `부지 − (바탕색 덩어리 ∪ 녹지 ∪ 물)`. 포장 픽셀은 건물·이름표 글씨 자리가
  비어 있어, 그걸로 뜨면 건물 둘레와 글씨마다 가장자리가 뜯겨 계단처럼
  보였다. 캡처에서 반듯한 건 잔디·화단(학교용지 바탕색) 경계다. 건물 자리는
  포장면에 든다(건물은 그 위에 그린다). 바탕색에 둘러싸인 섬 중 포장·건물색이
  40% 미만인 것은 이름표 글씨라 바탕으로 친다.
  `pavementFull`은 `trace_map`이 내고(주차 구획선을 메우고 세게 편다),
  `build_index`를 못 돌리는 동안은 `traced_raw.json`의 그 키만
  `campus_traced.json`에 옮겨 넣는다(다른 키는 건드리지 않는다).
- **바닥 구조물**(2026-11-16) = 코트·주차 구획·샛길. 캡처에서는 **치수만** 재고
  선은 앱이 긋는다(1픽셀짜리 선을 면으로 뜨면 얼룩이 된다).
  - `courts` — 초록 직사각형(중심·길이·폭·각도) 15곳. `courtLines`가 크기로
    종류를 갈라(축구장·테니스·일반 코트) 규격 비율로 선을 긋는다. 그 자리의
    뭉친 잔디·선 얼룩은 뺀다. 이름표 글씨에 가린 3곳("테니스장" 2면·"농구장")은
    `trace_map`의 `hidden`에 사람이 채웠다. 대운동장은 둥근 트랙 안이라 안 잡힌다.
  - `stallStrips` — 길가 주차칸의 사다리 띠 227개. `stallLadder`가 양쪽 줄과
    2.5m 간격 가로대를 긋는다. 캡처에서 잰 방향·위치는 띠마다 몇 도·1~2m씩
    흔들려서 **`trace_map`이 도로에 맞춰 낸다**(`lib/stall_align.dart`,
    순수 Dart — 도구와 테스트가 같이 쓴다): 가까운 차도와 나란히 돌리고,
    길에 걸쳤거나 3m 안으로 뜬 띠는 **그려지는 도로 가장자리에 딱 붙이고**,
    차도가 없는 띠는 옆 띠 방향을 따르고, 겹친 토막은 합치고, 모서리·
    가로지르는 도로 위로 나온 끝은 줄인다. 도로 폭 규칙(`osmRoadBaseWidth`)을
    앱의 `projectOsmRoads`와 같이 쓰므로 **도로 굵기나 `campus_roads.json`을
    바꾸면 `trace_map` → `merge_ground_layers.py`를 다시 돌린다.**
    주차칸 바닥과, 마주 보는 두 줄 사이 통로(`stallAisles` — 앱이 읽을 때
    계산, OSM에 없는 주차장 통로)는 포장면 색으로 깐다.
    코트 위에 잡힌 띠(코트 선을 잘못 읽은 것)는 뺀다. 기울어진 시점에서 도로는
    언덕 높이만큼 띄워 그리므로, 주차칸·통로·횡단보도도 **같은 높이로**
    투영한다(`projectOnRoadLevel`) — 바닥에 붙이면 언덕에서 길과 어긋난다.
  - `crosswalks`(2026-11-16) — 캡처의 횡단보도는 방향이 0°/90°뿐이고 126개 중
    97개가 도로 밖(계단·주차선을 잘못 읽은 것)이었다. `trace_map`이 차도 위의
    것만 남겨 중심선으로 옮기고 도로를 가로지르게 돌린다(`snapCrosswalks`,
    29개). 도로 노면이 흰색이라 줄은 회색으로, **도로를 그린 뒤에** 그린다.
    이 키도 `merge_ground_layers.py`가 옮긴다. 예전 주차장 면·빗살(7구역, 방향이 0°/90°뿐)과
    띠 위의 가짜 횡단보도는 이게 있으면 안 그린다.
  - `paths` — 폭 2m 안팎 샛길의 가운데 선 77줄(약 3.4km). OSM 도로·보행로가
    지나는 자리는 빠져 있다(그건 OSM 선으로 그린다). 폭은 `kFootpathWidth`.
    뼈대 138줄을 `lib/footpath_clean.dart`로 다듬은 것이다: OSM 길과 몇 m
    어긋나 그 옆에 나란히 뜬 조각(같은 길을 두 번 그린 것)을 빼고, 끝이 8m
    안으로 마주 본 토막을 잇고, 어디에도 닿지 않는 30m 미만 토막을 뺀다.
  - 에셋에 넣는 법: `dart run tool/trace_map.dart` 뒤
    `python tool/merge_ground_layers.py`. `build_index`를 못 돌리는 동안
    이 네 키(`pavementFull` 포함)만 글자 그대로 옮긴다 — 다른 키는 안 바뀐다.
  - 확인은 `flutter test test/map_topdown_preview.dart` — 캡처와 같은 범위·배율의
    `build/topdown_{core,north,south}.png`와 확대본 `topdown_zoom_*.png`.
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

### 원룸 임대 문의 연락처 (2026-10-16)

원룸촌을 직접 돌며 모은 연락처 33곳을 `housing_building_overrides`의
`landlordPhone`·`landlordPhone2`(`010-0000-0000` 형식)에 넣었다. 관리자 번호가
있는 건물은 **그 번호만** 보여 주고(`effectiveLandlordPhones` — 예전 학생 제보와
섞지 않는다) 연락처 제보를 받지 않는다(수정/제보·2번째 번호 제보 숨김). 시세 제보는
그대로 받는다. Firestore에 직접 쓴 뒤에는 `app_settings/housing_data`의 `version`을
올려야 학생 기기가 다시 받는다(앱 관리자 화면으로 고치면 저절로 올라간다).

`setOverride`는 문서를 **통째로 덮어쓴다**. 건물을 고치는 화면(지도 편집 시트,
관리자 목록 화면 `adminListEditedOverride`)은 화면에 칸이 없는 값을 기존
문서에서 옮겨야 한다 — 안 옮기면 외곽선·병합·가게·시세·2번째 번호가 지워진다
(2026-11-12에 관리자 목록 화면이 그랬다). 필드를 새로 더하면 두 곳에 다 넣는다.

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

**하루 읽기 한도(무료 요금제 5만 건)**도 찬다 — 2026-10-08 오후에 실제로 차서
식단 공용 캐시·버스·자취방이 한국 시각 16시까지 안 됐다. 9/20(1.6.1)부터
하루 2만~7만 건이다(그 전엔 4천 건). 읽기 수는 Cloud Monitoring의
`firestore.googleapis.com/document/read_count`로 본다(컬렉션별 구분은 안 된다).
줄인 것:
- 3D 지도(자취방·캠퍼스맵 지도 탭)가 열 때마다 관리자 수정 세 컬렉션(약 270건)을
  통째로 받던 것 → 학생 기기는 판 번호(`app_settings/housing_data`의 `version`)
  하나만 읽고, 바뀌었을 때·하루가 지났을 때만 서버에서 받는다
  (`HousingService.loadAdminEdits`). 관리자 쓰기(`setOverride`·`clearOverride`·
  위치 표시 저장/삭제)가 번호를 올린다. 관리자 기기는 실시간 리스너 그대로.
  **관리자 수정 컬렉션에 쓰는 코드를 새로 만들면 `bumpAdminEditsVersion()`을 부른다.**
- 하단 탭을 건너뛰면 사이 탭이 전부 만들어지던 것(홈→설정이 지도 탭을 지나며
  270건) → 떨어진 탭은 바로 넘어간다(`RootNavigationScreen._onTabTapped`).
- 1.6.3 이하는 업데이트 전까지 예전처럼 읽는다.

**강제 업데이트**(1.6.4부터, `lib/app_update.dart`): `app_settings/app_version`의
`androidBuild`·`iosBuild`(정수)보다 앱의 **빌드 번호**가 낮으면 닫을 수 없는 창을
띄워 스토어로 보낸다. 버전 이름이 아니라 빌드 번호로 비교한다 — App Store에
보이는 버전(1.8)은 App Store Connect의 표시 번호라 앱 안의 버전(1.6.x)과 다르다.
**스토어에서 실제로 받을 수 있게 된 뒤에** 그 플랫폼 번호만 올린다(심사 중·단계적
출시 중에 올리면 스토어에 아직 새 버전이 없는 사람이 창에 갇힌다). 문서가 없으면
아무것도 안 한다. App Store 앱 번호는 6757637319.
App Store에서 **승인된 버전 이름(pubspec의 1.6.x)은 다시 못 올린다** — "train version is closed"
(90186)·"must contain a higher version"(90062)으로 거부된다. 한 버전이 승인되면 다음 업로드
전에 이름도 올린다(1.6.5 → 1.6.6). 빌드 번호만 올리면 같은 이름 안에서 TestFlight용으로만 된다.

**iOS 빌드 번호는 Codemagic이 정한다**(2026-11-25): Workflow Editor의 iOS Build arguments에
`--build-number=$((BUILD_NUMBER + 200))`(Codemagic 빌드 횟수 + 200, 첫 적용 274). pubspec의 `+N`은 iOS에선
덮어써진다. 같은 번호를 다시 올리면 409(-19232)로 거부된다. `app-store-connect get-latest-testflight-build-number`는
빌드 단계에 업로드 키(`APP_STORE_CONNECT_PUBLISHER_PRIVATE_KEY`)가 없어 인자 처리에서 실패했다. 버전 이름은 여전히
pubspec에서 올린다. codemagic.yaml 방식은 쓰지 않기로 했다(사용자 결정).

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

## 홈 위젯 (식단·버스·공지)

- 식단: 앱·백그라운드가 넣은 값(`widget_title`·`widget_time`·`widget_menu`)을 그린다.
- 버스: 앱이 켜질 때 시간표 JSON(`bus_timetable_json`, `busWidgetTimetableJson`)을
  넣고, 위젯이 **스스로** 다음 차를 고른다. 학교에서 나가는 차만(513·514·518
  교원문화관 출발, 913 교원대 경유 평동행·미호행). iOS는 출발 시각마다 타임라인
  엔트리, Android는 `AlarmManager`(정확 알람 아님, 다음 출발이나 5분 뒤).
- 공지: 즐겨찾기 게시판마다 최신 글 1개를 먼저, 남는 자리는 그 게시판들의 다음 글을
  최신순으로(`noticeWidgetRows`, 최대 10줄 — 위젯 높이만큼 보이고 줄 사이를 벌려
  아래까지 채운다). 게시판 이름 색은 즐겨찾기 순서대로 8색(`noticeBoardColorIndex`,
  색 목록은 Swift·Kotlin에 따로 있어 일관성 테스트가 맞춰 본다). 앱이 공지 캐시를 바꿀
  때(`NoticeCache.save`)·즐겨찾기를 바꿀 때 `notice_rows_json`을 넣는다. **iOS
  위젯은 수집 파일(GitHub Pages)을 직접 받는다**(1시간, 지문이 바뀐 게시판만) —
  비상 직접 모드(`notice_feed_direct`)면 받지 않는다. Android는 받지 않는다.
- **위젯은 학교 서버·Firestore에 요청하지 않는다.** 받는 곳은 `notice_feed_base`뿐.
- 규칙이 세 곳에 있다: Dart(`lib/home_widgets.dart`, 테스트 있음)·Swift
  (`ios/MealWidget/`)·Kotlin(`BusWidgetProvider.kt`·`NoticeWidgetProvider.kt`).
  다음 차 규칙(같은 분은 지난 차)·링크 허용(https + knue.ac.kr 계열)을 바꾸면 셋 다.
  키 이름·kind·Manifest는 `test/native_id_consistency_test.dart`가 확인한다.
- 테마·투명도(`themeMode`·`transparency`)는 식단 위젯 설정 하나로 세 위젯에 같이. 투명도 0.7 이상이면
  배경화면 위 글씨로 보고 흐린 글씨·주황을 진하게 쓴다(`onWallpaper`, 기준값은 일관성 테스트).
- **모양(2026-11-24, 에브리타임식)**: 크고 굵은 머리글("점심"·"버스"·"공지", 제목색) + 흐린 보조 줄,
  항목 왼쪽에 옅은 색 막대(iOS `WidgetBar`·`WidgetBigHeader`, Android `drawable/widget_bar` +
  `WidgetColors.applyBar`). 식단은 세로 막대 대신 "점심" 밑에 가로 막대(앱 테마 색, small 48·medium 72, iOS
  `WidgetBigHeader(underline:)`, Android `meal_top_line`·`meal_side_line`). 막대 색: 버스는 노선 색(`kBusRouteColorIndex` /
  `ROUTE_COLOR_INDEX` — 게시판 색 목록에서 고름, 일관성 테스트), 공지는 게시판 색. 넓은 위젯(medium,
  Android 220dp 이상)은 머리글이 왼쪽 칸, 좁으면 위. 공지는 높이가 낮아 머리글이 한 줄.
  "오늘 점심"은 위젯이 "점심"(큰 글씨)·"오늘"(보조)로 나눠 쓴다(`mealHeaderParts`/`headerParts`).
- 앱 테마 색(`accent_light`·`accent_dark`): 앱이 켜질 때와 `themeColor`가 바뀔 때 `pushWidgetAccent`가
  넣는다(`widgetAccentHex` — 흰 배경엔 너무 밝은 색을 어둡게, 검은 배경엔 너무 어두운 색을 밝게).
  무지개 모드의 날마다 바뀌는 색은 앱을 열어야 위젯에 반영된다.
- 버스 위젯은 **두 종류**를 위젯 고르는 화면에서 사용자가 고른다: 노선별(`BusWidget` /
  `BusWidgetProvider`)과 곧 떠나는 차(`BusNextWidget` / `BusNextWidgetProvider`, 모든 노선을 합쳐 시각 순
  `upcomingDepartures`). 곧 떠나는 차는 **small·잠금화면만**(medium은 노선별과 겹쳐 뺐다, 2026-11-25 사용자 결정 —
  Android는 가로로 못 늘리고, 이미 넓힌 것도 small 모양으로 그린다). 같은 시간표·레이아웃을 쓰고, Dart는 둘 다 다시 그린다(`_updateBusWidgets`).
  가장 먼저 오는 차는 주황(`highlight`, `soonestRoutes`).
- Android 위젯 레이아웃에 맨 `View`를 쓰면 "Can't load widget"이 난다(RemoteViews 허용 목록) —
  빈 칸은 `FrameLayout`으로.
- iOS 17부터 시스템이 위젯 가장자리에 여백을 자동으로 넣는다. 각 위젯이 `.padding(14)`를 직접
  주므로 위젯 구성에 `.ownContentMargins()`(WidgetShared.swift)를 붙여 시스템 여백을 끈다 —
  새 위젯도 붙인다. 안 붙이면 여백이 두 번 들어가 small 식단 위젯에 메뉴가 3줄만 보였다.
- 식단 medium은 메뉴 하나에 한 줄, 넘치면 두 열(`mealMenuColumns`, 두 열에도 넘치면 "외 N개").
  small은 다 들어가면 한 줄에 하나씩, 넘치면 줄 폭에 맞춰 " · "로 묶는다(`mealMenuFlowLines`,
  메뉴가 줄 끝에서 끊기지 않고 마지막 줄은 "외 N개").
- iOS 위젯에 `Text(date, style: .relative)`(문자열 끼워 넣기 포함)를 쓰지 않는다 — 그걸 쓰던 버스 위젯
  (노선별 medium·곧 떠나는 차 둘 다)이 iPad에서 흰 화면이었다(2026-11-25). "N분 뒤"는 엔트리 시각 기준
  고정 글자(`busEtaLabel`)이고, 타임라인에 앞으로 120분 동안 매 분 엔트리를 넣어 줄인다.
- **식단 위젯은 스스로 끼니를 넘긴다**(2026-11-25, `lib/meal_widget.dart`). 앱이 두 식당의 오늘~7일
  식단과 끼니 끝나는 시각을 `meal_week_json`에 넣고(`pushMealWidgetWeek` — 캐시만 읽고 학교·Firestore에 묻지
  않는다. `MealCache.save/saveWeek`·위젯 갱신·앱 시작 때), 위젯이 지금 시각으로 고른다(`resolveMealWidget`).
  iOS는 끼니가 끝난 1초 뒤·자정마다 엔트리, Android는 그때 `AlarmManager`(`MEAL_TICK`). 규칙은 Dart 하나가 기준이고
  Swift·Kotlin은 옮긴 것 — `test/meal_widget_test.dart` 표를 바꾸면 둘 다. 끝나는 시각은 `mealTimeRangeFor`에서만 온다.
  옛 키(`widget_title`·`widget_time`·`widget_menu`)는 JSON이 없을 때(업데이트 직후)만 쓰인다.
  Swift·Kotlin 포트는 Linux에서도 돌려 볼 수 있다: swift.org 툴체인·kotlinc로 순수 함수만 떼어 같은 표를 넣는다.
- 식단 위젯을 앱에서 고칠 땐 `refreshMealWidgetNow()`를 부른다. `fetchMealApi`는 네트워크로 받았을 때만
  위젯을 쓰고 캐시면 그냥 돌려줘서, "위젯 데이터 즉시 업데이트"가 아무것도 안 바꿨다(2026-11-25).
  위젯 식당은 `widgetSource`다 — 식단 탭에서 다른 식당을 열어도 위젯은 안 바뀐다.
- **위젯에서 식당 바꾸기(2026-11-25)**: 식단 위젯 오른쪽 위(넓으면 왼쪽 칸 아래) 동그란 버튼. 앱을 열지 않고
  `meal_widget_source`(Dart `kMealWidgetSourceKey`)에 식당 id를 적는다 — iOS 17+는 위젯 확장 안
  `ToggleMealSourceIntent`(MealWidget.swift — 새 파일을 만들면 project.pbxproj에 넣어야 해서 같은 파일에 뒀다),
  iOS 15·16은 버튼이 없다. Android는 `MEAL_TOGGLE_SOURCE` 브로드캐스트. 이 값이 앱 설정(`widgetSource`)보다
  먼저고, 앱에서 위젯 식당을 바꾸면 지운다(`clearMealWidgetSourceOverride`). 다음 식당 규칙은
  `nextMealWidgetSource`(Dart·Swift·Kotlin 같다).
- **글자·여백 규칙(2026-11-25)**: iOS `WidgetType`·`WidgetSpace`(WidgetShared.swift) = Android
  `res/values/widget_dimens.xml`. 머리글 24(넓은 칸)/20(좁은 칸), 강조 16/14, 본문 13, 보조 12, 캡션 11, 여백 14.
  화면 코드·레이아웃에 숫자를 직접 쓰지 않는다(일관성 테스트가 잡는다). 안내 문구는 `WidgetMessage` 하나.
- **시스템이 칠하는 모드**: 위젯 구성은 `WidgetEnvReader { env in …EntryView(env: env) }`로 감싼다.
  틴트 홈 화면·잠금화면(fullColor 아님)에선 막대를 진하게, 머리글·막대·가장 빠른 차는 `widgetAccentableCompat()`.
  StandBy처럼 배경이 빠지면 앱 테마 대신 기기 설정을 따른다(라이트 고정이면 검은 바탕에 검은 글씨가 됐다).
- **잠금화면 위젯(2026-11-25, iOS 16+)**: 새 kind가 아니라 같은 위젯에 잠금화면 크기를 더했다
  (`widgetFamilies(home:lock:)`). 곧 떠나는 차(`BusLockView` — inline·circular·rectangular)와 식단
  (`MealLockView` — inline·rectangular)만. 노선별 버스·공지는 넣지 않았다. 화면은 `family.isAccessory`로
  가르고, 시스템이 한 색으로 칠하므로 색 막대·배경 없이 글자만 쓴다(배경은 `.widgetBackground(Color.clear)` —
  빼면 iOS 17에서 빈 위젯). 버스 "N분 뒤"는 기존 매 분 엔트리를 그대로 탄다. Android엔 잠금화면 위젯이 없다.
- iOS 위젯은 모두 `MealWidget` 확장 하나(`MealWidgetBundle`)에 들어 있다 — 새 파일은
  MealWidget 타깃 Sources에도 넣는다.
- Android 위젯 확인: 에뮬레이터 `HomeWidgetPreferences.xml`을 `run-as`로 덮고
  `adb install -r`이면 다시 그린다.

## 사용 통계 (2026-11-15)

Firebase Analytics(`lib/analytics.dart`)로 **하단 탭 조회만** 센다 — "식단만 보고
끈다"를 숫자로 보려고 넣었다. 화면 이름은 `tab_home`·`tab_meal`·… 고정이고
(바꾸면 추세가 끊긴다), 탭을 옮길 때·앱을 켤 때·백그라운드에서 돌아올 때 적는다.
개발 빌드는 세지 않는다. 이벤트를 더하면 스토어 데이터 수집 고지와
개인정보처리방침도 같이 고친다. iOS에는 `GoogleService-Info.plist`가 없어서
(Dart 옵션으로만 초기화) 앱이 켜진 직후의 자동 이벤트 일부가 빠질 수 있다.

## 식단 탭 광고 자리 (2026-11-12, 사용자 결정)

식단 탭은 가장 자주 보는 화면이라 **광고를 식단 카드 아래**에 둔다(0309885에서
위로 올렸던 것을 되돌림 — 맨 위 광고는 지저분해 보였다). 대신 처음 식단을
불러오면 한 번 살짝 내려 광고까지 보이게 한다(`_revealAdOnce`: 이미 보이면
안 움직이고, 사용자가 먼저 스크롤했으면 건드리지 않는다). 버스 탭 광고는
그대로(지나간 버스와 다음 버스 사이).

## 버스 — 노선 데이터·방향·도착 시간 (2026-11-12)

```bash
dart run tool/fetch_bus_route_stops.dart   # 노선 개정 시 → lib/bus_route_snapshot.dart
flutter test test/bus_preview.dart         # 버스 탭 화면 → build/bus_preview/*.png
```

버스 탭을 고치면 `bus_preview`로 그림을 보고 확인한다(실시간·빈 상태·시간표·
노선도 시트, 밝은/어두운 모드). 기기 없이 실제 위젯을 그린다 —
`BusAppScreen(previewBuses:, previewNearby:)`로 네트워크·Firebase를 건너뛴다.
글꼴은 Windows의 Noto Sans KR을 읽는다.

**시간대로 짐작한 값을 실제처럼 보여 주지 않는다.** 혼잡도·교통 상황은 API에
없어서 시간대로 짐작했는데, 모든 카드에 같은 "보통(예상)"이 붙어 잡음이었다 —
카드·시트·요약에서 뺐다(2026-11-12). 실제 혼잡도 데이터가 생기면 다시 붙인다.

- **노선 스냅샷**: 운영 빌드엔 노선정보 키(`BUS_ROUTE_API_KEY`)가 없어서 앱이
  `lib/bus_route_snapshot.dart`(10개 노선 정류장의 순서·방향·좌표·번호)를 쓴다.
  `fetchRouteStops`가 API에 실패하면 스냅샷을 준다. 예전 손글씨 목록
  (`bus_route_data.dart`의 `routeStops`)은 실제와 달랐다(511 상행 끝이 조치원역,
  747이 오송역↔오송역, 정류장 1/3~1/4만) — 이제 노선도는 스냅샷으로 그린다.
  노선 표는 `bus_model.dart`의 `kBusRoutes` 하나다(도구 목록과 같아야 한다).
- **방향은 행선지로 보여 준다**(`busDirectionLabel`). "상행"의 뜻이 노선마다
  다르다 — 513 상행 = 교원대로 들어오는 차, 511 상행 = 오송역 가는 차. 버스 탭
  구역은 "청주 방면 / 오송·조치원 방면"(`busDirectionsFor`). 513·514는 두 방향
  다 청주 구역(종점에서 돌아 나간다), 518은 두 방향 다 오송 구역.
- **공용 문서에 방향을 적는다**(`direction`·`etaFromApi`). 예전엔 안 적어서 공용
  문서로 받는 기기에선 모든 차가 "상행"이었다. 방향이 없는 옛 문서(1.6.4 이하가
  쓴 것)는 정류장 순번으로 다시 정한다.
- **도착 시간**: 기준 정류장 네 곳(탑연삼거리 3308 오송 쪽·3309 청주 쪽, 교원대
  3334·2633)의 정류장 도착 정보를 받아 남은 정거장이 같은 차에 붙이고
  (`resolveVehicleEtas`), 뒤차는 그 노선의 실제 속도로 어림한다. 공용 문서를
  쓰는 기기만 부른다. API는 **종점으로 들어오거나 종점에서 나가는 차엔 예측을
  안 준다** — 513·514는 어림값("약 n분")으로 남는다.
- **513·514는 월탄1리를 지나면 위치가 끊긴다**(사용자 관찰). 공용 문서에 차가
  정류장에 처음 보인 시각(`atStopSince`)을 적어 두고, 월탄1리 뒤 사라진 차는
  **지난 뒤 3분**까지 "곧 도착", 그 뒤 2분은 "도착"으로 남긴다
  (`carryTerminalApproach`, 사용자 결정). 518(4031 → 종점)은 확인 안 했다.
- **정류장은 번호 대신 "~ 방면"(다음 정류장)**으로 보여 준다(`kStopHeadingLabels`,
  정류장 id 기준 — 번호는 세종 정류장과 겹친다). 사용자가 정한 이름: 3331 교원대
  후문, 3333 월탄1리, 4031 한국교원대, 3308 궁평3리, 3309 월곡초등학교 방면.
  3330(월탄1리 정류장 자체)은 사용자가 "월탄1리 방면"이라 했으나 다음 정류장
  규칙대로 "교원대 방면"으로 적었다. 교원대 종점(3334·2633)은 카드에서 "교원대".

## 버스 — 가까운 정류장 (2026-11-12)

버스 탭 [실시간 위치] 맨 위 카드(`lib/nearby_stop_card.dart`, 로직은
`lib/nearby_stop.dart`). 탭을 열면 위치 권한을 바로 묻고(거절하면 그 실행 동안
다시 묻지 않는다), 1km 안 가까운 정류장 4곳 중 하나의 도착 정보를 **노선 전부**
보여 준다. 앱의 10개 노선은 색으로 표시한다. 노선 카드(차량 위치로 어림)와는
다른 API다 — TAGO 정류소정보 `getCrdntPrxmtSttnList` + 도착정보
`getSttnAcctoArvlPrearngeInfoList`. 둘 다 기존 `BUS_API_KEY`로 된다.

- **도시 코드는 정류장마다 다르다.** 청주 터미널엔 세종(12) 정류장이 청주
  정류장과 같은 자리·같은 번호로 겹쳐 있고, 세종 정류장을 33010으로 물으면 빈
  결과가 온다. 같은 번호·40m 안은 하나로 합치고 각자의 코드로 물어 합친다.
- 같은 이름이 길 양쪽에 있다(한국교원대정문 2107·3333) — 번호로 구분해 보여 준다.
- 기기마다 부른다(공용 문서 없음). 화면이 보일 때만 30초마다, 같은 정류장은
  20초 안에 다시 안 받고, 100m 안 움직이면 근처 정류장을 다시 안 찾는다.
  공공데이터포털 서비스별 하루 트래픽 한도를 넘기면 이 카드만 멈춘다.
- iOS 위치 권한 문구(Info.plist)에 버스 정류장 찾기를 넣었다. 용도가 문구에
  없으면 심사에서 걸린다.

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
- iOS 식단 위젯: `MealWidget` 타깃은 등록했다(2026-11-23, 번들 id
  `com.knue.knuemate.MealWidget`, 기본 구성 `Flutter/Generated.xcconfig`라 버전·빌드
  번호가 앱과 같다). 이때 Runner에도 `Runner.entitlements`(App Group·푸시)를 처음
  연결했다. Apple Developer의 App Group `group.knue.meal`과 두 App ID도 끝냈다
  (개발 프로파일에 그룹·푸시가 들어간 것 확인). 남은 건 Codemagic이 위젯용 배포
  프로비저닝 프로파일도 받게 하는 것.

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
