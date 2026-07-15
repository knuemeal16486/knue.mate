# KNUE_MoA → knue.mate 통합 설계 (1단계)

날짜: 2026-07-16
상태: 사용자 검토 대기

## 목표

KNUE_MoA(공지 크롤러 앱)의 핵심 기능을 knue.mate로 통합해, knue.mate를 학교생활 전반을 아우르는 단일 대학생활 앱으로 만든다. 이번 1단계는 MoA 기능 통합과 홈 대시보드 신설까지이며, 2단계(동아리 공연/행사 + 홍보 수익화)와 3단계(자취방 정보)는 별도 설계로 진행한다.

## 범위

### 포함 (1단계)
- 공지사항 크롤러 + 공지 피드 화면 (30+ 게시판: 본교, 도서관, 연수원, 학과별)
- 키워드 알림 (온디바이스: workmanager 백그라운드 크롤링 + 로컬 알림)
- 학사일정 + D-day + 개인 일정 (table_calendar)
- 홈 대시보드 탭 신설
- 하단 탭 재구성 (UX 감사 결과 반영)

### 제외
- MoA의 지원서 관리 기능
- 동아리 공연/행사 (2단계)
- 자취방 정보 (3단계)
- 서버 크롤링/FCM 키워드 푸시 (2·3단계에서 Firestore 백엔드 도입 시 재검토)

## 핵심 결정 사항

| 결정 | 선택 | 근거 |
|---|---|---|
| 이관 방식 | knue.mate 스타일로 재작성 | 크롤러 로직은 복사, 상태관리는 setState/ValueNotifier + SharedPreferences로 통일. Riverpod·Hive·lucide_icons 미도입 |
| 키워드 알림 | 온디바이스 (A안) | MoA에서 검증된 방식, 서버 비용 0. 백엔드 도입 후 FCM 승격 검토 |
| UI 배치 | 홈 대시보드 탭 신설 | 문화생활 확장의 기반 구조 |
| 탭 구성 | 5탭: 홈·식단·버스·지도·더보기 | UX 감사 결과 반영 (아래) |

## UX 감사 결과 (2026-07-16, 웹 빌드 실사용 기반)

### 발견 사항
- 🔴 웹 빌드 크래시: `Platform.isIOS` 등 dart:io 호출이 kIsWeb 가드 없이 사용됨 (버스·설정 탭 진입 시 앱 전체 다운). **감사 중 10개 호출부 수정 완료** (bus_screen, meal_screen, campus_map_screen)
- 🟡 식단 탭 이중 하단바 (앱 탭바 + 오늘/월간 서브탭바)
- 🟡 교직원 연락처가 지도 탭 내부에 매몰 (과 사무실/행정사무실)
- 🟢 버스 시간표 진입 시 컨트롤 4줄 적층 (서브탭→노선→평일/휴일→출발지)
- 🟢 식단 빈 상태 메시지가 원인(방학/오류/미등록) 구분 없음
- 일관성: 탭별 브랜딩 상이 (청람밥상/청람버스/CAMPUS RUN/캠퍼스맵)
- 접근성: 하단 탭 라벨 11px, 비선택 색 대비 부족 (white30/black26)
- 패키지명 `flutter_application_1` 잔존
- 잘 된 점: 탭 순서 편집+시작화면 지정, 버스 실시간 탭 정보 설계, 식단 홈 위젯, 테마 시스템

### 개선 방향 (사용자 확정)
사용 빈도 데이터(식단·버스 일 수회 > 공지·일정 주 단위 > 지도·런·연락처 간헐)에 맞춰 **식단·버스 중심 유지**. 홈 대시보드 최상단을 "오늘 브리핑"(다음 끼니 + 다음 버스)으로 구성해 홈이 시작 화면이 되어도 식단·버스 정보가 0탭으로 노출되게 한다.

## 화면 구조

### 하단 탭 (5개, 순서 편집 가능 유지)
1. **홈** (신설, 기본 시작 화면)
2. **식단** (기존)
3. **버스** (기존)
4. **지도** (기존)
5. **더보기** (신설) — 캠퍼스런, 설정, 교직원 연락처 진입점, (향후) 동아리·자취

기존 사용자 마이그레이션: 저장된 tabOrder에 run/settings가 있으면 더보기로 흡수, 홈을 맨 앞에 삽입. 시작 화면 지정 기능은 유지 (기존 식단 시작 유저는 식단 시작 유지).

### 홈 대시보드 (home_screen.dart, 신설)
세로 스크롤 카드 섹션. 각 섹션은 독립 위젯으로 분리해 2·3단계 카드 삽입이 쉬운 구조:
1. **오늘 브리핑 헤더** — 날짜, 다음 끼니 메뉴 요약(탭하면 식단 탭), 다음 버스 출발(탭하면 버스 탭)
2. **키워드 알림 카드** — 매칭된 새 공지 (키워드 미등록 시 등록 유도)
3. **최신 공지 피드** — 즐겨찾는 게시판 최근 5~7개 + "전체 보기" → 공지 화면
4. **학사일정/D-day 카드** — 다가오는 일정 + "전체 보기" → 캘린더 화면
5. *(자리 예약)* 동아리 공연 카드, 자취방 카드

### 공지 화면 (notice_screen.dart, 신설)
- 게시판 그룹 탭 (MAIN/ANNEX/LIFE/DEPT), 게시판 즐겨찾기, 키워드 관리 진입
- MoA home_page.dart의 UI를 knue.mate 디자인 언어(카드, 테마 색)로 재작성

### 캘린더 화면 (calendar_screen.dart, 신설)
- 학사일정(크롤링) + 개인 일정 + D-day. table_calendar 사용

### 더보기 화면 (more_screen.dart, 신설)
- 캠퍼스런, 설정, 교직원 연락처(지도 탭의 과/행정 사무실 데이터 재사용) 목록형 진입점

## 신규/변경 파일

| 파일 | 작업 | 출처 |
|---|---|---|
| `lib/home_screen.dart` | 신설 | — |
| `lib/notice_screen.dart` | 신설 | MoA `screens/home_page.dart` 재작성 |
| `lib/notice_service.dart` | 신설 | MoA `services/scraper_service.dart` 거의 그대로 (Hive→offline_cache 교체) |
| `lib/notice_model.dart` | 신설 | MoA `models/notice_model.dart` (Hive 어노테이션 제거) |
| `lib/calendar_screen.dart` | 신설 | MoA 캘린더/D-day 재작성 |
| `lib/keyword_alert_service.dart` | 신설 | MoA `services/notification_service.dart` 재작성 |
| `lib/more_screen.dart` | 신설 | — |
| `lib/constants.dart` | 수정 | AppTab에 home/more 추가, PreferencesService에 키워드·즐겨찾기 게시판·D-day 저장 추가, tabOrder 마이그레이션 |
| `lib/root_screen.dart` | 수정 | 새 탭 라우팅 |
| `lib/main.dart` | 수정 | keyword_alert workmanager task 등록 (기존 meal task와 이름 분리) |
| `pubspec.yaml` | 수정 | 의존성 (아래) |

## 데이터 흐름

- **포그라운드**: 홈 진입 시 즐겨찾는 게시판만 병렬 크롤링 → offline_cache 저장 → 카드 갱신. 공지 화면에서 게시판 열람 시 해당 게시판만 추가 크롤링
- **백그라운드**: workmanager 주기 task(1~2시간, 키워드 등록 시에만) → 새 글 diff → 키워드 매칭 → flutter_local_notifications 로컬 알림. 기존 `meal_widget_update_task`와 별도 task로 등록
- **저장**: 키워드·즐겨찾기·D-day·개인일정 = SharedPreferences (PreferencesService 경유), 공지 캐시 = offline_cache (파일)

## 의존성 변경

- 추가: `table_calendar`, `cp949_codec`, `euc` (일부 게시판 CP949/EUC-KR 인코딩)
- 버전 올림: `flutter_local_notifications` ^17 → ^21 (Android 설정 마이그레이션 확인)
- 미도입: riverpod, hive, lucide_icons, flutter_staggered_animations, uuid

## 에러 처리

- 게시판별 크롤링 실패 격리: 실패 게시판만 "불러오기 실패" 표시, 나머지 정상 렌더
- 오프라인: 캐시 표시 + 마지막 갱신 시각 노출
- 식단 빈 상태 메시지 원인 구분(방학/주말/네트워크)은 이번 범위에서 함께 수정 (경미)

## 검증

- 크롤러: MoA의 test_*_board 스타일 파서 테스트를 `test/`로 이식, 게시판 그룹별 파싱 검증
- 정적 검사: `flutter analyze` 통과 (기존 174 info 초과 금지)
- UI: 웹 빌드로 홈/공지/캘린더/더보기 화면 실사용 확인 (이번 감사에서 웹 크래시 수정 완료로 가능해짐)
- 백그라운드 알림: 디버그용 즉시 실행 트리거로 keyword task 수동 검증

## 함께 반영하는 UX 개선 (1단계 내)

- 식단 탭 서브탭(오늘/월간)을 상단 세그먼트로 이동 → 이중 하단바 제거
- 교직원 연락처를 더보기에서 직접 진입 가능하게
- 하단 탭 비선택 색 대비 개선
- 패키지명/앱 타이틀 정리 (`flutter_application_1` → `knue_mate`)는 별도 커밋으로 (안드로이드 applicationId는 스토어 등록 문제로 변경하지 않음, Dart package name만)

## 2·3단계 예고 (별도 설계)

- 2단계: 동아리 공연/행사 일정 + 홍보 수익화 (Firestore 백엔드, 등록/승인 흐름, 노출 로직)
- 3단계: 자취방 정보 수합 (데이터 소스 조사부터)
