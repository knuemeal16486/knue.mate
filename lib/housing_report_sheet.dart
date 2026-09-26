import 'package:flutter/material.dart';

import 'housing_iso.dart';
import 'housing_service.dart';

/// 자취방 시세 제보 바텀시트.
///
/// 한 화면에 이름·구조·금액·연락처·관리비 항목·장점 11개·단점 10개·후기가
/// 줄줄이 있어 난잡했다. 꼭 필요한 **방 구조·보증금·월세(·관리비)**만 앞에 두고
/// 나머지는 [더 알려주기]에 접어 둔다. 원룸 이름 고르기는 뺐다 — 83개 중에서
/// 고르다 보니 같은 건물에 다른 이름이 달렸고(바우하우스 A·B동), 이름은 이제
/// 개발자가 지도에서 붙인다.
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
    final phone = _contactPhone.text.trim();
    final report = HousingReport(
      buildingId: widget.building.id,
      deposit: int.parse(_deposit.text.trim()),
      monthlyRent: int.parse(_rent.text.trim()),
      maintenanceFee: _fee.text.trim().isEmpty ? null : int.tryParse(_fee.text.trim()),
      features: _features.toList(),
      drawbacks: _drawbacks.toList(),
      contactPhone: phone.isEmpty ? null : phone,
      roomType: _roomType,
      review: _review.text.trim().isEmpty ? null : _review.text.trim(),
      includedUtilities: _utilities.toList(),
      reportedAt: DateTime.now(),
    );
    // 결과를 보고 알린다. 예전엔 이미 제보했거나 저장에 실패해도
    // 무조건 "등록되었습니다"를 띄웠다.
    final result = await HousingService.submit(report);
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case HousingSubmitResult.ok:
        Navigator.pop(context);
        await widget.onSubmitted();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제보가 등록되었어요. 고마워요!')),
        );
      case HousingSubmitResult.alreadyReported:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('같은 내용을 이미 보냈어요. 다른 방이면 금액이나 구조를 바꿔 보내 주세요.')),
        );
      case HousingSubmitResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장하지 못했어요. 네트워크를 확인하고 다시 눌러 주세요.')),
        );
    }
  }

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _chips(Iterable<String> items, Set<String> selected, {Color? color}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final x in items)
            FilterChip(
              label: Text(x, style: const TextStyle(fontSize: 11.5)),
              selected: selected.contains(x),
              selectedColor: color?.withValues(alpha: 0.2),
              checkmarkColor: color,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() => v ? selected.add(x) : selected.remove(x)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black54;
    Text label(String t) => Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 12, 22, MediaQuery.of(context).viewInsets.bottom + 16),
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
                  Text('시세 제보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
                  const SizedBox(height: 2),
                  Text('보증금·월세만 적어도 돼요.', style: TextStyle(fontSize: 12, color: sub)),
                  const SizedBox(height: 16),

                  label('방 구조'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in HousingRoomType.values)
                        ChoiceChip(
                          label: Text(t.label, style: const TextStyle(fontSize: 12)),
                          selected: _roomType == t,
                          visualDensity: VisualDensity.compact,
                          onSelected: (sel) => setState(() => _roomType = sel ? t : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  label('금액 (만원)'),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _deposit,
                          keyboardType: TextInputType.number,
                          decoration: _deco('보증금'),
                          validator: (v) => housingAmountError(v, max: kMaxReportDeposit),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _rent,
                          keyboardType: TextInputType.number,
                          decoration: _deco('월세'),
                          validator: (v) => housingAmountError(v, max: kMaxReportRent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _fee,
                          keyboardType: TextInputType.number,
                          decoration: _deco('관리비', hint: '선택'),
                          validator: (v) => housingAmountError(v, max: kMaxReportFee, required: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // 나머지는 선택 — 접어 둔다.
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text('더 알려주기 (선택)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
                      subtitle: Text('좋은 점·아쉬운 점·관리비 포함 항목·문의 번호·한 줄 후기',
                          style: TextStyle(fontSize: 11, color: sub)),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label('좋은 점'),
                        const SizedBox(height: 6),
                        // "내 조건 찾기"와 같은 목록이어야 조건에 걸린다.
                        _chips(kHousingFeatures, _features, color: const Color(0xFF10B981)),
                        const SizedBox(height: 12),
                        label('아쉬운 점'),
                        const SizedBox(height: 6),
                        _chips(kHousingCons, _drawbacks, color: const Color(0xFFEF4444)),
                        const SizedBox(height: 12),
                        label('관리비에 포함'),
                        const SizedBox(height: 6),
                        _chips(kHousingUtilities, _utilities),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _contactPhone,
                          keyboardType: TextInputType.phone,
                          decoration: _deco('외벽 임대 문의 번호', hint: '010-1234-5678'),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _review,
                          maxLength: 100,
                          decoration: _deco('한 줄 후기', hint: '수압·방음·채광·집주인 등'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('제보하기', style: TextStyle(fontWeight: FontWeight.w700)),
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
