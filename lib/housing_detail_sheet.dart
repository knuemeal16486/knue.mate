import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_auth_service.dart';
import 'building_data.dart' show BuildingData;
import 'campus_building_info.dart' show floorLabel;
import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_note_service.dart';
import 'housing_note_sheet.dart';
import 'housing_report_sheet.dart';
import 'housing_service.dart';
import 'housing_survey.dart';
import 'ui_utils.dart';

/// 자취방 건물 상세 바텀시트
class HousingDetailSheet extends StatefulWidget {
  final BaseBuilding building;
  final HousingSummary summary;
  final OneRoomName? known;
  final HousingBuildingOverride? edited;
  final bool isDark;
  final bool isFavorite;
  final bool isCompared;
  final Future<void> Function() onToggleFavorite;
  final Future<void> Function() onReported;
  final VoidCallback? onToggleCompare;
  final VoidCallback? onShowOnMap;
  final VoidCallback? onEditBuilding;

  /// 교내 건물이면 캠퍼스맵에 있던 건물 정보(설명·층별 호실).
  final BuildingData? campusInfo;

  const HousingDetailSheet({
    super.key,
    required this.building,
    required this.summary,
    required this.known,
    required this.edited,
    required this.isDark,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onReported,
    this.isCompared = false,
    this.onToggleCompare,
    this.onShowOnMap,
    this.onEditBuilding,
    this.campusInfo,
  });

  @override
  State<HousingDetailSheet> createState() => _HousingDetailSheetState();
}

class _HousingDetailSheetState extends State<HousingDetailSheet> {
  bool _already = false;
  late bool _fav;
  int _dormIndex = 0;
  HousingNoteData? _noteData;

  /// 원룸, 1.5룸, 2룸 중 단일 선택 (기본: 원룸)
  HousingRoomType _selectedRoomType = HousingRoomType.oneRoom;

  @override
  void initState() {
    super.initState();
    _fav = widget.isFavorite;

    // 만약 건물에 등록된 제보 방 구조가 있고 원룸이 없다면 해당 타입 우선 선택
    final reportedTypes = widget.summary.roomTypes;
    if (reportedTypes.isNotEmpty && !reportedTypes.contains(HousingRoomType.oneRoom)) {
      if (reportedTypes.contains(HousingRoomType.onePointFive)) {
        _selectedRoomType = HousingRoomType.onePointFive;
      } else if (reportedTypes.contains(HousingRoomType.twoRoom)) {
        _selectedRoomType = HousingRoomType.twoRoom;
      }
    }

    HousingService.hasReported(widget.building.id).then((v) {
      if (mounted) setState(() => _already = v);
    });
    _loadNote();
  }

  Future<void> _loadNote() async {
    final note = await HousingNoteService.loadNote(widget.building.id);
    if (mounted) setState(() => _noteData = note);
  }

  void _openInspectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HousingNoteSheet(
        buildingId: widget.building.id,
        buildingName: widget.known?.name ?? widget.building.officialName ?? '이름 미확인 건물',
        isDark: widget.isDark,
        onSaved: (note) {
          if (mounted) setState(() => _noteData = note);
        },
      ),
    );
  }

  void _share() {
    final b = widget.building;
    final s = widget.summary;
    final name = widget.known?.name ?? b.officialName ?? '한국교원대 인근 자취방';
    final addr = displayAddress(b, widget.edited);
    final pricing = s.getPricing(_selectedRoomType, zone: widget.known?.zone);

    final buffer = StringBuffer();
    buffer.writeln('[KNUE Mate 자취방 정보] $name');
    buffer.writeln('📍 위치: $addr');
    buffer.writeln('🏠 방 구조: ${_selectedRoomType.label}');
    if (pricing != null) {
      buffer.writeln('💰 시세: 보증금 ${pricing.deposit}만원 / 월세 ${pricing.monthlyRent}만원 (관리비 ${pricing.maintenanceFee}만원)');
    }
    if (s.topFeatures.isNotEmpty) {
      buffer.writeln('✨ 특징: ${s.topFeatures.join(', ')}');
    }
    if (s.recentReviews.isNotEmpty) {
      buffer.writeln('💬 학생 후기: "${s.recentReviews.first}"');
    }

    Share.share(buffer.toString());
  }

  /// 외벽 현수막/관리인/집주인 복수 연락처 (보통 최대 2개)
  List<String> get _effectivePhones {
    final overridePhones = widget.edited?.allLandlordPhones ?? [];
    final reportedPhones = widget.summary.publicContactPhones.isNotEmpty
        ? widget.summary.publicContactPhones
        : [if (widget.summary.publicContactPhone != null) widget.summary.publicContactPhone!];
    return parseContactPhones([...overridePhones, ...reportedPhones]);
  }

  Future<void> _callLandlord(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('통화 기능을 열 수 없습니다: $phone')),
        );
      }
    }
  }

  Future<void> _sendSms(String phone, String text) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('sms:$clean?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('문자 앱을 열 수 없어 문의 내용이 클립보드에 복사되었습니다.')),
        );
      }
    }
  }

  void _showSubmitPhoneDialog({String? initialPhone1, String? initialPhone2}) {
    final controller1 = TextEditingController(text: initialPhone1);
    final controller2 = TextEditingController(text: initialPhone2);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_call, size: 20, color: Color(0xFF007AFF)),
            SizedBox(width: 8),
            Text('외벽 임대 문의 번호 제보', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '건물 외벽 현수막이나 출입문에 적힌 문의 연락처를 입력해주세요.\n보통 집주인과 관리인(또는 사모님) 2개가 적혀 있습니다.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller1,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '연락처 1 (집주인/임대인)',
                hintText: '예: 010-1234-5678',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller2,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '연락처 2 (관리인/사모님 - 선택)',
                hintText: '예: 010-9876-5432 또는 유선전화',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final phone1 = controller1.text.trim();
              final phone2 = controller2.text.trim();
              if (phone1.isEmpty && phone2.isEmpty) return;
              Navigator.pop(ctx);
              final ok = await HousingService.submitContactPhone(
                buildingId: widget.building.id,
                phone: phone1.isNotEmpty ? phone1 : phone2,
                phone2: (phone1.isNotEmpty && phone2.isNotEmpty) ? phone2 : null,
                oneRoomId: widget.known?.id,
              );
              if (mounted) {
                if (ok) {
                  await widget.onReported();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('외벽 연락처가 제보되었습니다. 감사합니다!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('제보에 실패했습니다. 잠시 후 다시 시도해주세요.')),
                  );
                }
              }
            },
            child: const Text('제보하기'),
          ),
        ],
      ),
    );
  }

  void _showInquiryTemplateModal(String? phone, {String? roleTitle}) {
    final b = widget.building;
    final name = widget.known?.name ?? b.officialName ?? '한국교원대 인근 원룸';
    final addr = displayAddress(b, widget.edited);
    final roomName = _selectedRoomType.label;
    final pricing = widget.summary.getPricing(_selectedRoomType, zone: widget.known?.zone);

    final defaultText = '''안녕하세요, 교원대 학생입니다!
에브리타임/지도에서 [ $name ]($addr) 외벽 임대 현수막 보고 연락드립니다.

혹시 다가오는 학기에 입주 가능한 [$roomName] 공실이 있는지 여쭙고 싶습니다.
- 문의 구조: $roomName
${pricing != null ? '- 예상 시세 조건: 보증금 ${pricing.deposit}만원 / 월세 ${pricing.monthlyRent}만원 (관리비 ${pricing.maintenanceFee}만원)\n' : ''}- 희망 입주시기: 개강 전 (협의 가능)
- 기본 옵션 및 난방 방식(도시가스 등) 확인 요청

편하신 시간에 방을 한번 둘러볼 수 있을까요? 감사합니다!''';

    final textController = TextEditingController(text: defaultText);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.sms_outlined, color: Color(0xFF007AFF), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '집주인 직거래 문의 양식',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '교원대 원룸 직거래에 꼭 필요한 질문들을 정리한 템플릿입니다.\n자유롭게 수정한 뒤 복사하거나 문자로 바로 보내실 수 있습니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.white60 : Colors.black54,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: textController,
                maxLines: 8,
                style: const TextStyle(fontSize: 13, height: 1.4),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: textController.text));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('문의 내용이 클립보드에 복사되었습니다!')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('내용 복사'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (phone != null && phone.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendSms(phone, textController.text);
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('문자로 바로 보내기'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChecklistModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.78,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 8),
                Text(
                  '자취방 직거래 계약 7대 체크리스트',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '교원대 인근은 부동산 없이 집주인 직거래가 많아 계약 전 꼼꼼한 확인이 필수입니다.',
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: const [
                  _ChecklistTile(
                    step: '1',
                    title: '등기부등본 확인 (소유자 & 빚)',
                    desc: '인터넷등기소(700원)에서 건물 등기부등본을 떼어 계약 당사자와 실제 소유자(신분증)가 같은지 확인하고, 근저당(대출)이 건물 시세 대비 과다하지 않은지 점검하세요.',
                  ),
                  _ChecklistTile(
                    step: '2',
                    title: '난방 방식 & 겨울 난방비 팩트 체크',
                    desc: '도시가스인지 심야전기/LPG인지 반드시 확인하세요! 심야전기/LPG는 겨울 한 달 난방비만 15~30만원이 청구될 수 있으므로 전 세입자 겨울 고지서를 물어보는 것이 좋습니다.',
                  ),
                  _ChecklistTile(
                    step: '3',
                    title: '관리비 포함 항목 계약서 특약 명시',
                    desc: '수도세, 인터넷, 공용전기/청소비가 관리비에 포함인지 별도 고지인지 계약서에 명확히 적으세요. 말로만 들었다가 나중에 분쟁이 생길 수 있습니다.',
                  ),
                  _ChecklistTile(
                    step: '4',
                    title: '수압 & 온수 & 배수 동시 테스트',
                    desc: '방 구경 시 세면대, 싱크대, 샤워기 물을 동시에 틀고 양변기 물을 내려보세요. 수압 급감이나 온수 지연 여부를 바로 확인할 수 있습니다.',
                  ),
                  _ChecklistTile(
                    step: '5',
                    title: '방음 상태 & 창틀 외풍/곰팡이',
                    desc: '벽을 가볍게 두드려 석고보드 가벽인지 콘크리트인지 확인하고, 장롱 뒤나 창틀 실리콘에 결로 곰팡이 흔적이 없는지 살펴보세요.',
                  ),
                  _ChecklistTile(
                    step: '6',
                    title: '입주 첫날 기본 옵션 파손 사전 촬영',
                    desc: '에어컨, 냉장고, 도배, 장판의 기존 흠집과 작동 상태를 입주 첫날 사진/동영상으로 찍어 집주인에게 카톡이나 문자로 미리 보내두면 퇴실 시 원상복구 분쟁을 방지할 수 있습니다.',
                  ),
                  _ChecklistTile(
                    step: '7',
                    title: '확정일자 & 전입신고 필수',
                    desc: '소액 보증금이라도 안전하게 보호받으려면 계약서 작성 즉시 강내면 행정복지센터 방문 또는 정부24 온라인으로 전입신고 및 확정일자를 받으세요.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openForm() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HousingReportSheet(
        building: widget.building,
        isDark: widget.isDark,
        onSubmitted: () async {
          setState(() => _already = true);
          await widget.onReported();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final b = widget.building;
    final s = widget.summary;
    final known = widget.known;


    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.22,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: const [0.38, 0.88],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scrollController,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, b.isCampus ? 16 : 88),
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

                // 상단 헤더 (이름 + 즐겨찾기 + 공유 + 지도보기)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        known?.name ?? b.officialName ?? '이름 미확인 건물',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _fav ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54),
                        size: 22,
                      ),
                      tooltip: _fav ? '찜 취소' : '찜하기',
                      onPressed: () async {
                        setState(() => _fav = !_fav);
                        await widget.onToggleFavorite();
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.share_rounded,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      tooltip: '공유하기',
                      onPressed: _share,
                    ),
                    if (widget.onShowOnMap != null)
                      IconButton(
                        icon: const Icon(
                          Icons.map_rounded,
                          size: 20,
                          color: Color(0xFF007AFF),
                        ),
                        tooltip: '지도에서 위치 보기',
                        onPressed: widget.onShowOnMap,
                      ),
                    if (widget.onEditBuilding != null && AdminAuthService.isAdmin.value)
                      IconButton(
                        icon: const Icon(
                          Icons.edit_note_rounded,
                          size: 22,
                          color: Color(0xFF10B981),
                        ),
                        tooltip: '건물 정보/색상 편집 (개발자)',
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onEditBuilding!();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 2),

                // 주소 및 층수 정보
                Text(
                  [
                    displayAddress(b, widget.edited),
                    '지상 ${widget.edited?.floors ?? b.floors}층',
                    if (widget.edited?.unitCount != null)
                      '${widget.edited!.unitCount}세대',
                    if (known?.builtYear ?? builtYearByName(b.officialName) case final year?)
                      '$year년 준공',
                    if (known?.note != null) known!.note!,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),

                // 구역 딱지는 "캠퍼스 시설"만 — 원룸 구역 태그는 뺐다.
                if (known != null && b.isCampus) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: badgeZone(b, known).color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        known.zone.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: known.zone.color,
                        ),
                      ),
                    ],
                  ),
                ],

                // 정문·도서관·정류장까지 어림 거리는 뺐다(직선거리라 실제와 달랐다).
                // 도보권은 지도의 등시선 버튼으로 이 건물 기준으로 본다.
                if (!b.isCampus) ...[
                  const SizedBox(height: 12),

                  // 발품수첩 & 비교함 액션 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openInspectionSheet,
                          icon: const Icon(Icons.assignment_outlined, size: 15),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('발품 수첩', style: TextStyle(fontSize: 12)),
                              if (_noteData != null && _noteData!.checkedKeys.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_noteData!.checkedKeys.length}/7',
                                    style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (widget.onToggleCompare != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: widget.onToggleCompare,
                            icon: Icon(
                              widget.isCompared ? Icons.check_circle_outline_rounded : Icons.compare_arrows_rounded,
                              size: 15,
                            ),
                            label: Text(
                              widget.isCompared ? '비교함 담김 ✓' : '비교함 담기',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.isCompared ? const Color(0xFF10B981) : const Color(0xFF007AFF),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 외벽 임대 문의처 카드 (집주인 / 관리인 보통 2개 번호 지원)
                  _buildLandlordContactCard(isDark),

                  // 시세·조건 한 장: 방 구조별 시세, 관리비 포함 항목, 좋은 점·아쉬운 점.
                  // (예전엔 방 구조 선택기·구조별 시세·옵션 안내·관리비·장단점이
                  //  카드 다섯 장으로 흩어져 있었고, 옵션 안내는 모든 건물에 같은
                  //  평수·옵션을 지어 보여줬다.)
                  _buildConditionsCard(s, isDark),
                ],

                // 교내 건물: 캠퍼스맵에 있던 설명·층별 호실
                if (widget.campusInfo case final info?) _buildCampusInfoCard(info, isDark),

                // 상가 건물에 든 가게들
                if (widget.edited?.shops case final shops? when shops.isNotEmpty)
                  _buildShopsCard(shops, isDark),

                // 개발자가 직접 입력한 시세(최근 3건 + 전체보기)
                if (widget.edited?.prices case final prices? when prices.isNotEmpty)
                  _buildEnteredPricesCard(prices, isDark),

                const SizedBox(height: 6),

                // 포함 관리비 및 실거주 정보 블록
                if (!b.isCampus) ...[

                  // 기숙사 비교 카드
                  if (s.hasData && s.avgMonthlyTotal != null) ...[
                    const SizedBox(height: 12),
                    _buildDormComparisonCard(s, isDark),
                  ],

                  // 자취방 직거래 계약 7대 체크리스트 배너
                  _buildChecklistBanner(isDark),

                  // 최근 거주 후기
                  if (s.recentReviews.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '학생들의 생생 후기 (${s.recentReviews.length})',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...s.recentReviews.map(
                      (rev) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF242426) : const Color(0xFFF7F7F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💬 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                rev,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: Text(
                        _already
                            ? '다른 방 시세 알려주기'
                            : known == null
                            ? '이 건물 이름·시세 알려주기'
                            : '내가 아는 시세·후기 알려주기',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // 캠퍼스 건물 안내
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.school_rounded,
                          size: 20,
                          color: Color(0xFF3F51B5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '한국교원대학교 교육·행정 및 학생 편의 시설입니다.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
              // 하단 고정 전화/문자 퀵 액션 플로팅 바 (Glassmorphism Blur)
              if (!b.isCampus)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomQuickActionBar(isDark),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 하단 고정 전화/문자 퀵 액션 플로팅 바 (Glassmorphism Blur)
  Widget _infoCard({required bool isDark, required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
        ),
        child: child,
      );

  /// 학생 제보로 모은 이 집의 시세와 조건. 없는 건 지어내지 않고 비워 둔다.
  Widget _buildConditionsCard(HousingSummary s, bool isDark) {
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black54;
    // 방 구조별 시세(학생 제보). 개발자 확인 시세는 아래 따로 보여준다.
    final points = housingPricePoints(s, null);
    // 아파트 전세(시세 조사). 단지 어느 동을 눌러도 보인다.
    final edited = widget.edited;
    final jeonse = housingJeonseFor(
      (edited?.isNamed ?? false) ? edited!.name : (widget.known?.name ?? widget.building.officialName),
    );

    Widget chipRow(String title, List<String> items, Color color) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sub)),
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final x in items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(x, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                    ),
                ],
              ),
            ],
          ),
        );

    return _infoCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('시세·조건', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
              const SizedBox(width: 6),
              if (s.hasData)
                Text('${s.sourceLabel}${s.isThin ? ' · 참고용' : ''}', style: TextStyle(fontSize: 11.5, color: sub)),
              const Spacer(),
              TextButton(
                onPressed: _openForm,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('제보하기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (points.isEmpty && jeonse.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '아직 시세 제보가 없어요. 살고 있거나 계약해 봤다면 알려 주세요.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: sub),
              ),
            )
          else ...[
            if (points.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('방 구조별 평균 (만원)', style: TextStyle(fontSize: 11.5, color: sub)),
              ),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        p.roomType?.label ?? '구조 모름',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sub),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '보증금 ${p.deposit} · 월세 ${p.monthlyRent}'
                        '${p.maintenanceKnown ? ' · 관리비 ${p.monthlyTotal - p.monthlyRent}' : ''}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          fontFeatures: KnueTokens.tabularFigures,
                        ),
                      ),
                    ),
                    if (s.roomPricingMap[p.roomType]?.reportCount case final n?)
                      Text('$n건', style: TextStyle(fontSize: 11.5, color: sub)),
                  ],
                ),
              ),
          ],
          for (final j in jeonse)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('전세', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sub)),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: '보증금 ${j.deposit}',
                        children: [
                          if (j.note != null)
                            TextSpan(
                              text: '  ${j.note}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sub),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        fontFeatures: KnueTokens.tabularFigures,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (s.reports.length > 1) _buildAllReports(s, isDark),
          if (s.commonUtilities.isNotEmpty)
            chipRow('관리비에 포함', s.commonUtilities.toList(), isDark ? Colors.tealAccent : Colors.teal.shade700),
          if (s.topFeatures.isNotEmpty) chipRow('좋은 점', s.topFeatures, const Color(0xFF10B981)),
          if (s.topDrawbacks.isNotEmpty) chipRow('아쉬운 점', s.topDrawbacks, const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  /// 평균이 나온 제보 하나하나. 같은 건물도 방마다 값이 달라 겹치는 제보를
  /// 모두 남기므로, 어떤 값들의 평균인지 펼쳐 볼 수 있게 한다.
  Widget _buildAllReports(HousingSummary s, bool isDark) {
    final fg = isDark ? Colors.white70 : Colors.black87;
    final sub = isDark ? Colors.white38 : Colors.black45;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          '제보 전체 보기 (${s.reports.length}건)',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
        ),
        children: [
          for (final r in s.reports)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(r.roomType?.label ?? '구조 모름', style: TextStyle(fontSize: 12, color: sub)),
                  ),
                  Expanded(
                    child: Text(
                      '${r.deposit} / ${r.monthlyRent}'
                      '${r.maintenanceFee != null ? ' · 관리비 ${r.maintenanceFee}' : ''}',
                      style: TextStyle(fontSize: 12.5, color: fg, fontFeatures: KnueTokens.tabularFigures),
                    ),
                  ),
                  Text(
                    r.survey
                        ? '시세 조사'
                        : '${r.reportedAt.year}.${r.reportedAt.month.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 교내 건물 안내: 설명과 층별 호실(층을 누르면 펼친다).
  Widget _buildCampusInfoCard(BuildingData info, bool isDark) {
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;
    final floors = [for (final f in info.floors) if (f.rooms.isNotEmpty) f];
    return _infoCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_rounded, size: 18, color: Color(0xFF3F51B5)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '건물 안내',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
                ),
              ),
            ],
          ),
          if (info.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(info.description, style: TextStyle(fontSize: 13, height: 1.4, color: sub)),
          ],
          if (floors.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final f in floors)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  dense: true,
                  title: Text(
                    '${floorLabel(f.floor)} · ${f.rooms.length}곳',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in f.rooms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                              ),
                              child: Text(r, style: TextStyle(fontSize: 12, color: fg)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 상가 건물 안의 가게 목록.
  Widget _buildShopsCard(List<HousingShop> shops, bool isDark) {
    return _infoCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFFFF9800)),
              const SizedBox(width: 6),
              Text(
                '이 건물의 가게 ${shops.length}곳',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final shop in shops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      shop.name,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (shop.detail.isNotEmpty)
                    Text(shop.detail, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 개발자가 직접 입력한 시세. 최근 3건만 보이고, 더 있으면 [전체보기].
  Widget _buildEnteredPricesCard(List<HousingPriceEntry> prices, bool isDark) {
    final sorted = sortedPriceEntries(prices);
    const preview = 3;
    return _infoCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF03C75A)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '확인된 시세 ${sorted.length}건',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87),
                ),
              ),
              if (sorted.length > preview)
                TextButton(
                  onPressed: () => _showAllPrices(sorted, isDark),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('전체보기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (final p in sorted.take(preview)) _priceRow(p, isDark),
        ],
      ),
    );
  }

  Widget _priceRow(HousingPriceEntry p, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.priceText} 만원',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
                fontFeatures: KnueTokens.tabularFigures,
              ),
            ),
            if (p.detail.isNotEmpty)
              Text(p.detail, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
          ],
        ),
      );

  void _showAllPrices(List<HousingPriceEntry> sorted, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '확인된 시세 전체 (${sorted.length}건)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 8),
            for (final p in sorted) ...[
              _priceRow(p, isDark),
              Divider(height: 10, color: isDark ? Colors.white10 : Colors.black12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomQuickActionBar(bool isDark) {
    final phones = _effectivePhones;
    final primaryPhone = phones.isNotEmpty ? phones.first : null;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF161618).withValues(alpha: 0.86)
                : Colors.white.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: phones.isEmpty
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showSubmitPhoneDialog(),
                        icon: const Icon(Icons.add_call, size: 16),
                        label: const Text('외벽 임대 연락처 제보하기'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    // 전화 걸기 버튼 (복수 번호 시 모달 선택)
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (phones.length == 1) {
                            _callLandlord(primaryPhone!);
                          } else {
                            _showCallSelectModal(phones);
                          }
                        },
                        icon: const Icon(Icons.phone_in_talk_rounded, size: 16, color: Color(0xFF10B981)),
                        label: Text(
                          phones.length > 1 ? '전화 (2개)' : '집주인 전화',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: const Color(0xFF10B981).withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 문자 문의하기 버튼 (자동 템플릿 연동)
                    Expanded(
                      flex: 1,
                      child: FilledButton.icon(
                        onPressed: () {
                          _showInquiryTemplateModal(primaryPhone, roleTitle: '집주인');
                        },
                        icon: const Icon(Icons.sms_outlined, size: 16),
                        label: const Text(
                          '직거래 문자',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showCallSelectModal(List<String> phones) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '통화할 연락처 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...phones.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              final role = idx == 0 ? '집주인 (임대인)' : '관리인 (사모님)';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                  child: const Icon(Icons.phone_rounded, color: Color(0xFF10B981), size: 18),
                ),
                title: Text('$role · $p', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('터치 시 바로 통화 앱으로 연결됩니다', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _callLandlord(p);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  bool _compareIncludeMeals = false;

  Widget _buildDormComparisonCard(HousingSummary s, bool isDark) {
    final dorm = kDormCosts[_dormIndex];
    final monthly = s.avgMonthlyTotal ?? s.avgRent;
    if (monthly == null) return const SizedBox.shrink();

    final roomCost = _compareIncludeMeals ? (monthly + dorm.monthlyMeal) : monthly;
    final dormCost = _compareIncludeMeals ? dorm.monthlyWithMeals : dorm.monthlyHousing;
    final diff = roomCost - dormCost;
    final maxCost = (roomCost > dormCost ? roomCost : dormCost).toDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF5F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment_rounded, size: 16),
              const SizedBox(width: 6),
              Text(
                "기숙사 비용과 비교",
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              // 주거비만 / 식비포함 토글
              GestureDetector(
                onTap: () => setState(() => _compareIncludeMeals = !_compareIncludeMeals),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _compareIncludeMeals ? '식비 포함' : '주거비만',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 기숙사 선택 칩
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(kDormCosts.length, (idx) {
                final d = kDormCosts[idx];
                final isSel = idx == _dormIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(d.name, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      if (val) setState(() => _dormIndex = idx);
                    },
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          // 시각적 비교 바 1: 이 원룸
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  '이 원룸',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxCost > 0 ? (roomCost / (maxCost * 1.15)) : 0,
                    minHeight: 10,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: Text(
                  '월 $roomCost만',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // 시각적 비교 바 2: 기숙사
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  dorm.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxCost > 0 ? (dormCost / (maxCost * 1.15)) : 0,
                    minHeight: 10,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      diff <= 0 ? Colors.grey : const Color(0xFFFF9500),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: Text(
                  '월 $dormCost만',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 인사이트 뱃지
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (diff <= 0
                      ? (isDark ? Colors.greenAccent : Colors.green)
                      : (isDark ? Colors.orangeAccent : Colors.orange))
                  .withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  diff <= 0 ? Icons.savings_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: diff <= 0
                      ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                      : (isDark ? Colors.orangeAccent : Colors.deepOrange),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    diff <= 0
                        ? "이 원룸이 ${dorm.name}보다 월 ${-diff}만원 (한 학기 약 ${-diff * 6}만원) 절약돼요!"
                        : "${dorm.name}보다 월 $diff만원 차이예요. (통금·룸메이트 없는 1인 공간)",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: diff <= 0
                          ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                          : (isDark ? Colors.orangeAccent : Colors.deepOrange),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandlordContactCard(bool isDark) {
    final phones = _effectivePhones;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF007AFF), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '임대 문의 연락처',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            phones.isNotEmpty ? '${phones.length}개 번호 제공' : '외벽 번호 제보',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      phones.isNotEmpty
                          ? '외벽 현수막/관리인 직거래 문의 번호입니다.'
                          : '외벽 현수막이나 출입문에 적힌 문의 번호를 등록해주세요.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showSubmitPhoneDialog(
                  initialPhone1: phones.isNotEmpty ? phones[0] : null,
                  initialPhone2: phones.length > 1 ? phones[1] : null,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    phones.isNotEmpty ? '수정/제보' : '번호 등록',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (phones.isNotEmpty) ...[
            // 최대 2개의 번호 (집주인 및 관리인/비상 연락처)
            ...List.generate(phones.length, (idx) {
              final phone = phones[idx];
              final roleTitle = idx == 0 ? '집주인 (임대인)' : '관리인 / 비상 연락처';
              final roleIcon = idx == 0 ? Icons.person_rounded : Icons.support_agent_rounded;

              return Container(
                margin: EdgeInsets.only(bottom: idx < phones.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252C35) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(roleIcon, size: 15, color: const Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roleTitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.lightBlueAccent : const Color(0xFF0056B3),
                              letterSpacing: 0.3,
                              fontFeatures: KnueTokens.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 복사 버튼
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      tooltip: '번호 복사',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(5),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: phone));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$roleTitle 번호가 복사되었습니다: $phone')),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 2),
                    // 문자 버튼
                    IconButton(
                      icon: const Icon(Icons.sms_outlined, size: 16, color: Color(0xFF007AFF)),
                      tooltip: '직거래 문의 문자',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(5),
                      onPressed: () => _showInquiryTemplateModal(phone, roleTitle: roleTitle),
                    ),
                    const SizedBox(width: 4),
                    // 전화 걸기 버튼
                    FilledButton.icon(
                      onPressed: () => _callLandlord(phone),
                      icon: const Icon(Icons.phone_rounded, size: 12),
                      label: const Text('통화', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // 번호가 1개만 있을 때 관리인/사모님 2번째 연락처 추가 권장
            if (phones.length == 1) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _showSubmitPhoneDialog(initialPhone1: phones[0]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '관리인/사모님 2번째 연락처 추가 제보하기 +',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showSubmitPhoneDialog(),
                icon: const Icon(Icons.add_call, size: 15),
                label: const Text('외벽 임대 문의 번호 제보하기 (보통 2개)', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChecklistBanner(bool isDark) {
    return InkWell(
      onTap: _showChecklistModal,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: (isDark ? Colors.amberAccent : Colors.amber).withValues(alpha: isDark ? 0.12 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.checklist_rounded, color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '자취방 직거래 계약 7대 체크리스트',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                  ),
                  Text(
                    '등기부등본, 난방비 폭탄 방지, 수압 등 계약 전 필수 점검',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white38 : Colors.black38,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  final String step;
  final String title;
  final String desc;

  const _ChecklistTile({
    required this.step,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF28282B) : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: const Color(0xFF007AFF),
            child: Text(
              step,
              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
