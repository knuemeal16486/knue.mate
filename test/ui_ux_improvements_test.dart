import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/calendar_screen.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/features/notice/notice_bookmark_service.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_screen.dart';
import 'package:knue_mate/onboarding_screen.dart';
import 'package:knue_mate/ui_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  group('KnueTokens 대비 보정 (20색 전수 검증)', () {
    test('밝은 색(노랑·라임·앰버)에서는 onAccent가 진한 잉크색으로 전환된다', () {
      for (final c in const [
        Color(0xFFFDD835), // 노랑
        Color(0xFFC0CA33), // 라임
        Color(0xFFFFB300), // 앰버
      ]) {
        expect(KnueTokens.onAccent(c), const Color(0xFF1C1C1E), reason: '$c');
        expect(KnueTokens.headerShadows(c), isEmpty);
        expect(
          _contrastRatio(c, KnueTokens.onAccent(c)),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('어두운/선명한 색(청람 블루·블랙)에서는 onAccent가 흰색과 그림자를 유지한다', () {
      for (final c in const [Color(0xFF2563EB), Color(0xFF000000)]) {
        expect(KnueTokens.onAccent(c), Colors.white);
        expect(KnueTokens.headerShadows(c), isNotEmpty);
      }
    });

    test('accentForeground는 라이트/다크 카드 배경 위에서 20색 모두 가독성을 확보한다', () {
      for (final seed in kColorPalette) {
        final lightFg = KnueTokens.accentForeground(seed, false);
        final darkFg = KnueTokens.accentForeground(seed, true);
        expect(
          _contrastRatio(lightFg, KnueTokens.surfaceLight),
          greaterThanOrEqualTo(3.0),
          reason: '라이트 카드 위 $seed → $lightFg 대비 부족',
        );
        expect(
          _contrastRatio(darkFg, KnueTokens.surfaceDark),
          greaterThanOrEqualTo(3.5),
          reason: '다크 카드 위 $seed → $darkFg 대비 부족',
        );
      }
    });
  });

  group('공통 UI 컴포넌트', () {
    testWidgets('KnueSegmentedControl 선택 전환 및 콜백 동작', (tester) async {
      String selected = 'a';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => KnueSegmentedControl<String>(
                items: const [
                  (value: 'a', label: '전체'),
                  (value: 'b', label: '행정'),
                ],
                selected: selected,
                onChanged: (v) => setState(() => selected = v),
                accentColor: const Color(0xFF2563EB),
                isDark: false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('행정'));
      await tester.pumpAndSettle();
      expect(selected, 'b');
    });

    testWidgets('KnueSearchBar 입력 및 지우기 버튼 동작', (tester) async {
      final ctrl = TextEditingController();
      String q = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => KnueSearchBar(
                controller: ctrl,
                query: q,
                hintText: '검색어 입력',
                onChanged: (v) => setState(() => q = v),
                accentColor: const Color(0xFF2563EB),
                isDark: false,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '장학');
      await tester.pump();
      expect(q, '장학');
      expect(find.byTooltip('검색어 지우기'), findsOneWidget);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pump();
      expect(q, '');
      ctrl.dispose();
    });

    testWidgets('KnueEmptyState & KnueErrorState 렌더링 및 재시도', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const KnueEmptyState(
                  icon: Icons.inbox_outlined,
                  title: '비어 있음',
                  subtitle: '항목이 없습니다',
                  isDark: false,
                ),
                KnueErrorState(onRetry: () => retried = true, isDark: false),
              ],
            ),
          ),
        ),
      );

      expect(find.text('비어 있음'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });

  group('딥링크 · 온보딩 · 일정 포커스', () {
    testWidgets('KnueOnboardingSheet 3단계 진행 및 건너뛰기 저장', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KnueOnboardingSheet())),
      );
      expect(find.text('어느 식당을 자주 가시나요?'), findsOneWidget);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('소속 학과를 선택해 주세요 (선택)'), findsOneWidget);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('자주 타는 버스를 골라주세요'), findsOneWidget);
      expect(find.text('시작하기'), findsOneWidget);
    });

    testWidgets('CalendarScreen initialDate로 지정한 달이 포커스된다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('ko_KR');
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(initialDate: DateTime(2026, 5, 15))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('청람일정'), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
    });

    test('parseRemoteHomeGreeting 및 11/28~29 특별 문구, 11/30 원복 동작', () {
      final day1 = DateTime(2026, 11, 28, 23, 0);
      final day2 = DateTime(2026, 11, 29, 12, 0);
      final day3 = DateTime(2026, 11, 30, 0, 1);

      expect(pickGreeting(day1), '임용 1차 모두 고생하셨어요');
      expect(pickGreeting(day2), '임용 1차 모두 고생하셨어요');
      expect(pickGreeting(day3), isNot('임용 1차 모두 고생하셨어요'));
      expect(parseRemoteHomeGreeting({'text': '  환영합니다  '}, day1), '환영합니다');
      expect(
        parseRemoteHomeGreeting({
          'text': '임용 1차 모두 고생하셨어요',
          'endDate': '2026-11-29',
        }, day2),
        '임용 1차 모두 고생하셨어요',
      );
      expect(
        parseRemoteHomeGreeting({
          'text': '임용 1차 모두 고생하셨어요',
          'endDate': '2026-11-29',
        }, day3),
        isNull,
      );
      expect(parseRemoteHomeGreeting({'text': '   '}, day1), isNull);
    });
  });

  group('공지 북마크(스크랩)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NoticeBookmarkService.bookmarks.value = const [];
    });

    test('토글로 저장·영속화·해제가 정확히 동작하고 설정 초기화에도 유지된다', () async {
      final n = Notice(
        id: 42,
        category: '장학금',
        group: 'MAIN',
        title: '2026-2 국가장학금 신청 안내',
        date: '2026-11-28',
        author: '학생지원과',
        link: 'https://www.knue.ac.kr/notice/42',
      );

      expect(NoticeBookmarkService.isBookmarked(n), isFalse);
      expect(await NoticeBookmarkService.toggle(n), isTrue);
      expect(NoticeBookmarkService.isBookmarked(n), isTrue);

      // 재로드 후에도 유지
      NoticeBookmarkService.bookmarks.value = const [];
      await NoticeBookmarkService.load();
      expect(NoticeBookmarkService.bookmarks.value.length, 1);
      expect(NoticeBookmarkService.isBookmarked(n), isTrue);

      // 설정 초기화해도 북마크는 보존
      await PreferencesService.resetSettings();
      await NoticeBookmarkService.load();
      expect(NoticeBookmarkService.bookmarks.value.length, 1);

      // 다시 토글하면 해제
      expect(await NoticeBookmarkService.toggle(n), isFalse);
      expect(NoticeBookmarkService.isBookmarked(n), isFalse);
    });

    testWidgets('NoticeBookmarksSheet에 저장한 공지가 표시되고 삭제할 수 있다', (tester) async {
      final n = Notice(
        id: 7,
        category: '학사공지',
        group: 'MAIN',
        title: '수강신청 정정 기간 안내',
        date: '2026-11-28',
        author: '학사관리과',
        link: 'https://www.knue.ac.kr/notice/7',
      );
      await NoticeBookmarkService.toggle(n);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NoticeBookmarksSheet(onOpen: (_) {})),
        ),
      );
      expect(find.text('저장한 공지 (1)'), findsOneWidget);
      expect(find.text('수강신청 정정 기간 안내'), findsOneWidget);

      await tester.tap(find.byTooltip('북마크 해제'));
      await tester.pumpAndSettle();
      expect(find.text('저장한 공지가 없어요'), findsOneWidget);
    });
  });
}
