// 식단 공유가 실제로 플랫폼까지 가는지, 무엇을 보내는지 본다.
//
// share_plus의 메서드 채널을 가로채면 기기 없이도 확인할 수 있다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'dev.fluttercommunity.plus/share/success';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// 공유 버튼이 달린 화면을 흉내 낸다 — shareMenu가 context를 쓰므로
  /// 트리에 붙은 진짜 BuildContext가 필요하다.
  Future<void> tapShare(
    WidgetTester tester,
    List<String>? items, {
    String? calories,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => shareMenu(
                context,
                DateTime(2026, 9, 22),
                MealSource.a,
                MealType.lunch,
                items,
                calories: calories,
              ),
              child: const Text('공유'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('공유'));
    await tester.pumpAndSettle();
  }

  testWidgets('메뉴가 있으면 공유 시트를 띄운다', (tester) async {
    await tapShare(tester, ['백미밥', '된장국', '제육볶음']);
    expect(calls, hasLength(1), reason: '플랫폼까지 가지 않았다');
    expect(calls.single.method, 'share');
    final text = (calls.single.arguments as Map)['text'] as String;
    expect(text, contains('백미밥'));
    expect(text, contains('제육볶음'));
    expect(text, contains('9/22'));
  });

  testWidgets('칼로리를 알면 같이 보낸다', (tester) async {
    await tapShare(tester, ['백미밥'], calories: '약 650kcal');
    final text = (calls.single.arguments as Map)['text'] as String;
    expect(text, contains('650kcal'));
  });

  testWidgets('메뉴가 없으면 공유하지 않고 그 사실을 알린다', (tester) async {
    // 예전엔 아무 말 없이 그냥 반환해서, 눌러도 아무 일이 없었다.
    await tapShare(tester, const []);
    expect(calls, isEmpty);
    expect(find.textContaining('메뉴'), findsWidgets);
  });

  testWidgets('공유가 실패해도 조용히 넘어가지 않는다', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error', message: '공유 실패');
        });
    await tapShare(tester, ['백미밥']);
    expect(find.textContaining('공유'), findsWidgets);
  });
}
