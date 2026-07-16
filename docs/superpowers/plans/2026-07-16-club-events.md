# 동아리 공연/행사 + 홍보 수익화 (2단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 앱 내 화면에서 동아리 공연/행사를 등록·관리하고(포스터 포함), 결제 완료 행사를 "녹출"로 토글해 홈·목록 상단에 노출하며, 학생은 홈 카드/전체 목록에서 열람하고 녹출 신규 행사는 로컬 알림을 받는다.

**Architecture:** Firestore `club_events` 컬렉션 + Storage 포스터. 데이터 접근은 기존 `firebase_sync_service.dart`의 `FirebaseFirestore.instance` 패턴을, 캐시는 `NoticeCache`(SharedPreferences+JSON) 패턴을, 알림은 `keyword_alert_service.dart`(workmanager 폴링 + 순수 필터 함수)를 그대로 답습한다. UI는 기존 홈/더보기 위젯 부품(`_SectionCard`, `_CardLoading`, `_CardFailure`, `_MoreTile`)을 재사용한다.

**Tech Stack:** Flutter, cloud_firestore, firebase_storage(신규), image_picker(신규), workmanager, flutter_local_notifications, SharedPreferences, url_launcher

**Source repo:** `/Users/kaciaoz/Desktop/KNUE Mate/knue.mate` (여기서 작업, branch `feature/club-events`)

## Global Constraints

- 신규 상태관리/저장 라이브러리 금지: riverpod, hive, lucide_icons, uuid, flutter_staggered_animations 미도입. StatefulWidget + setState + ValueListenableBuilder 패턴 사용
- 추가 의존성은 정확히: `firebase_storage`, `image_picker` (버전은 pub 해석에 맡기되 SDK 제약 `^3.10.4` 및 기존 firebase_core `^4.5.0`/cloud_firestore `^6.1.3`와 호환되는 최신)
- `flutter analyze` 에서 error/warning 0 유지 (info는 기존 172개 수준 이하)
- 새 opacity 사용은 `.withValues(alpha: ...)` (deprecated `.withOpacity` 금지)
- 모든 신규 화면은 기존 디자인 언어를 따름: `Theme.of(context).cardColor` 카드, `themeColor.value` 포인트 색(`ValueListenableBuilder<Color>(themeColor)` 래핑), 다크모드 대응(`Theme.of(context).brightness`)
- UI 문자열은 한국어
- Android `applicationId` 절대 변경 금지
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- `NotificationService().showNotification(int id, String title, String body)` positional 시그니처 사용 (constants.dart:836, 기존 그대로)
- `showToast(BuildContext, String)` (constants.dart:145) 재사용

---

### Task 1: 의존성 추가 (firebase_storage, image_picker)

**Files:**
- Modify: `pubspec.yaml` (dependencies 블록, 61행 `euc: ^1.0.6+8` 다음)

**Interfaces:**
- Consumes: 없음
- Produces: `package:firebase_storage/firebase_storage.dart`, `package:image_picker/image_picker.dart` import 가능

- [ ] **Step 1: pubspec.yaml 수정**

`dependencies:` 블록에서 `euc: ^1.0.6+8` 줄 바로 아래에 추가:

```yaml
  firebase_storage: ^13.0.0
  image_picker: ^1.1.2
```

(버전 충돌 시 `flutter pub get` 출력의 권장 버전으로 조정 — firebase_storage는 firebase_core `^4.5.0`와 호환되는 라인, image_picker는 `^1.x` 유지)

- [ ] **Step 2: pub get 실행**

Run: `flutter pub get`
Expected: 해석 성공. 실패 시(버전 충돌) 충돌 패키지를 pub 권장 버전으로 조정 후 재실행

- [ ] **Step 3: analyze 확인**

Run: `flutter analyze --no-pub 2>&1 | tail -3`
Expected: error/warning 0 (info만, 기존 172 수준)

- [ ] **Step 4: 커밋**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: 동아리 행사 포스터용 firebase_storage, image_picker 추가

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: ClubEvent 모델

**Files:**
- Create: `lib/club_event_model.dart`
- Test: `test/club_event_model_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `class ClubEvent { String id, title, clubName, location, description; DateTime startDate; DateTime? endDate; String? posterUrl, externalLink; bool isFeatured; DateTime createdAt; }`
  - `Map<String, dynamic> toJson()` — 캐시용 (DateTime → ISO8601 String)
  - `factory ClubEvent.fromJson(Map<String, dynamic>)` — 캐시 복원
  - `Map<String, dynamic> toFirestore()` — Firestore 쓰기용 (DateTime → Timestamp, id 제외)
  - `factory ClubEvent.fromFirestore(String id, Map<String, dynamic>)` — Firestore 읽기용 (Timestamp → DateTime)

- [ ] **Step 1: 실패 테스트 작성** — `test/club_event_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_model.dart';

void main() {
  test('ClubEvent JSON 왕복 직렬화', () {
    final e = ClubEvent(
      id: 'abc123',
      title: '봄 정기공연',
      clubName: '노래패 청람',
      startDate: DateTime(2026, 5, 20, 18, 30),
      endDate: DateTime(2026, 5, 20, 20, 0),
      location: '학생회관 대강당',
      description: '동아리 봄 정기공연입니다.',
      posterUrl: 'https://example.com/poster.jpg',
      externalLink: 'https://forms.gle/xyz',
      isFeatured: true,
      createdAt: DateTime(2026, 5, 1, 9, 0),
    );
    final restored = ClubEvent.fromJson(e.toJson());
    expect(restored.id, 'abc123');
    expect(restored.title, '봄 정기공연');
    expect(restored.clubName, '노래패 청람');
    expect(restored.startDate, DateTime(2026, 5, 20, 18, 30));
    expect(restored.endDate, DateTime(2026, 5, 20, 20, 0));
    expect(restored.location, '학생회관 대강당');
    expect(restored.isFeatured, true);
    expect(restored.posterUrl, 'https://example.com/poster.jpg');
    expect(restored.externalLink, 'https://forms.gle/xyz');
  });

  test('선택 필드(endDate/posterUrl/externalLink) 없어도 왕복', () {
    final e = ClubEvent(
      id: 'x',
      title: 't',
      clubName: 'c',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: 'l',
      description: 'd',
      posterUrl: null,
      externalLink: null,
      isFeatured: false,
      createdAt: DateTime(2026, 5, 1),
    );
    final restored = ClubEvent.fromJson(e.toJson());
    expect(restored.endDate, isNull);
    expect(restored.posterUrl, isNull);
    expect(restored.externalLink, isNull);
    expect(restored.isFeatured, false);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/club_event_model_test.dart`
Expected: FAIL — `club_event_model.dart` 없음

- [ ] **Step 3: 구현** — `lib/club_event_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// 동아리 공연/행사 한 건. Firestore `club_events` 컬렉션 문서와 대응.
class ClubEvent {
  final String id;
  final String title;
  final String clubName;
  final DateTime startDate;
  final DateTime? endDate;
  final String location;
  final String description;
  final String? posterUrl;
  final String? externalLink;
  final bool isFeatured;
  final DateTime createdAt;

  ClubEvent({
    required this.id,
    required this.title,
    required this.clubName,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.description,
    required this.posterUrl,
    required this.externalLink,
    required this.isFeatured,
    required this.createdAt,
  });

  /// 캐시용 JSON (SharedPreferences 저장). DateTime → ISO8601.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'clubName': clubName,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'location': location,
        'description': description,
        'posterUrl': posterUrl,
        'externalLink': externalLink,
        'isFeatured': isFeatured,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ClubEvent.fromJson(Map<String, dynamic> json) => ClubEvent(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        clubName: json['clubName'] as String? ?? '',
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: (json['endDate'] as String?) != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        location: json['location'] as String? ?? '',
        description: json['description'] as String? ?? '',
        posterUrl: json['posterUrl'] as String?,
        externalLink: json['externalLink'] as String?,
        isFeatured: json['isFeatured'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  /// Firestore 쓰기용. id는 문서 ID이므로 제외, DateTime → Timestamp.
  Map<String, dynamic> toFirestore() => {
        'title': title,
        'clubName': clubName,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'location': location,
        'description': description,
        'posterUrl': posterUrl,
        'externalLink': externalLink,
        'isFeatured': isFeatured,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory ClubEvent.fromFirestore(String id, Map<String, dynamic> data) =>
      ClubEvent(
        id: id,
        title: data['title'] as String? ?? '',
        clubName: data['clubName'] as String? ?? '',
        startDate: (data['startDate'] as Timestamp).toDate(),
        endDate: (data['endDate'] as Timestamp?)?.toDate(),
        location: data['location'] as String? ?? '',
        description: data['description'] as String? ?? '',
        posterUrl: data['posterUrl'] as String?,
        externalLink: data['externalLink'] as String?,
        isFeatured: data['isFeatured'] as bool? ?? false,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/club_event_model_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/club_event_model.dart test/club_event_model_test.dart
git commit -m "feat: ClubEvent 모델 (Firestore/JSON 직렬화)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: ClubEventService (Firestore CRUD + Storage + 캐시)

**Files:**
- Create: `lib/club_event_service.dart`
- Test: `test/club_event_cache_test.dart`

**Interfaces:**
- Consumes: `ClubEvent` (Task 2)
- Produces:
  - `class ClubEventService`:
    - `static Future<List<ClubEvent>> fetchAll({bool forceRefresh = false})` — 캐시 있으면 즉시 반환+백그라운드 갱신, 없으면 Firestore 조회. startDate 오름차순 정렬
    - `static Future<void> upsert(ClubEvent event)` — id 비었으면 add, 있으면 set(merge)
    - `static Future<void> delete(String id)`
    - `static Future<String?> uploadPoster(String localPath)` — Storage `club_posters/<millis>.jpg` 업로드 후 다운로드 URL 반환. 실패 시 null
    - `static Future<void> setFeatured(String id, bool featured)` — isFeatured 필드만 갱신
    - `static Future<String?> fetchAdminPassword()` — `app_config/club_admin` 문서의 `password` 필드
  - `class ClubEventCache`:
    - `static Future<void> save(List<ClubEvent>)`
    - `static Future<List<ClubEvent>?> load()`
    - `static Future<DateTime?> lastUpdated()`

- [ ] **Step 1: 캐시 테스트 작성** — `test/club_event_cache_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/club_event_model.dart';
import 'package:knue_mate/club_event_service.dart';

ClubEvent _ev(String id) => ClubEvent(
      id: id,
      title: '공연$id',
      clubName: '동아리$id',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: '장소',
      description: '설명',
      posterUrl: null,
      externalLink: null,
      isFeatured: false,
      createdAt: DateTime(2026, 5, 1),
    );

void main() {
  test('ClubEventCache 저장/복원 왕복', () async {
    SharedPreferences.setMockInitialValues({});
    await ClubEventCache.save([_ev('1'), _ev('2')]);
    final loaded = await ClubEventCache.load();
    expect(loaded, isNotNull);
    expect(loaded!.length, 2);
    expect(loaded[0].id, '1');
    expect(loaded[1].title, '공연2');
  });

  test('캐시 없으면 null, lastUpdated도 null', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ClubEventCache.load(), isNull);
    expect(await ClubEventCache.lastUpdated(), isNull);
  });

  test('저장 시 lastUpdated 기록', () async {
    SharedPreferences.setMockInitialValues({});
    await ClubEventCache.save([_ev('1')]);
    expect(await ClubEventCache.lastUpdated(), isNotNull);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/club_event_cache_test.dart`
Expected: FAIL — `club_event_service.dart` 없음

- [ ] **Step 3: 구현** — `lib/club_event_service.dart`

`firebase_sync_service.dart`의 `FirebaseFirestore.instance` 패턴, `NoticeCache`의 SharedPreferences+JSON 패턴을 따른다.

```dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'club_event_model.dart';

/// 동아리 행사 Firestore CRUD + Storage 포스터 업로드 + 로컬 캐시.
class ClubEventService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const String _collection = 'club_events';

  /// 행사 목록. 캐시가 있으면 즉시 반환하고 백그라운드 갱신.
  static Future<List<ClubEvent>> fetchAll({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await ClubEventCache.load();
      if (cached != null && cached.isNotEmpty) {
        _fetchAndCache(); // await 없이 갱신
        return cached;
      }
    }
    return _fetchAndCache();
  }

  static Future<List<ClubEvent>> _fetchAndCache() async {
    try {
      final snapshot = await _db.collection(_collection).get();
      final events = snapshot.docs
          .map((d) => ClubEvent.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      await ClubEventCache.save(events);
      return events;
    } catch (e) {
      debugPrint('ClubEventService.fetchAll error: $e');
      final cached = await ClubEventCache.load();
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// id 비었으면 신규 추가, 있으면 갱신.
  static Future<void> upsert(ClubEvent event) async {
    final col = _db.collection(_collection);
    if (event.id.isEmpty) {
      await col.add(event.toFirestore());
    } else {
      await col.doc(event.id).set(event.toFirestore(), SetOptions(merge: true));
    }
  }

  static Future<void> delete(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }

  static Future<void> setFeatured(String id, bool featured) async {
    await _db.collection(_collection).doc(id).update({'isFeatured': featured});
  }

  /// 로컬 파일 경로의 포스터를 Storage에 올리고 다운로드 URL 반환. 실패 시 null.
  static Future<String?> uploadPoster(String localPath) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref('club_posters/$ts.jpg');
      await ref.putFile(File(localPath));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('ClubEventService.uploadPoster error: $e');
      return null;
    }
  }

  /// 관리자 비밀번호 (app_config/club_admin 문서의 password 필드).
  static Future<String?> fetchAdminPassword() async {
    try {
      final doc = await _db.collection('app_config').doc('club_admin').get();
      return doc.data()?['password'] as String?;
    } catch (e) {
      debugPrint('ClubEventService.fetchAdminPassword error: $e');
      return null;
    }
  }
}

/// 행사 목록 캐시 — NoticeCache와 동일 패턴 (SharedPreferences + JSON).
class ClubEventCache {
  static const _key = 'clubEventCache';

  static Future<void> save(List<ClubEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(events.map((e) => e.toJson()).toList()));
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<ClubEvent>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list
          .map((e) => ClubEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${_key}_ts');
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/club_event_cache_test.dart`
Expected: PASS (캐시는 SharedPreferences mock으로 검증. Firestore/Storage 메서드는 실기기/웹에서 검증 — 순수 캐시 로직만 단위 테스트)

- [ ] **Step 5: analyze + 커밋**

Run: `flutter analyze --no-pub 2>&1 | tail -3` → error/warning 0

```bash
git add lib/club_event_service.dart test/club_event_cache_test.dart
git commit -m "feat: ClubEventService (Firestore CRUD + Storage 포스터 + 캐시)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 녹출 신규 행사 알림 서비스

**Files:**
- Create: `lib/club_event_alert_service.dart`
- Modify: `lib/main.dart` (callbackDispatcher 분기 34-39행, 등록 138행)
- Test: `test/club_event_alert_test.dart`

**Interfaces:**
- Consumes: `ClubEvent` (Task 2), `ClubEventService.fetchAll` (Task 3), `NotificationService().showNotification(int, String, String)` (constants.dart), `kNoticeCheckTask` (keyword_alert_service.dart, 기존)
- Produces:
  - `const String kClubEventCheckTask = 'knue_club_event_check_task';`
  - `class ClubEventAlertService`:
    - `static List<ClubEvent> filterNewFeatured({required List<ClubEvent> events, required Set<String> notifiedIds})` — 순수 함수, isFeatured==true && id∉notifiedIds
    - `static Future<void> checkAndNotify()` — 백그라운드 task 본체
    - `static Future<void> syncRegistration()` — periodic task 등록

- [ ] **Step 1: 순수 필터 테스트 작성** — `test/club_event_alert_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_model.dart';
import 'package:knue_mate/club_event_alert_service.dart';

ClubEvent _ev(String id, {required bool featured}) => ClubEvent(
      id: id,
      title: '공연$id',
      clubName: '동아리',
      startDate: DateTime(2026, 6, 1),
      endDate: null,
      location: '장소',
      description: '',
      posterUrl: null,
      externalLink: null,
      isFeatured: featured,
      createdAt: DateTime(2026, 5, 1),
    );

void main() {
  test('녹출이면서 아직 안 알린 행사만 선별', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [
        _ev('1', featured: true),
        _ev('2', featured: false), // 녹출 아님
        _ev('3', featured: true),
      ],
      notifiedIds: {'1'}, // 이미 알림
    );
    expect(result.map((e) => e.id), ['3']);
  });

  test('전부 이미 알렸으면 빈 리스트', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [_ev('1', featured: true)],
      notifiedIds: {'1'},
    );
    expect(result, isEmpty);
  });

  test('녹출 없으면 빈 리스트', () {
    final result = ClubEventAlertService.filterNewFeatured(
      events: [_ev('1', featured: false)],
      notifiedIds: {},
    );
    expect(result, isEmpty);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/club_event_alert_test.dart`
Expected: FAIL — `club_event_alert_service.dart` 없음

- [ ] **Step 3: 구현** — `lib/club_event_alert_service.dart`

`keyword_alert_service.dart` 패턴을 따른다.

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';

const String kClubEventCheckTask = 'knue_club_event_check_task';

/// 녹출(featured) 신규 행사 로컬 알림. keyword_alert_service.dart 패턴 이식.
class ClubEventAlertService {
  static const _notifiedKey = 'club_notified_ids';

  /// 녹출이면서 아직 안 알린 행사 선별. 순수 함수 — 테스트 대상.
  static List<ClubEvent> filterNewFeatured({
    required List<ClubEvent> events,
    required Set<String> notifiedIds,
  }) {
    return events
        .where((e) => e.isFeatured && !notifiedIds.contains(e.id))
        .toList();
  }

  /// 백그라운드 task 본체.
  static Future<void> checkAndNotify() async {
    final events = await ClubEventService.fetchAll(forceRefresh: true);
    if (events.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final notified = prefs.getStringList(_notifiedKey) ?? [];

    final newItems = filterNewFeatured(
      events: events,
      notifiedIds: notified.toSet(),
    );

    // 스캔한 모든 녹출 항목을 알림 완료로 기록 (반복 알림 방지)
    final featuredIds = events.where((e) => e.isFeatured).map((e) => e.id);
    final merged = {...notified, ...featuredIds}.toList();
    final trimmed =
        merged.length > 200 ? merged.sublist(merged.length - 200) : merged;
    await prefs.setStringList(_notifiedKey, trimmed);

    if (newItems.isEmpty) return;

    final ns = NotificationService();
    await ns.init();
    if (newItems.length == 1) {
      await ns.showNotification(
        newItems[0].id.hashCode,
        '[${newItems[0].clubName}] 새 공연·행사',
        newItems[0].title,
      );
    } else {
      await ns.showNotification(
        newItems[0].id.hashCode,
        '새 공연·행사 ${newItems.length}건',
        '[${newItems[0].clubName}] ${newItems[0].title} 외 ${newItems.length - 1}건',
      );
    }
  }

  /// periodic task 등록 (앱 시작 시 항상 등록 — 녹출 행사는 관리자가 언제든 올릴 수 있음).
  static Future<void> syncRegistration() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerPeriodicTask(
        kClubEventCheckTask,
        kClubEventCheckTask,
        frequency: const Duration(hours: 2),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('club event alert registration error: $e');
    }
  }
}
```

- [ ] **Step 4: main.dart 연결**

`callbackDispatcher`의 task 분기(34-39행)를 확장 — 기존:

```dart
      if (task == kNoticeCheckTask) {
        await KeywordAlertService.checkAndNotify();
      } else {
        final targetDate = getWidgetTargetDate(defaultSourceNotifier.value);
        await fetchMealApi(targetDate, defaultSourceNotifier.value);
      }
```

를 다음으로 교체:

```dart
      if (task == kNoticeCheckTask) {
        await KeywordAlertService.checkAndNotify();
      } else if (task == kClubEventCheckTask) {
        await ClubEventAlertService.checkAndNotify();
      } else {
        final targetDate = getWidgetTargetDate(defaultSourceNotifier.value);
        await fetchMealApi(targetDate, defaultSourceNotifier.value);
      }
```

`main()`의 등록 블록(138행 `await KeywordAlertService.syncRegistration();` 다음 줄)에 추가:

```dart
        await ClubEventAlertService.syncRegistration();
```

import 추가 (main.dart 상단): `import 'club_event_alert_service.dart';`

- [ ] **Step 5: 테스트 + analyze + 커밋**

Run: `flutter test test/club_event_alert_test.dart && flutter analyze --no-pub 2>&1 | tail -3`
Expected: PASS, error/warning 0

```bash
git add lib/club_event_alert_service.dart lib/main.dart test/club_event_alert_test.dart
git commit -m "feat: 녹출 신규 행사 온디바이스 알림 (workmanager 폴링)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 학생용 전체 목록 화면

**Files:**
- Create: `lib/club_events_screen.dart`
- Test: `test/club_events_screen_test.dart`

**Interfaces:**
- Consumes: `ClubEvent`, `ClubEventService.fetchAll`, `ClubEventCache.lastUpdated`, `showToast` (constants.dart), `themeColor` (constants.dart), `url_launcher`
- Produces: `class ClubEventsScreen extends StatefulWidget`

**화면 구성:**
- AppBar "동아리 공연·행사", `ValueListenableBuilder<Color>(themeColor)` 래핑, `backgroundColor: color`, 흰색 아이콘 (notice_screen.dart:106-115 패턴)
- `RefreshIndicator`로 pull-to-refresh (`fetchAll(forceRefresh: true)`)
- 녹출 항목 상단 섹션(테마색 테두리 + "녹출" 뱃지) → 일반 항목 시작일 오름차순
- 카드: 포스터 썸네일(posterUrl 있으면 `Image.network`, 실패 시 아이콘 placeholder), 제목, 동아리명, 일시(intl `M월 d일 HH:mm`, ko_KR), 장소. 탭 → 상세 바텀시트(설명 전문 + externalLink 있으면 "신청/문의" 버튼 `launchUrl`)
- 하단 footer: 마지막 갱신 시각 (notice_screen.dart:369 패턴)
- 로딩/실패/빈 상태 처리

- [ ] **Step 1: 스모크 테스트 작성** — `test/club_events_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/club_events_screen.dart';

void main() {
  testWidgets('ClubEventsScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: ClubEventsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('동아리 공연·행사'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/club_events_screen_test.dart`
Expected: FAIL — `club_events_screen.dart` 없음

- [ ] **Step 3: 구현** — `lib/club_events_screen.dart`

화면 구성 명세대로. 골격:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';

class ClubEventsScreen extends StatefulWidget {
  const ClubEventsScreen({super.key});
  @override
  State<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends State<ClubEventsScreen> {
  List<ClubEvent> _events = [];
  bool _loading = true;
  bool _error = false;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() { _loading = true; _error = false; });
    try {
      final list = await ClubEventService.fetchAll(forceRefresh: force);
      final ts = await ClubEventCache.lastUpdated();
      if (!mounted) return;
      setState(() { _events = list; _lastUpdated = ts; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }
  // build/_buildList/_buildCard/_showDetail/_buildFooter 는 화면 구성 명세대로.
  // AppBar/themeColor/다크모드는 notice_screen.dart 패턴, 카드 셸은 cardColor + 테두리.
  // 녹출 항목: events.where((e) => e.isFeatured), 일반: 나머지 startDate 정렬.
  // 상세: showModalBottomSheet(설명 + externalLink launchUrl(LaunchMode.externalApplication)).
}
```

주의: 카드/상세/footer/로딩·실패·빈 상태를 `notice_screen.dart`의 대응 부품 스타일로 채운다. `.withValues(alpha:)` 사용, 한국어 문자열, 다크모드 분기.

- [ ] **Step 4: 테스트 통과 + analyze**

Run: `flutter test test/club_events_screen_test.dart && flutter analyze --no-pub 2>&1 | tail -3`
Expected: PASS, error/warning 0

- [ ] **Step 5: 커밋**

```bash
git add lib/club_events_screen.dart test/club_events_screen_test.dart
git commit -m "feat: 동아리 공연·행사 학생 목록 화면 (녹출 우선, 포스터/상세)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 관리자 화면 (비밀번호 게이트 + 폼 + 녹출 토글)

**Files:**
- Create: `lib/club_event_admin_screen.dart`
- Test: `test/club_event_admin_screen_test.dart`

**Interfaces:**
- Consumes: `ClubEvent`, `ClubEventService.{fetchAll,upsert,delete,uploadPoster,setFeatured,fetchAdminPassword}`, `image_picker`, `showToast`, `themeColor`
- Produces: `class ClubEventAdminScreen extends StatefulWidget`

**화면 구성:**
- 진입 시 비밀번호 다이얼로그 → `ClubEventService.fetchAdminPassword()`와 대조. 불일치 시 에러 스낵바 후 pop. (원격 비번이 null이면 "관리자 설정이 없습니다" 안내 후 pop)
- 통과 후 목록: 각 행사 카드에 제목·동아리·일시, 녹출 `Switch`(→ `setFeatured`), 수정(폼)·삭제(확인 다이얼로그) 버튼
- AppBar "동아리 행사 관리", 우상단 "+" → 추가 폼
- 추가/수정 폼(별도 `StatefulWidget` 또는 풀스크린 다이얼로그): 제목·동아리명·시작일시(showDatePicker+showTimePicker 또는 showDatePicker만)·선택 종료일·장소·설명·외부 링크 `TextField`, 포스터: `ImagePicker().pickImage(source: ImageSource.gallery)` → 로컬 미리보기 → 저장 시 `uploadPoster` → URL 확보 후 `upsert`
- 저장 성공 시 목록 새로고침 + 스낵바

- [ ] **Step 1: 스모크 테스트 작성** — `test/club_event_admin_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/club_event_admin_screen.dart';

void main() {
  testWidgets('ClubEventAdminScreen 비밀번호 게이트 렌더링', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ClubEventAdminScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    // 비밀번호 입력 UI가 뜨는지 (다이얼로그 or 인라인)
    expect(find.byType(ClubEventAdminScreen), findsOneWidget);
  });
}
```

주의: Firestore 접근이 테스트 환경에서 실패하므로, 비밀번호 확인은 실패/대기 상태로 렌더되어도 crash 없이 통과해야 한다. 게이트 UI는 `fetchAdminPassword` 완료를 기다리되, 미완료/에러 시에도 위젯 트리는 유지(스모크 테스트가 crash 없이 통과하도록).

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/club_event_admin_screen_test.dart`
Expected: FAIL — `club_event_admin_screen.dart` 없음

- [ ] **Step 3: 구현** — `lib/club_event_admin_screen.dart`

화면 구성 명세대로. 폼은 같은 파일 내 private `_EventFormPage`로 분리(관리 목록과 폼은 함께 변경되므로 한 파일). `image_picker` 사용, 로컬 파일 경로는 `XFile.path`. `calendar_screen.dart`의 D-day 추가 다이얼로그(showDatePicker + TextField)를 폼 입력 패턴 참고로.

- [ ] **Step 4: 테스트 통과 + analyze**

Run: `flutter test test/club_event_admin_screen_test.dart && flutter analyze --no-pub 2>&1 | tail -3`
Expected: PASS, error/warning 0

- [ ] **Step 5: 커밋**

```bash
git add lib/club_event_admin_screen.dart test/club_event_admin_screen_test.dart
git commit -m "feat: 동아리 행사 관리자 화면 (비밀번호 게이트/폼/녹출 토글)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: 홈 카드 + 더보기 숨김 진입점 연결

**Files:**
- Modify: `lib/home_screen.dart` (import, 상태 필드, `_loadClubEvents`, `_buildClubEventsCard`, 삽입 지점 218행)
- Modify: `lib/more_screen.dart` (버전 텍스트 133행 → 연속 탭 감지 + 관리자 화면 push)
- Test: 기존 `test/home_screen_test.dart` / `test/more_screen_test.dart` 통과 유지 (신규 스모크 불필요 — 회귀 방지)

**Interfaces:**
- Consumes: `ClubEvent`, `ClubEventService.fetchAll`, `ClubEventsScreen` (Task 5), `ClubEventAdminScreen` (Task 6), 기존 `_SectionCard`/`_CardLoading`/`_CardFailure` (home_screen.dart 내부 부품)
- Produces: 없음 (화면 조립)

- [ ] **Step 1: home_screen.dart — import + 상태 필드**

상단 import에 추가:

```dart
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'club_events_screen.dart';
```

`_HomeScreenState`의 일정 카드 상태 필드(`_upcomingDdays` 선언 다음, 50행 부근)에 추가:

```dart
  // 동아리 행사 카드
  bool _clubLoading = true;
  bool _clubError = false;
  List<ClubEvent> _clubEvents = const [];
```

- [ ] **Step 2: home_screen.dart — 로더 + initState 등록**

`initState`(52-60행)의 `_loadUpcoming();` 다음에 `_loadClubEvents();` 추가.

로더 메서드 추가 (다른 `_load*` 메서드 근처):

```dart
  Future<void> _loadClubEvents() async {
    if (mounted) setState(() { _clubLoading = true; _clubError = false; });
    try {
      final all = await ClubEventService.fetchAll();
      // 녹출 우선 + 다가오는(시작일 오늘 이후) 순, 상위 3건
      final now = DateTime.now();
      final upcoming = all
          .where((e) => (e.endDate ?? e.startDate).isAfter(now))
          .toList();
      upcoming.sort((a, b) {
        if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
        return a.startDate.compareTo(b.startDate);
      });
      if (!mounted) return;
      setState(() {
        _clubEvents = upcoming.take(3).toList();
        _clubLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _clubLoading = false; _clubError = true; });
    }
  }
```

- [ ] **Step 3: home_screen.dart — 카드 위젯 + 삽입**

삽입 지점(218행 `// 2단계: 동아리 공연 카드 ...` 주석)을 다음으로 교체:

```dart
                _buildClubEventsCard(color, isDark),
                const SizedBox(height: 12),
                // 3단계: 자취방 카드 삽입 지점
```

카드 빌더 추가 (`_buildUpcomingCard` 다음, `_SectionCard` 재사용):

```dart
  Widget _buildClubEventsCard(Color color, bool isDark) {
    return _SectionCard(
      isDark: isDark,
      title: "동아리 공연·행사",
      icon: Icons.celebration_outlined,
      color: color,
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClubEventsScreen()),
      ),
      child: _clubLoading
          ? const _CardLoading()
          : _clubError
              ? _CardFailure(onRetry: _loadClubEvents)
              : (_clubEvents.isEmpty
                  ? Text(
                      "예정된 공연·행사가 없습니다",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _clubEvents.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            if (e.isFeatured) ...[
                              Icon(Icons.star, size: 12, color: color),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                "${e.title} · ${e.clubName}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              _formatShortDate(e.startDate),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    )),
    );
  }
```

(`_formatShortDate`는 home_screen.dart에 이미 존재 — 496행)

- [ ] **Step 4: more_screen.dart — 숨김 진입점**

import 추가:

```dart
import 'club_event_admin_screen.dart';
```

`_MoreScreenState`에 탭 카운터 필드 + 핸들러 추가:

```dart
  int _versionTapCount = 0;

  void _onVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClubEventAdminScreen()),
      );
    }
  }
```

버전 텍스트(131-139행 `Center(child: Text("버전 5.8.0 (Final)", ...))`)를 `GestureDetector`로 감싸기:

```dart
              Center(
                child: GestureDetector(
                  onTap: _onVersionTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    "버전 5.8.0 (Final)",
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 5: 전체 테스트 + analyze**

Run: `flutter test && flutter analyze --no-pub 2>&1 | tail -3`
Expected: 전체 PASS (기존 home/more 스모크 테스트 포함), error/warning 0

- [ ] **Step 6: 커밋**

```bash
git add lib/home_screen.dart lib/more_screen.dart
git commit -m "feat: 홈 동아리 행사 카드 + 더보기 숨김 관리자 진입점

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 최종 검증 (웹 실사용 + Firestore 규칙 확인)

**Files:** 없음 (검증 전용)

- [ ] **Step 1: 전체 테스트 + analyze**

Run: `flutter test && flutter analyze --no-pub 2>&1 | tail -3`
Expected: 전체 PASS, error/warning 0, info 기존 수준 이하

- [ ] **Step 2: 웹 종합 검증**

Run: `flutter run -d web-server --web-port=8123` 후 브라우저에서:
1. 홈 대시보드에 "동아리 공연·행사" 카드 렌더 (데이터 없으면 빈 상태 또는 실패 상태가 정상)
2. 카드 "전체 보기" → `ClubEventsScreen` 진입, 녹출 우선 정렬 확인
3. 더보기 → 버전 텍스트 7회 탭 → 비밀번호 다이얼로그 → (테스트용 Firestore `app_config/club_admin` 문서 준비 시) 통과 후 관리 목록
4. 기존 홈/공지/캘린더/더보기 회귀 없음

주의: 웹은 Firestore 접근이 되지만, 포스터 업로드(image_picker)는 실기기 권장. 웹 CORS로 조회 실패 시 "불러오기 실패" 표시가 정상 동작인지 확인.

- [ ] **Step 3: Firestore 보안 규칙 확인 (배포 전 필수 안내)**

Firebase 콘솔에서 Firestore 규칙 확인 — `app_config/club_admin`(관리자 비밀번호)이 무제한 읽기로 노출되지 않는지 점검. 최소한 쓰기는 콘솔/인증 경로로만 가능하도록 규칙 설정 권장. (이 스텝은 코드 변경이 아니라 배포 담당자 안내 — 커밋 대상 아님)

- [ ] **Step 4: 모바일 실검증 (가능하면)**

`flutter run -d <device>`로 실기기에서 포스터 이미지 선택/업로드, 녹출 알림 즉시 테스트(관리자 화면 또는 디버그 트리거) 확인.

- [ ] **Step 5: 최종 상태 확인**

Run: `git log --oneline -8`
Expected: Task 1~7 커밋이 순서대로 존재

---

## Self-Review 체크 결과

- **Spec coverage:** 데이터 모델(T2), Firestore CRUD+Storage+캐시(T3), 녹출 알림(T4), 학생 목록 화면(T5), 관리자 화면+비번 게이트+포스터(T6), 홈 카드+숨김 진입점(T7), 의존성(T1), 검증+보안규칙 안내(T8) — 스펙 전 항목 커버
- **알려진 유보:** 녹출 자동 만료 없음(관리자 수동, 스펙 명시), 앱 내 결제 없음(스펙 제외), Firestore 규칙은 코드 밖 배포 항목(T8 안내)
- **Type consistency:** `ClubEvent.id: String`(T2=T3=T4=T5=T6=T7), `showNotification(int, String, String)` positional + `id.hashCode`로 int 변환(T4), `fetchAll({bool forceRefresh})`(T3=T5=T7), `filterNewFeatured({events, notifiedIds}) → List<ClubEvent>`(T4 테스트=구현), `_SectionCard`/`_CardLoading`/`_CardFailure` 재사용(T7, home_screen.dart 기존 부품 확인 완료)
