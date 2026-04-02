import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
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
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _tempOrder.removeAt(oldIndex);
      _tempOrder.insert(newIndex, item);
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _saveAndExit() async {
    await PreferencesService.saveTabOrder(_tempOrder);
    if (mounted) Navigator.pop(context);
    showToast(context, "새로운 탭 구성이 적용되었습니다. ✨");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0F) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          "내비게이션 편집",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndExit,
            child: const Text(
              "완료",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              "길게 눌러서 순서를 변경하세요.\n첫 번째 탭이 앱의 시작 화면이 됩니다.",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tempOrder.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final animValue = Curves.easeInOut.transform(animation.value);
                    final elevation = lerpDouble(0, 10, animValue)!;
                    final scale = lerpDouble(1, 1.05, animValue)!;
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

                return Padding(
                  key: ValueKey(tab.name),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: isStartTab
                          ? Border.all(color: theme.primaryColor, width: 2)
                          : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tab.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(tab.icon, color: tab.color),
                      ),
                      title: Text(
                        tab.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: isStartTab
                          ? Text(
                              "시작 화면으로 지정됨",
                              style: TextStyle(
                                color: theme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            )
                          : const Text("길게 눌러서 이동"),
                      trailing: const Icon(Icons.drag_handle_rounded, color: Colors.grey),
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
