import 'package:flutter/material.dart';

import 'housing_service.dart';

/// "내 조건 찾기" 조건 입력 시트.
///
/// 닫으면 고른 [HousingFilter]를 돌려준다(뒤로 가기로 닫으면 null).
/// 조건을 바꿀 때마다 몇 곳이 걸리는지 버튼에 바로 보여줘서, 조건을 너무
/// 빡빡하게 걸어 0곳이 되는 걸 시트를 닫기 전에 알 수 있게 했다.
class HousingFilterSheet extends StatefulWidget {
  final HousingFilter initial;
  final bool isDark;

  /// 지금 조건으로 몇 곳이 잡히는지 세어 주는 콜백.
  final int Function(HousingFilter) countMatches;

  const HousingFilterSheet({
    super.key,
    required this.initial,
    required this.isDark,
    required this.countMatches,
  });

  @override
  State<HousingFilterSheet> createState() => _HousingFilterSheetState();
}

class _HousingFilterSheetState extends State<HousingFilterSheet> {
  late HousingFilter _f = widget.initial;
  late final TextEditingController _deposit = TextEditingController(
    text: widget.initial.maxDeposit?.toString() ?? '',
  );
  late final TextEditingController _monthly = TextEditingController(
    text: widget.initial.maxMonthly?.toString() ?? '',
  );

  @override
  void dispose() {
    _deposit.dispose();
    _monthly.dispose();
    super.dispose();
  }

  /// 입력칸의 숫자를 필터에 반영한다. 비우면 그 조건은 해제된다 —
  /// copyWith의 null은 "안 바꿈"이라 여기서는 생성자를 직접 쓴다.
  void _syncNumbers() {
    setState(() {
      _f = HousingFilter(
        roomTypes: _f.roomTypes,
        maxDeposit: _deposit.text.trim().isEmpty
            ? null
            : int.tryParse(_deposit.text.trim()),
        maxMonthly: _monthly.text.trim().isEmpty
            ? null
            : int.tryParse(_monthly.text.trim()),
        includeMaintenance: _f.includeMaintenance,
        requiredFeatures: _f.requiredFeatures,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final sub = isDark ? Colors.white54 : Colors.black54;
    final count = widget.countMatches(_f);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            10,
            22,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  "내 조건 찾기",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "학생들이 남긴 제보를 기준으로 걸러요.",
                  style: TextStyle(fontSize: 12, color: sub),
                ),
                const SizedBox(height: 18),

                _label("방 구조", isDark),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: HousingRoomType.values.map((t) {
                    return FilterChip(
                      label: Text(
                        t.label,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _f.roomTypes.contains(t),
                      onSelected: (sel) => setState(() {
                        final next = {..._f.roomTypes};
                        if (sel) {
                          next.add(t);
                        } else {
                          next.remove(t);
                        }
                        _f = _f.copyWith(roomTypes: next);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                _label("보증금 · 월 부담 (이 금액 이하)", isDark),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deposit,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _syncNumbers(),
                        decoration: const InputDecoration(
                          labelText: "보증금",
                          suffixText: "만원",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _monthly,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _syncNumbers(),
                        decoration: const InputDecoration(
                          labelText: "월 부담",
                          suffixText: "만원",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _f.includeMaintenance,
                  onChanged: (v) =>
                      setState(() => _f = _f.copyWith(includeMaintenance: v)),
                  title: const Text(
                    "관리비 포함해서 계산",
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    _f.includeMaintenance ? "월세 + 관리비 기준" : "월세만 기준",
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ),
                const SizedBox(height: 10),

                _label("꼭 있어야 하는 조건", isDark),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kHousingFeatures.map((f) {
                    return FilterChip(
                      label: Text(f, style: const TextStyle(fontSize: 11.5)),
                      selected: _f.requiredFeatures.contains(f),
                      onSelected: (sel) => setState(() {
                        final next = {..._f.requiredFeatures};
                        if (sel) {
                          next.add(f);
                        } else {
                          next.remove(f);
                        }
                        _f = _f.copyWith(requiredFeatures: next);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        _deposit.clear();
                        _monthly.clear();
                        setState(() => _f = const HousingFilter());
                      },
                      child: const Text("조건 지우기"),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _f),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _f.isEmpty ? "전체 보기" : "$count곳 보기",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t, bool isDark) => Text(
    t,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white70 : Colors.black87,
    ),
  );
}
