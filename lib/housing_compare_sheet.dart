import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_service.dart';

/// 자취방 1:1 후보 비교 바텀시트
class HousingCompareSheet extends StatelessWidget {
  final List<BaseBuilding> buildings;
  final Map<String, HousingSummary> summaries;
  final Map<String, OneRoomName?> knowns;
  final Map<String, HousingBuildingOverride?> overrides;
  final bool isDark;
  final void Function(String buildingId) onRemove;
  final VoidCallback onClearAll;
  final void Function(BaseBuilding b)? onShowOnMap;

  const HousingCompareSheet({
    super.key,
    required this.buildings,
    required this.summaries,
    required this.knowns,
    required this.overrides,
    required this.isDark,
    required this.onRemove,
    required this.onClearAll,
    this.onShowOnMap,
  });

  Future<void> _callPhone(BuildContext context, String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전화 앱을 열 수 없습니다: $phone')),
      );
    }
  }

  void _copySmsTemplate(BuildContext context, String name, String addr) {
    final template = '''안녕하세요, 교원대 학생입니다!
에브리타임/지도에서 [ $name ]($addr) 외벽 임대 현수막 보고 연락드립니다.
혹시 다가오는 학기에 입주 가능한 공실이 있는지 여쭙고 싶습니다.
편하신 시간에 방을 한번 둘러볼 수 있을까요? 감사합니다!''';
    Clipboard.setData(ClipboardData(text: template));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('직거래 문의 문자 양식이 복사되었습니다!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (buildings.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1E22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.compare_arrows_rounded, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text(
                '비교함이 비어 있습니다.',
                style: TextStyle(fontSize: 15, color: isDark ? Colors.white70 : Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1E22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                  color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.compare_arrows_rounded, size: 20, color: Color(0xFF007AFF)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '후보 자취방 1:1 비교함 (${buildings.length}/3)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '선택한 자취방의 시세, 거리, 난방/옵션, 후기를 한눈에 비교합니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onClearAll,
                child: const Text('전체 비우기', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 비교 테이블
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 고정 항목 라벨 열
                    _buildLabelColumn(isDark),
                    const SizedBox(width: 8),
                    // 각 건물별 데이터 열
                    for (final b in buildings) ...[
                      _buildBuildingCard(context, b, isDark),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelColumn(bool isDark) {
    const labels = [
      '원룸 기본 정보',
      '월세 / 보증금',
      '포함 관리비',
      '정문 도보 시간',
      '도서관 도보 시간',
      '탑연삼거리 정류장',
      '난방 및 장점 TOP',
      '주의 단점 TOP',
      '학우 최근 후기',
      '외벽 임대 연락처',
    ];

    return Container(
      width: 105,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 70), // 건물 헤더 높이만큼 띄움
          for (final l in labels) ...[
            Container(
              height: l == '원룸 기본 정보' || l == '난방 및 장점 TOP' || l == '주의 단점 TOP' || l == '학우 최근 후기'
                  ? 68
                  : 44,
              alignment: Alignment.centerLeft,
              child: Text(
                l,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildBuildingCard(BuildContext context, BaseBuilding b, bool isDark) {
    final known = knowns[b.id];
    final override = overrides[b.id];
    final s = summaries[b.id] ?? HousingSummary.empty;
    final name = override?.name ?? known?.name ?? b.officialName ?? '이름 미확인';
    final addr = displayAddress(b, override);
    // 구역 표시는 "캠퍼스 시설"만 — 원룸 구역 태그는 뺐다.
    final zone = b.isCampus ? HousingZone.campus : null;
    final phone = override?.landlordPhone ?? s.publicContactPhone;

    final distGate = walkingDistanceMeters(b.center, CampusLandmark.mainGate);
    final distLib = walkingDistanceMeters(b.center, CampusLandmark.library);
    final distTopyeon = walkingDistanceMeters(b.center, CampusLandmark.topyeonStop);

    final monthly = s.avgMonthlyTotal ?? s.avgRent ?? 0;
    final deposit = s.avgDeposit ?? 0;

    return Container(
      width: 175,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 이름 + 삭제 + 지도보기
          Row(
            children: [
              if (zone != null)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(color: zone.color, shape: BoxShape.circle),
                ),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => onRemove(b.id),
                child: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            addr,
            style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.black45),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (onShowOnMap != null)
            InkWell(
              onTap: () {
                Navigator.pop(context);
                onShowOnMap!(b);
              },
              child: const Text('📍 지도 보기', style: TextStyle(fontSize: 10.5, color: Color(0xFF007AFF), fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // 1. 기본 정보 (층수 / 준공연도)
          Container(
            height: 68,
            alignment: Alignment.centerLeft,
            child: Text(
              '지상 ${override?.floors ?? b.floors}층\n${(known?.builtYear ?? builtYearByName(b.officialName)) != null ? "${known?.builtYear ?? builtYearByName(b.officialName)}년 준공" : "준공연도 미상"}${zone != null ? "\n${zone.label}" : ""}',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
          const Divider(height: 1),

          // 2. 월세 / 보증금
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: s.hasData
                ? Text(
                    '월 $monthly만 / 보 $deposit만',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF03C75A)),
                  )
                : Text('시세 제보 없음', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white38 : Colors.black38)),
          ),
          const Divider(height: 1),

          // 3. 포함 관리비
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: s.commonUtilities.isNotEmpty
                ? Text(
                    s.commonUtilities.join(', '),
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('제보 없음', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ),
          const Divider(height: 1),

          // 4. 정문 도보 시간
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: Text(
              '도보 ${walkingMinutes(distGate)}분 (${distGate}m)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: walkingMinutes(distGate) <= 4 ? const Color(0xFF03C75A) : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
          const Divider(height: 1),

          // 5. 도서관 도보 시간
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: Text(
              '도보 ${walkingMinutes(distLib)}분 (${distLib}m)',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
          const Divider(height: 1),

          // 6. 탑연삼거리 정류장 도보 시간
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: Text(
              '도보 ${walkingMinutes(distTopyeon)}분 (${distTopyeon}m)',
              style: TextStyle(
                fontSize: 11.5,
                color: walkingMinutes(distTopyeon) <= 6 ? const Color(0xFF007AFF) : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
          const Divider(height: 1),

          // 7. 난방 및 장점 TOP
          Container(
            height: 68,
            alignment: Alignment.centerLeft,
            child: s.topFeatures.isNotEmpty
                ? Text(
                    s.topFeatures.take(2).join('\n'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF03C75A), height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('장점 제보 없음', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ),
          const Divider(height: 1),

          // 8. 주의 단점 TOP
          Container(
            height: 68,
            alignment: Alignment.centerLeft,
            child: s.topDrawbacks.isNotEmpty
                ? Text(
                    s.topDrawbacks.take(2).join('\n'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('단점 제보 없음', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ),
          const Divider(height: 1),

          // 9. 학우 최근 후기
          Container(
            height: 68,
            alignment: Alignment.centerLeft,
            child: s.recentReviews.isNotEmpty
                ? Text(
                    '"${s.recentReviews.first}"',
                    style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: isDark ? Colors.white70 : Colors.black87, height: 1.25),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('후기 없음', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ),
          const Divider(height: 1),

          // 10. 임대 연락처 (전화 및 문자)
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            child: phone != null && phone.isNotEmpty
                ? Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.phone_in_talk, size: 18, color: Color(0xFF007AFF)),
                        tooltip: '전화 걸기',
                        onPressed: () => _callPhone(context, phone),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.sms_outlined, size: 18, color: Color(0xFF10B981)),
                        tooltip: '문의 문자 양식 복사',
                        onPressed: () => _copySmsTemplate(context, name, addr),
                      ),
                    ],
                  )
                : Text('연락처 미등록', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ),
        ],
      ),
    );
  }
}
