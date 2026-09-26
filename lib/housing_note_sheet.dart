import 'package:flutter/material.dart';
import 'housing_note_service.dart';

/// 나만의 원룸 발품 점검표 바텀시트
class HousingNoteSheet extends StatefulWidget {
  final String buildingId;
  final String buildingName;
  final bool isDark;
  final void Function(HousingNoteData note)? onSaved;

  const HousingNoteSheet({
    super.key,
    required this.buildingId,
    required this.buildingName,
    required this.isDark,
    this.onSaved,
  });

  @override
  State<HousingNoteSheet> createState() => _HousingNoteSheetState();
}

class _HousingNoteSheetState extends State<HousingNoteSheet> {
  final Set<String> _checked = {};
  final TextEditingController _memoController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final note = await HousingNoteService.loadNote(widget.buildingId);
    if (!mounted) return;
    if (note != null) {
      _checked.addAll(note.checkedKeys);
      _memoController.text = note.memo;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final note = HousingNoteData(
      buildingId: widget.buildingId,
      checkedKeys: _checked,
      memo: _memoController.text.trim(),
      updatedAt: DateTime.now(),
    );
    final ok = await HousingNoteService.saveNote(note);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      widget.onSaved?.call(note);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('발품 메모가 내 폰에 저장되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final total = kInspectionItems.length;
    final checkedCount = _checked.length;
    final progress = total > 0 ? checkedCount / total : 0.0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1E22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF03C75A).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_document, size: 20, color: Color(0xFF03C75A)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '나만의 원룸 발품 수첩',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      widget.buildingName,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 진척도 바
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F7F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE2EBE5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '현장 점검 완료도',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Text(
                      '$checkedCount / $total 항목 확인',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF03C75A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF03C75A)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 체크리스트 & 메모 스크롤 영역
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      Text(
                        '방 보러 갔을 때 꼭 확인할 7가지',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in kInspectionItems) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              if (_checked.contains(item.key)) {
                                _checked.remove(item.key);
                              } else {
                                _checked.add(item.key);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: _checked.contains(item.key),
                                  activeColor: const Color(0xFF03C75A),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _checked.add(item.key);
                                      } else {
                                        _checked.remove(item.key);
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.description,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white54 : Colors.black54,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '현장 메모 & 특이사항',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _memoController,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '예: 302호 방 빠짐, 2월 24일 입주 협의 가능, 보증금 100 조율 여지 있음.',
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.black38),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '💡 이 메모는 학생 본인의 스마트폰에만 안전하게 저장됩니다.',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),

          // 저장 버튼
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF03C75A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      '내 발품 수첩 저장하기',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
