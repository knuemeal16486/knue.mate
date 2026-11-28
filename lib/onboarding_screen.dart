import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'favorite_service.dart';
import 'notice_service.dart';
import 'ui_utils.dart';

/// 첫 설치 사용자를 위한 15초 개인화 온보딩 시트.
///
/// 1) 자주 가는 식당(기숙사/교직원)
/// 2) 내 학과 공지 고정(대학/대학원 게시판 목록에서 선택)
/// 3) 자주 타는 버스 노선 고정
/// 언제든 건너뛸 수 있으며, 완료 또는 건너뛰기 후에는 다시 뜨지 않는다.
class KnueOnboardingSheet extends StatefulWidget {
  const KnueOnboardingSheet({super.key});

  static const String kDoneKey = 'knue_onboarding_done_v1';

  /// 아직 온보딩을 완료하지 않은 신규 사용자에게 한 번만 시트를 띄운다.
  static Future<void> maybeShow(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kDoneKey) == true) return;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        builder: (_) => const KnueOnboardingSheet(),
      );
      await prefs.setBool(kDoneKey, true);
    } catch (_) {
      // 저장소 오류 시 앱 진입을 막지 않는다.
    }
  }

  @override
  State<KnueOnboardingSheet> createState() => _KnueOnboardingSheetState();
}

class _KnueOnboardingSheetState extends State<KnueOnboardingSheet> {
  int _step = 0;
  MealSource _selectedMeal = defaultSourceNotifier.value;
  String? _selectedDept;
  final Set<String> _selectedBuses = {'513'};
  String _deptQuery = '';

  static const List<({String route, String desc})> _busChoices = [
    (route: '513', desc: '교원대 ↔ 청주 시내 · 동부종점'),
    (route: '514', desc: '교원대 ↔ 가경동 · 시외버스터미널'),
    (route: '518', desc: '교원대 ↔ 오송역 · 보건의료행정타운'),
    (route: '913', desc: '미호종점 ↔ 교원대 ↔ 평동'),
  ];

  late final List<String> _allDepts = () {
    final colleges = KnueScraper.noticeTabStructure['대학/대학원'] ?? const {};
    return colleges.values.expand((e) => e).toList();
  }();

  Future<void> _finish() async {
    KnueHaptics.medium();
    await PreferencesService.saveMealSource(_selectedMeal);

    if (_selectedDept != null) {
      final boards = List<String>.from(PreferencesService.favoriteBoards.value);
      if (!boards.contains(_selectedDept)) {
        boards.insert(0, _selectedDept!);
        await PreferencesService.saveFavoriteBoards(boards);
      }
    }

    for (final route in _selectedBuses) {
      if (!FavoriteService.favoritesNotifier.value.contains(route)) {
        await FavoriteService.add(route);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KnueOnboardingSheet.kDoneKey, true);
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, '맞춤 설정이 홈 화면에 반영되었어요!');
  }

  Future<void> _skip() async {
    KnueHaptics.selection();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KnueOnboardingSheet.kDoneKey, true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final accentFg = KnueTokens.accentForeground(primary, isDark);
    final onBrand = KnueTokens.onAccent(primary);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(3, (i) {
                    final active = i == _step;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? accentFg
                            : KnueTokens.hairline(isDark),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    '건너뛰기',
                    style: TextStyle(
                      fontSize: 13,
                      color: KnueTokens.caption(isDark),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_step == 0) _buildMealStep(isDark, accentFg),
            if (_step == 1) _buildDeptStep(isDark, primary, accentFg),
            if (_step == 2) _buildBusStep(isDark, accentFg),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_step > 0) ...[
                  OutlinedButton(
                    onPressed: () {
                      KnueHaptics.selection();
                      setState(() => _step--);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: KnueTokens.hairline(isDark)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('이전'),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _step < 2
                        ? () {
                            KnueHaptics.selection();
                            setState(() => _step++);
                          }
                        : _finish,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: onBrand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _step < 2 ? '다음' : '시작하기',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealStep(bool isDark, Color accentFg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '어느 식당을 자주 가시나요?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '홈 화면 "오늘의 식단" 카드에 선택한 식당을 먼저 보여드려요.',
          style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark)),
        ),
        const SizedBox(height: 16),
        for (final src in MealSource.values) ...[
          _buildSelectTile(
            title: src.label,
            subtitle: src == MealSource.a
                ? '관리동 1층 · 조식/중식/석식'
                : '학생회관 1층 · 중식/석식 및 선택식 메뉴',
            selected: _selectedMeal == src,
            accentFg: accentFg,
            isDark: isDark,
            onTap: () {
              KnueHaptics.selection();
              setState(() => _selectedMeal = src);
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildDeptStep(bool isDark, Color primary, Color accentFg) {
    final q = _deptQuery.trim();
    final depts = q.isEmpty
        ? _allDepts
        : _allDepts.where((d) => d.contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '소속 학과를 선택해 주세요 (선택)',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '우리 학과 공지를 홈과 공지사항 맨 위에 고정해 드려요.',
          style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark)),
        ),
        const SizedBox(height: 12),
        KnueSearchBar(
          query: _deptQuery,
          hintText: '학과명 검색 (예: 초등교육과, 컴퓨터교육과)',
          onChanged: (v) => setState(() => _deptQuery = v),
          accentColor: primary,
          isDark: isDark,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: depts.map((dept) {
                final active = _selectedDept == dept;
                return ChoiceChip(
                  label: Text(dept),
                  selected: active,
                  selectedColor: primary,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? KnueTokens.onAccent(primary)
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  onSelected: (_) {
                    KnueHaptics.selection();
                    setState(() => _selectedDept = active ? null : dept);
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusStep(bool isDark, Color accentFg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '자주 타는 버스를 골라주세요',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '홈 "다음 버스" 타일에서 실시간 도착 정보를 바로 확인해요.',
          style: TextStyle(fontSize: 13, color: KnueTokens.caption(isDark)),
        ),
        const SizedBox(height: 14),
        for (final bus in _busChoices) ...[
          _buildSelectTile(
            title: '${bus.route}번',
            subtitle: bus.desc,
            selected: _selectedBuses.contains(bus.route),
            accentFg: accentFg,
            isDark: isDark,
            onTap: () {
              KnueHaptics.selection();
              setState(() {
                if (_selectedBuses.contains(bus.route)) {
                  _selectedBuses.remove(bus.route);
                } else {
                  _selectedBuses.add(bus.route);
                }
              });
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildSelectTile({
    required String title,
    required String subtitle,
    required bool selected,
    required Color accentFg,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accentFg.withValues(alpha: isDark ? 0.18 : 0.08)
              : KnueTokens.bg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accentFg : KnueTokens.hairline(isDark),
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: KnueTokens.caption(isDark),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? accentFg : KnueTokens.caption(isDark),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
