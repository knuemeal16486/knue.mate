import 'package:flutter/material.dart';

import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_service.dart';

/// 자취방 원룸 이름·시세·후기 제보 바텀시트
class HousingReportSheet extends StatefulWidget {
  final BaseBuilding building;
  final bool isDark;
  final Future<void> Function() onSubmitted;

  const HousingReportSheet({
    super.key,
    required this.building,
    required this.isDark,
    required this.onSubmitted,
  });

  @override
  State<HousingReportSheet> createState() => _HousingReportSheetState();
}

class _HousingReportSheetState extends State<HousingReportSheet> {
  final _form = GlobalKey<FormState>();
  final _deposit = TextEditingController();
  final _rent = TextEditingController();
  final _fee = TextEditingController();
  final _review = TextEditingController();
  final _contactPhone = TextEditingController();
  String? _selectedOneRoomId;
  HousingRoomType? _roomType;
  final Set<String> _features = {};
  final Set<String> _drawbacks = {};
  final Set<String> _utilities = {};
  bool _submitting = false;

  @override
  void dispose() {
    _deposit.dispose();
    _rent.dispose();
    _fee.dispose();
    _review.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final phone = _contactPhone.text.trim();
      final report = HousingReport(
        buildingId: widget.building.id,
        deposit: int.parse(_deposit.text.trim()),
        monthlyRent: int.parse(_rent.text.trim()),
        maintenanceFee: _fee.text.trim().isEmpty
            ? null
            : int.tryParse(_fee.text.trim()),
        features: _features.toList(),
        drawbacks: _drawbacks.toList(),
        contactPhone: phone.isEmpty ? null : phone,
        oneRoomId: _selectedOneRoomId,
        roomType: _roomType,
        review: _review.text.trim().isEmpty ? null : _review.text.trim(),
        includedUtilities: _utilities.toList(),
        reportedAt: DateTime.now(),
      );
      await HousingService.submit(report);
      if (!mounted) return;
      Navigator.pop(context); // 폼 닫기
      await widget.onSubmitted();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제보가 등록되었습니다. 감사합니다!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('제보 등록에 실패했습니다: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
            12,
            22,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    '원룸 이름·시세·후기 제보',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 이름 선택
                  DropdownButtonFormField<String>(
                    initialValue: _selectedOneRoomId,
                    decoration: const InputDecoration(
                      labelText: '원룸 이름 (알고 있다면)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('목록에 없음 / 모름'),
                      ),
                      ...kOneRoomNames.map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.name} (${r.zone.label})'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedOneRoomId = v),
                  ),
                  const SizedBox(height: 14),

                  // 방 구조
                  Text(
                    '방 구조',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: HousingRoomType.values.map((t) {
                      return ChoiceChip(
                        label: Text(
                          t.label,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: _roomType == t,
                        onSelected: (sel) =>
                            setState(() => _roomType = sel ? t : null),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // 보증금 / 월세
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _deposit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '보증금 (만원)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return '입력 필요';
                            if (int.tryParse(v.trim()) == null) return '숫자만';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _rent,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '월세 (만원)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return '입력 필요';
                            if (int.tryParse(v.trim()) == null) return '숫자만';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 관리비
                  TextFormField(
                    controller: _fee,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '관리비 (만원, 선택)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 외벽 현수막/관리인 임대 문의 번호
                  TextFormField(
                    controller: _contactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '외벽 임대 문의 번호 (선택)',
                      hintText: '예: 010-1234-5678 (건물 현수막 번호)',
                      helperText: '외벽에 붙은 현수막이나 출입문 문의 번호를 공유해주세요',
                      helperStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 관리비 포함 항목
                  Text(
                    '관리비 포함 항목 (선택)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kHousingUtilities.map((u) {
                      final selected = _utilities.contains(u);
                      return FilterChip(
                        label: Text(u, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _utilities.add(u);
                            } else {
                              _utilities.remove(u);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 👍 추천 장점 선택
                  Row(
                    children: [
                      const Text('👍 ', style: TextStyle(fontSize: 14)),
                      Text(
                        '이 방의 추천 장점 (선택)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kHousingPros.map((f) {
                      final selected = _features.contains(f);
                      return FilterChip(
                        label: Text(f, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                        checkmarkColor: const Color(0xFF10B981),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _features.add(f);
                            } else {
                              _features.remove(f);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // ⚠️ 솔직 주의점/단점 선택
                  Row(
                    children: [
                      const Text('⚠️ ', style: TextStyle(fontSize: 14)),
                      Text(
                        '솔직 주의점·아쉬운 점 (선택)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kHousingCons.map((d) {
                      final selected = _drawbacks.contains(d);
                      return FilterChip(
                        label: Text(d, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        selectedColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        checkmarkColor: const Color(0xFFEF4444),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _drawbacks.add(d);
                            } else {
                              _drawbacks.remove(d);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 거주 후기 / 팁
                  Text(
                    '거주 후기 / 팁 (선택)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _review,
                    maxLines: 2,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      hintText: '수압, 방음, 일조량, 집주인 등 살면서 느낀 점을 자유롭게 적어주세요',
                      hintStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // 제출 버튼
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              '제보하기',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
