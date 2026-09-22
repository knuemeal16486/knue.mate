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

레이어마다 맡는 일이 다르다:

- **도로** = OSM 중심선(ODbL)을 굵기로 그어 그린다. 래스터에서 면으로 떠내던
  방식은 천장이 있었다 — 충실도를 올리면 굽고, 곧게 펴면 길이 제자리를 벗어났다.
- **포장면** = 광장·주차 앞마당만. OSM 도로가 덮는 통로는 빼둔다(안 빼면 매끈한
  도로선 옆으로 옛 가장자리가 톱니처럼 비어져 나온다).
- **건물** = 캡처에서 뽑아 직각으로 세운다.

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
자취방 지도와 캠퍼스맵 탭 두 곳에 있다. 지도를 새로 띄우는 화면을 만들면 같이 넣는다.

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

관리자 인증: 비밀번호를 앱이 들고 있지 않다. `admin_grants/{uid}` 문서를 만들 때
**보안 규칙이 서버에서** `app_config/admin`과 대조한다.

## 남은 일

**사용자 입력이 필요**
- 태성탑연로 386 **디저트39** — 위치를 모른다. 382(x=122)와 396-28(x=158) 사이,
  태성탑연로 북쪽 끝인 것까지만 좁혀 뒀다.
- 월탄3길 **26-4, 26-2** — 이름을 모른다.

**콘솔 작업이 필요**
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

추출이 좋아지면 `manual_fixes.json` 항목이 죽는다. `build_index`가 "아직 쓰이는
merge 항목"을 찍으니 줄어들면 정리한다(한 번 22그룹 → 4그룹으로 줄였다).
