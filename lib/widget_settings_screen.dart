/// 설정 → 홈 위젯. 위젯 미리보기와 위젯 설정(식당·테마·투명도·즉시 업데이트)을 한 화면에 모았다
/// (2026-11-25 — 설정 첫 화면의 절반을 차지하던 묶음을 옮겼다).
library;

import 'package:flutter/material.dart';

import 'constants.dart';
import 'settings_screen.dart' show SettingsChoiceOption, SettingsThemeOption;
import 'widget_preview.dart';

class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  double _localTransparency = widgetTransparency.value;

  Future<void> _forceUpdateWidget(BuildContext context) async {
    // 갱신을 기다리는 동안 화면이 닫힐 수 있으므로 messenger를 미리 잡는다.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text("위젯 갱신 중..."),
        duration: Duration(milliseconds: 800),
      ),
    );
    try {
      final hasMenu = await refreshMealWidgetNow();
      showToastOn(
        messenger,
        hasMenu ? "위젯 업데이트 완료!" : "위젯 업데이트 완료 (등록된 메뉴 없음)",
      );
    } catch (e) {
      showToastOn(messenger, "식단을 불러오지 못했어요");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = themeColor.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBorder = isDark ? null : Border.all(color: Colors.grey.shade300);
    final hint = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: isDark ? Colors.grey : Colors.grey.shade600,
    );
    BoxDecoration card() => BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: boxBorder,
        );
    return Scaffold(
      appBar: AppBar(title: const Text("홈 위젯")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 테마·투명도를 바꾸면 홈 화면에 나가지 않고 바로 본다.
          const WidgetAppearancePreview(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "표시할 식당",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<MealSource>(
                  valueListenable: widgetSource,
                  builder: (context, src, _) => Row(
                    children: [
                      SettingsChoiceOption(
                        label: MealSource.a.shortLabel,
                        isSelected: src == MealSource.a,
                        onTap: () async {
                          await saveWidgetSettingsAndUpdate(
                            widgetTransparency.value,
                            widgetTheme.value,
                            MealSource.a,
                            context,
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      SettingsChoiceOption(
                        label: MealSource.b.shortLabel,
                        isSelected: src == MealSource.b,
                        onTap: () async {
                          await saveWidgetSettingsAndUpdate(
                            widgetTransparency.value,
                            widgetTheme.value,
                            MealSource.b,
                            context,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "위젯 배경 테마",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: widgetTheme,
                  builder: (context, mode, _) => Row(
                    children: [
                      SettingsThemeOption(
                        label: "라이트",
                        icon: Icons.light_mode,
                        selected: mode == ThemeMode.light,
                        // 식단은 다시 안 받는다 — 모양만 바로 적용.
                        onTap: () => applyWidgetAppearance(
                          theme: ThemeMode.light,
                        ),
                      ),
                      SettingsThemeOption(
                        label: "다크",
                        icon: Icons.dark_mode,
                        selected: mode == ThemeMode.dark,
                        // 식단은 다시 안 받는다 — 모양만 바로 적용.
                        onTap: () => applyWidgetAppearance(
                          theme: ThemeMode.dark,
                        ),
                      ),
                      SettingsThemeOption(
                        label: "시스템",
                        icon: Icons.settings_brightness,
                        selected: mode == ThemeMode.system,
                        // 식단은 다시 안 받는다 — 모양만 바로 적용.
                        onTap: () => applyWidgetAppearance(
                          theme: ThemeMode.system,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "배경 투명도",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _localTransparency,
                        min: 0.0,
                        max: 0.8,
                        divisions: 8,
                        activeColor: currentColor,
                        onChanged: (v) {
                          setState(() => _localTransparency = v);
                          widgetTransparency.value = v;
                        },
                        // 손을 뗄 때 한 번, 식단은 다시 안 받는다.
                        onChangeEnd: (v) =>
                            applyWidgetAppearance(transparency: v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: currentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${(_localTransparency * 100).toInt()}%",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: currentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "투명도가 높을수록 위젯 배경이 투명해집니다. 테마·투명도는 식단·버스·공지 위젯에 모두 적용돼요.",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _forceUpdateWidget(context),
                    icon: const Icon(Icons.refresh),
                    label: const Text("위젯 데이터 즉시 업데이트"),
                    style: FilledButton.styleFrom(
                      backgroundColor: currentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "홈 화면에 위젯 추가하기",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "iPhone·iPad: 홈 화면 빈 곳을 길게 누르기 → 왼쪽 위 + (편집) → "
                  "KNUE Mate → 식단·버스·공지 중 고르기\n"
                  "잠금화면(iOS 16 이상): 잠금화면 길게 누르기 → 사용자화 → 위젯 추가 → KNUE Mate\n"
                  "Android: 홈 화면 빈 곳을 길게 누르기 → 위젯 → KNUE Mate",
                  style: hint,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
