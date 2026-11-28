// 탭 순서 화면 — onReorderItem은 newIndex를 "옮긴 뒤 최종 자리"로 준다(직접 1을 빼면 한 칸 어긋난다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/tab_edit_screen.dart';

List<String> _shownOrder(WidgetTester tester, List<AppTab> tabs) {
  final ys = {
    for (final t in tabs) t.name: tester.getTopLeft(find.byKey(ValueKey(t.name))).dy,
  };
  return ys.keys.toList()..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

void main() {
  testWidgets('맨 위 탭을 세 번째 자리로 옮기면 정확히 세 번째에 놓인다', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final start = List<AppTab>.from(PreferencesService.tabOrder.value);
    await tester.pumpWidget(const MaterialApp(home: TabEditScreen()));
    await tester.pump();

    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    // onReorder는 제거 전 인덱스 기준이라 0번을 2번 자리로 옮길 때 newIndex=3을 넘긴다.
    // ignore: deprecated_member_use
    list.onReorder!(0, 3);
    await tester.pump();

    final expected = List<AppTab>.from(start);
    expected.insert(2, expected.removeAt(0));
    expect(_shownOrder(tester, start), [for (final t in expected) t.name]);
  });
}
