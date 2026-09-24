import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_auth_service.dart';
import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_report_sheet.dart';
import 'housing_service.dart';
import 'ui_utils.dart';

/// 자취방 건물 상세 바텀시트
class HousingDetailSheet extends StatefulWidget {
  final BaseBuilding building;
  final HousingSummary summary;
  final OneRoomName? known;
  final HousingBuildingOverride? edited;
  final bool isDark;
  final bool isFavorite;
  final Future<void> Function() onToggleFavorite;
  final Future<void> Function() onReported;
  final VoidCallback? onShowOnMap;
  final VoidCallback? onEditBuilding;

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
    this.onShowOnMap,
    this.onEditBuilding,
  });

  @override
  State<HousingDetailSheet> createState() => _HousingDetailSheetState();
}

class _HousingDetailSheetState extends State<HousingDetailSheet> {
  bool _already = false;
  late bool _fav;
  int _dormIndex = 0;

  @override
  void initState() {
    super.initState();
    _fav = widget.isFavorite;
    HousingService.hasReported(widget.building.id).then((v) {
      if (mounted) setState(() => _already = v);
    });
  }

  void _share() {
    final b = widget.building;
    final s = widget.summary;
    final name = widget.known?.name ?? b.officialName ?? '한국교원대 인근 자취방';
    final addr = widget.edited?.address ?? b.addressLabel;
    final distGate = walkingDistanceMeters(b.center, CampusLandmark.mainGate);

    final buffer = StringBuffer();
    buffer.writeln('[KNUE Mate 자취방 정보] $name');
    buffer.writeln('📍 위치: $addr');
    buffer.writeln('🚶 정문 거리: 도보 약 ${walkingMinutes(distGate)}분 (${distGate}m)');
    if (s.hasData) {
      final monthly = s.medianMonthlyTotal ?? s.medianRent ?? 0;
      buffer.writeln('💰 시세(중앙값): 월 $monthly만원 / 보증금 ${s.medianDeposit ?? 0}만원');
      if (s.topFeatures.isNotEmpty) {
        buffer.writeln('✨ 특징: ${s.topFeatures.join(', ')}');
      }
      if (s.recentReviews.isNotEmpty) {
        buffer.writeln('💬 학생 후기: "${s.recentReviews.first}"');
      }
    } else {
      buffer.writeln('💰 시세: 아직 등록된 제보가 없습니다.');
    }

    Share.share(buffer.toString());
  }

  String? get _effectivePhone {
    final overridePhone = widget.edited?.landlordPhone?.trim();
    if (overridePhone != null && overridePhone.isNotEmpty) return overridePhone;
    final reportedPhone = widget.summary.publicContactPhone?.trim();
    if (reportedPhone != null && reportedPhone.isNotEmpty) return reportedPhone;
    return null;
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

  void _showSubmitPhoneDialog() {
    final controller = TextEditingController();
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
              '건물 외벽 현수막이나 출입문에 적힌 공실/임대 문의 연락처를 입력해주세요.\n방을 찾는 다른 학우들에게 큰 도움이 됩니다!',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '연락처',
                hintText: '예: 010-1234-5678',
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
              final phone = controller.text.trim();
              if (phone.isEmpty) return;
              Navigator.pop(ctx);
              final ok = await HousingService.submitContactPhone(
                buildingId: widget.building.id,
                phone: phone,
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

  void _showInquiryTemplateModal(String? phone) {
    final b = widget.building;
    final name = widget.known?.name ?? b.officialName ?? '한국교원대 인근 원룸';
    final addr = widget.edited?.address ?? b.addressLabel;

    final defaultText = '''안녕하세요, 교원대 학생입니다!
에브리타임/지도에서 [ $name ]($addr) 외벽 임대 현수막 보고 연락드립니다.

혹시 다가오는 학기에 입주 가능한 공실이 있는지 여쭙고 싶습니다.
- 희망 입주시기: 개강 전 (협의 가능)
- 보증금 및 월세, 관리비(포함 항목) 조건
- 방 옵션 및 난방 방식(도시가스 등)

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

    final distGate = walkingDistanceMeters(b.center, CampusLandmark.mainGate);
    final distLib = walkingDistanceMeters(b.center, CampusLandmark.library);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: SingleChildScrollView(
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
                    widget.edited?.address ?? b.addressLabel,
                    '지상 ${widget.edited?.floors ?? b.floors}층',
                    if (widget.edited?.unitCount != null)
                      '${widget.edited!.unitCount}세대',
                    if (known?.builtYear != null) '${known!.builtYear}년 준공',
                    if (known?.note != null) known!.note!,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),

                if (known != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: known.zone.color,
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

                // 거리 뱃지 정보
                if (!b.isCampus) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _distBadge(
                        Icons.directions_walk_rounded,
                        '정문 도보 ${walkingMinutes(distGate)}분 (${distGate}m)',
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _distBadge(
                        Icons.menu_book_rounded,
                        '도서관 도보 ${walkingMinutes(distLib)}분 (${distLib}m)',
                        isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 외벽 임대 문의처 카드 (전화 / 직거래 문자 양식 / 번호 제보)
                  _buildLandlordContactCard(isDark),
                ],

                const SizedBox(height: 8),

                // 시세 블록
                if (!b.isCampus) ...[
                  _priceBlock(s, isDark),

                  // 포함 관리비 뱃지
                  if (s.commonUtilities.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '포함 관리비: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            children: s.commonUtilities.map((u) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.tealAccent : Colors.teal)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '✓ $u',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.tealAccent : Colors.teal.shade800,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 학우들이 꼽은 솔직 장단점 요약 (Pros vs Cons)
                  _buildProsAndConsCard(s, isDark),

                  // 기숙사 비교 카드
                  if (s.hasData && s.medianMonthlyTotal != null) ...[
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
                      onPressed: _already ? null : _openForm,
                      icon: Icon(
                        _already
                            ? Icons.check_rounded
                            : Icons.add_comment_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _already
                            ? '이미 제보함'
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
    );
  }

  Widget _distBadge(IconData icon, String text, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252528) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontFeatures: KnueTokens.tabularFigures,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceBlock(HousingSummary s, bool isDark) {
    if (!s.hasData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 26,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 8),
            Text(
              '아직 제보가 없어요',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '살아봤다면 아래에서 알려주세요',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    final d = s.medianDeposit;
    final m = s.medianMonthlyTotal ?? s.medianRent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _priceItem('보증금', d == null ? '-' : '$d만원', isDark),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          _priceItem('월 부담', m == null ? '-' : '$m만원', isDark),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          _priceItem('제보', '${s.reportCount}건', isDark),
        ],
      ),
    );
  }

  Widget _priceItem(String label, String value, bool isDark) => Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
          fontFeatures: KnueTokens.tabularFigures,
        ),
      ),
    ],
  );

  bool _compareIncludeMeals = false;

  Widget _buildDormComparisonCard(HousingSummary s, bool isDark) {
    final dorm = kDormCosts[_dormIndex];
    final monthly = s.medianMonthlyTotal ?? s.medianRent;
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
    final phone = _effectivePhone;
    final hasPhone = phone != null && phone.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
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
                child: const Icon(Icons.apartment_rounded, color: Color(0xFF007AFF), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPhone ? '임대 문의처 (외벽 현수막/관리인)' : '임대 문의처 번호 없음',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      hasPhone ? phone : '건물 외벽 현수막 번호를 제보해주세요',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasPhone
                            ? (isDark ? Colors.lightBlueAccent : const Color(0xFF0056B3))
                            : (isDark ? Colors.white54 : Colors.black45),
                        fontWeight: hasPhone ? FontWeight.w800 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasPhone) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _callLandlord(phone),
                    icon: const Icon(Icons.phone_rounded, size: 15),
                    label: const Text('전화 걸기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showInquiryTemplateModal(phone),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('직거래 문자', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showSubmitPhoneDialog,
                icon: const Icon(Icons.add_call, size: 15),
                label: const Text('외벽 임대 문의 번호 제보하기', style: TextStyle(fontSize: 12)),
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

  Widget _buildProsAndConsCard(HousingSummary s, bool isDark) {
    final hasPros = s.topFeatures.isNotEmpty;
    final hasCons = s.topDrawbacks.isNotEmpty;

    if (!hasPros && !hasCons) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202024) : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚖️ ', style: TextStyle(fontSize: 14)),
              Text(
                '학우들이 꼽은 솔직 장단점 요약',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          if (hasPros) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.thumb_up_alt_rounded, size: 13, color: Color(0xFF10B981)),
                const SizedBox(width: 5),
                Text(
                  '장점 & 매력 포인트',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: s.topFeatures.map((f) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    '✓ $f',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (hasCons) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 5),
                Text(
                  '주의점 & 아쉬운 점 (계약 전 꼭 확인!)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: s.topDrawbacks.map((d) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    '⚠️ $d',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                    ),
                  ),
                );
              }).toList(),
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
