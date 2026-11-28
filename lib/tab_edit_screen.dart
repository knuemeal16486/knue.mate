import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'ui_utils.dart';
import 'dart:ui';

class TabEditScreen extends StatefulWidget {
  const TabEditScreen({super.key});

  @override
  State<TabEditScreen> createState() => _TabEditScreenState();
}

class _TabEditScreenState extends State<TabEditScreen> {
  late List<AppTab> _tempOrder;

  @override
  void initState() {
    super.initState();
    _tempOrder = List.from(PreferencesService.tabOrder.value);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _tempOrder.removeAt(oldIndex);
      _tempOrder.insert(newIndex, item);
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _saveAndExit() async {
    // 드래그 중에는 임의 순서를 허용하지만, 저장 시점에는 항상 migrateTabOrder를
    // 거쳐 정규화한다: home은 (드래그로는 제거될 수 없지만) 목록에서 사라진 경우
    // 맨 앞에 재삽입되어 항상 존재가 보장된다. 그 외 탭 순서는 전부 자유.
    // 화면을 닫은 뒤에 토스트를 띄우므로 messenger를 미리 잡아 둔다. pop 뒤의
    // context로 ScaffoldMessenger.of를 부르면 이미 트리에서 떨어진 위젯이라
    // 예외가 난다(예전 코드는 mounted 확인도 없이 그렇게 하고 있었다).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final normalized = PreferencesService.migrateTabOrder(
      _tempOrder.map((t) => t.name).toList(),
    );
    await PreferencesService.saveTabOrder(normalized);
    navigator.pop();
    showToastOn(messenger, "새로운 탭 구성이 적용되었습니다. ✨");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = theme.primaryColor;
    final onBrand = KnueTokens.onAccent(color);
    final accentFg = KnueTokens.accentForeground(color, isDark);

    return Scaffold(
      backgroundColor: KnueTokens.bg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: AppleAppBarFlexibleSpace(
          themeColor: color,
          isDark: isDark,
        ),
        iconTheme: IconThemeData(color: onBrand),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          "내비게이션 편집",
          style: TextStyle(
            color: onBrand,
            fontWeight: FontWeight.w800,
            shadows: KnueTokens.headerShadows(color),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndExit,
            style: TextButton.styleFrom(foregroundColor: onBrand),
            child: Text(
              "완료",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                shadows: KnueTokens.headerShadows(color),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              "길게 눌러서 순서를 변경하세요.\n첫 번째 탭이 앱의 시작 화면이 됩니다.",
              style: TextStyle(
                color: KnueTokens.caption(isDark),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tempOrder.length,
              // ignore: deprecated_member_use
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final animValue = Curves.easeInOut.transform(animation.value);
                    final elevation = lerpDouble(0, 10, animValue)!;
                    final scale = lerpDouble(1, 1.03, animValue)!;
                    return Transform.scale(
                      scale: scale,
                      child: Material(
                        elevation: elevation,
                        color: Colors.transparent,
                        child: child,
                      ),
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final tab = _tempOrder[index];
                final isStartTab = index == 0;
                final ink = KnueTokens.inkAt(tab.index, isDark);

                return Padding(
                  key: ValueKey(tab.name),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: KnueTokens.surface(isDark),
                      borderRadius: BorderRadius.circular(KnueTokens.radiusCard),
                      boxShadow: KnueTokens.cardShadow(isDark),
                      border: isStartTab
                          ? Border.all(color: accentFg, width: 1.8)
                          : Border.all(
                              color: KnueTokens.hairline(isDark),
                              width: 0.5,
                            ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(tab.icon, color: ink, size: 21),
                      ),
                      title: Text(
                        tab.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: isStartTab
                          ? Text(
                              "시작 화면으로 지정됨",
                              style: TextStyle(
                                color: accentFg,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            )
                          : Text(
                              "길게 눌러서 이동",
                              style: TextStyle(
                                color: KnueTokens.caption(isDark),
                                fontSize: 12.5,
                              ),
                            ),
                      trailing: Icon(
                        Icons.drag_handle_rounded,
                        color: KnueTokens.caption(isDark),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
