import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/more_screen.dart';

void main() {
  testWidgets('MoreScreen 진입 타일 렌더링', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    await tester.pump();
    expect(find.text('캠퍼스런'), findsOneWidget);
    expect(find.text('교직원 연락처'), findsOneWidget);
    // 설정은 하단 탭으로 이동되어 더보기 목록에서 제외됨
    expect(find.text('설정'), findsNothing);
  });
}
