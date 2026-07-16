# 동아리 공연/행사 + 홍보 수익화 (2단계) 설계

날짜: 2026-07-16
상태: 사용자 승인 완료

## 목표

KNUE_MoA 통합(1단계)에 이어, knue.mate에 동아리 공연/행사 일정 기능과 그 위에 얹는 홍보 수익화(유료 노출)를 추가한다. 관리자(학교/운영진)가 앱 내 관리 화면에서 행사를 등록하고, 결제가 완료된 행사는 "녹출(featured)"로 토글해 홈 상단과 목록 상단에 우선 노출한다. 학생은 홈 카드와 전체 일정 화면에서 행사를 열람한다.

## 범위

### 포함 (2단계)
- 동아리 공연/행사 데이터 모델 + Firestore 저장소 (`club_events` 컬렉션)
- 포스터 이미지 업로드 (Firebase Storage)
- 관리자 화면: 비밀번호 게이트 + 행사 추가/수정/삭제 + 녹출 토글 (더보기에 숨겨진 진입점)
- 학생 화면: 홈 대시보드 카드 + 전체 일정 화면
- 녹출 행사 등록 시 온디바이스 폴링 기반 로컬 알림

### 제외
- 앱 내 결제(PG 연동) — 결제는 앱 밖에서 이루어지고, 앱은 노출만 담당
- 즉시 푸시(Cloud Functions + FCM) — 온디바이스 폴링으로 대체
- 녹출 기간 자동 만료 — 관리자가 수동으로 녹출 on/off
- 동아리 대표 직접 로그인/권한 체계 — 관리자 대행 등록만
- 자취방 정보 (3단계)

## 핵심 결정 사항

| 결정 | 선택 | 근거 |
|---|---|---|
| 등록 주체 | 관리자(학교/운영진) 대행 | 앱 내 계정/권한 체계 불필요, 범위 축소 |
| 관리자 입력 | 앱 내 관리 화면 | Firebase 콘솔 직접 입력보다 사용성·실수 방지 우수 |
| 수익화 | 결제는 앱 밖, 앱은 녹출 토글만 | PG 연동 불필요, 구현 대폭 단순화 |
| 포스터 | Firebase Storage 업로드 포함 | 행사 홍보 효과에 이미지 필수 |
| 알림 | 온디바이스 폴링 (녹출만) | 1단계 키워드 알림 패턴 재사용, 서버 비용 0 |
| 관리자 비밀번호 | Firestore 원격 설정 | 앱 재배포 없이 비밀번호 변경 가능 |
| 관리자 진입점 | 더보기 화면 버전 표기 연속 탭 (숨김) | 1단계 디버그 타일과 동일 패턴, 학생에게 미노출 |

## 데이터 모델

### Firestore `club_events` 컬렉션 (문서 = 행사 1건)

```
id: String (Firestore 문서 ID)
title: String            // 행사 제목
clubName: String         // 동아리명
startDate: Timestamp     // 시작 일시
endDate: Timestamp?      // 종료 일시 (선택)
location: String         // 장소
description: String      // 설명
posterUrl: String?       // Firebase Storage 다운로드 URL (선택)
externalLink: String?    // 신청/문의 외부 링크 (선택)
isFeatured: bool         // 녹출(유료) 여부, 관리자 수동 토글
createdAt: Timestamp     // 등록 시각 (정렬/신규 판정용)
```

### Firestore `app_config/club_admin` 문서

```
password: String         // 관리자 화면 비밀번호 (평문, 소규모 신뢰 관리자 대상)
```

## 신규/변경 파일

| 파일 | 작업 | 비고 |
|---|---|---|
| `lib/club_event_model.dart` | 신설 | `ClubEvent` 클래스 + `fromFirestore`/`toFirestore`/JSON(캐시용) |
| `lib/club_event_service.dart` | 신설 | Firestore CRUD + Storage 포스터 업로드. `firebase_sync_service.dart` 패턴 재사용. SharedPreferences 캐시(`ClubEventCache`, `OfflineCache` 패턴) |
| `lib/club_events_screen.dart` | 신설 | 학생용 전체 목록 (다가오는 순, 녹출 항목 상단 + 뱃지/테두리 강조). 상세는 카드 탭 시 다이얼로그/바텀시트 또는 `externalLink` 열기 |
| `lib/club_event_admin_screen.dart` | 신설 | 비밀번호 게이트 → 목록 + 추가/수정 폼(`image_picker`로 포스터 선택) + 녹출 토글 + 삭제 |
| `lib/club_event_alert_service.dart` | 신설 | workmanager 폴링 task(`club_event_check_task`), 녹출 신규 항목만 필터링(순수 함수) 후 로컬 알림. Task 7 `keyword_alert_service.dart` 패턴 재사용 |
| `lib/home_screen.dart` | 수정 | Task 10에서 남긴 `// 2단계: 동아리 공연 카드` 자리에 `_ClubEventCard` 삽입 (녹출/최신 2~3건 + "전체 보기" → `ClubEventsScreen`) |
| `lib/more_screen.dart` | 수정 | 버전 표기 연속 탭 → 관리자 화면 진입 (숨김) |
| `lib/main.dart` | 수정 | `callbackDispatcher`에 `club_event_check_task` 분기 추가, `main()`에서 폴링 등록 |
| `pubspec.yaml` | 수정 | `firebase_storage`, `image_picker` 추가 |

## 데이터 흐름

- **학생 (포그라운드)**: 앱 진입/화면 진입 시 Firestore 1회 조회 → `ClubEventCache` 저장 → 렌더. pull-to-refresh로 강제 갱신. 조회 실패 시 캐시 + 마지막 갱신 시각 표시 (공지 화면과 동일 패턴)
- **홈 카드**: 녹출 항목 우선 + 다가오는 행사 상위 2~3건, 캐시 우선 즉시 표시
- **백그라운드**: `club_event_check_task`(workmanager 주기 실행)가 Firestore를 폴링 → 이전에 알린 ID와 diff → `isFeatured=true` 신규 항목만 로컬 알림. 알림 완료 ID는 SharedPreferences에 기록(반복 알림 방지, 상한 트림)
- **관리자**: 비밀번호 확인(Firestore `app_config/club_admin`) → 폼 입력 → 포스터 있으면 Storage 업로드 후 URL 획득 → Firestore 문서 생성/수정. 녹출은 목록에서 스위치로 토글

## 화면 구조

### 학생: 홈 카드 (`_ClubEventCard`, home_screen.dart 내)
- 제목 "동아리 공연·행사", 녹출/다가오는 상위 2~3건 (제목·동아리명·일시·녹출 뱃지)
- "전체 보기" → `Navigator.push(ClubEventsScreen())`
- 로딩/실패 상태는 기존 카드들과 동일(스피너 / "불러오기 실패 · 다시 시도")

### 학생: 전체 일정 화면 (`club_events_screen.dart`)
- AppBar "동아리 공연·행사", pull-to-refresh
- 녹출 항목을 상단 섹션에 뱃지·테두리로 강조, 그 아래 일반 항목을 시작일 오름차순(다가오는 순)
- 카드: 포스터 썸네일(있으면), 제목, 동아리명, 일시, 장소. 탭 → 상세(설명 + `externalLink` 열기 버튼)
- 하단: 마지막 갱신 시각

### 관리자: 관리 화면 (`club_event_admin_screen.dart`)
- 진입 시 비밀번호 입력 다이얼로그 (Firestore 원격 비밀번호와 대조)
- 통과 후: 전체 행사 목록(수정/삭제/녹출 스위치), 우상단 "+" → 추가 폼
- 추가/수정 폼: 제목·동아리명·시작일(+선택 종료일, showDatePicker)·장소·설명·외부 링크·포스터(image_picker) 입력, 저장 시 Storage 업로드 + Firestore 반영
- UI 문자열 한국어, 기존 디자인 언어(cardColor/themeColor/다크모드) 준수

## 의존성 변경

- 추가: `firebase_storage`(포스터 업로드), `image_picker`(포스터 선택)
- 기존 재사용: `cloud_firestore`, `firebase_core`, `workmanager`, `flutter_local_notifications`, `url_launcher`

## 에러 처리

- Firestore 조회 실패 → 캐시 표시 + 마지막 갱신 시각, "불러오기 실패" 배너
- 포스터 업로드 실패 → 이미지 없이 저장하거나 재시도 안내(관리자 폼 내 에러 메시지)
- 비밀번호 오류 → 단순 에러 메시지 (잠금/재시도 제한 없음 — 소규모 신뢰 관리자 대상)
- 오프라인 → 캐시 데이터로 열람 가능, 관리자 쓰기는 온라인 필요 안내

## 검증

- 순수 함수: 녹출 신규 알림 필터링(이미 알린 ID 제외 + isFeatured만), 시작일 정렬
- 모델: `ClubEvent` Firestore/JSON 왕복 직렬화
- UI: 학생 목록 화면·관리자 화면 스모크 테스트
- `flutter analyze` error/warning 0 유지 (info 기존 수준 이하)
- 웹 빌드로 홈 카드·전체 목록·관리자 진입/폼 실사용 확인 (이미지 업로드는 실기기 권장)

## 보안 고려

- 관리자 비밀번호는 평문 저장이며 Firestore 보안 규칙으로 `app_config` 읽기를 제한할 수 없다면 클라이언트 노출 위험이 있음 → Firestore 규칙에서 `app_config` 문서를 인증된 경로로만 읽도록 제한하거나, 최소한 쓰기는 콘솔에서만 가능하도록 규칙 설정(구현 시 규칙 확인 항목으로 명시)
- `club_events` 쓰기는 앱 관리자 화면 경유만 의도하나, 클라이언트 SDK 특성상 규칙으로 강제 불가 → 2단계에서는 신뢰 관리자 전제, 3단계 백엔드 도입 시 서버 검증으로 승격 검토

## 3단계 예고 (별도 설계)

- 자취방 정보 수합 (데이터 소스 조사부터)
