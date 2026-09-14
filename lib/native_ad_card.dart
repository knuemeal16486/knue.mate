import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'ui_utils.dart';

/// 앱 디자인(Apple Inset Grouped & Squircle)에 완벽하게 일치하는
/// 원격 실시간 제휴 / 네이티브 인라인 광고 컴포넌트
///
/// Firebase Firestore 'sponsors' 컬렉션과 실시간 동기화되며,
/// 활성화된 제휴 광고가 없을 시 자동으로 기본 캠퍼스 제휴/안내 카드로 롤백됩니다.
class KnueNativeAdCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final String? callToAction;
  final IconData? icon;
  final String? imageUrl;
  final String? targetUrl;
  final bool isCompact;
  final String placement; // 'all', 'home', 'meal', 'bus', 'settings'
  final VoidCallback? onTap;

  const KnueNativeAdCard({
    super.key,
    this.title,
    this.subtitle,
    this.callToAction,
    this.icon,
    this.imageUrl,
    this.targetUrl,
    this.isCompact = false,
    this.placement = 'all',
    this.onTap,
  });

  Future<void> _handleTap(BuildContext context, String? url) async {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      _showAdInfoDialog(context);
    }
  }

  void _showAdInfoDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "AD",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text("청람 제휴 & 스폰서", style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          "KNUE MATE는 한국교원대학교 학생들을 위한 비영리 올인원 서비스입니다.\n\n"
          "쾌적한 서버 운영 및 서비스 유지를 위한 제휴/광고 영역입니다.\n"
          "제휴 및 광고 문의: 교원대 KNUE MATE 운영팀",
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  IconData _parseIcon(dynamic iconVal) {
    if (iconVal is! String) return Icons.campaign_rounded;
    switch (iconVal.toLowerCase().trim()) {
      case 'restaurant':
      case 'food':
      case 'meal':
      case 'dining':
        return Icons.restaurant_rounded;
      case 'cafe':
      case 'coffee':
        return Icons.local_cafe_rounded;
      case 'store':
      case 'shop':
      case 'mart':
        return Icons.storefront_rounded;
      case 'school':
      case 'study':
      case 'book':
        return Icons.school_rounded;
      case 'bus':
      case 'transport':
        return Icons.directions_bus_rounded;
      case 'event':
      case 'party':
      case 'festival':
        return Icons.celebration_rounded;
      case 'game':
      case 'esports':
        return Icons.sports_esports_rounded;
      case 'discount':
      case 'coupon':
        return Icons.local_offer_rounded;
      case 'housing':
      case 'room':
      case 'home':
        return Icons.home_rounded;
      case 'fitness':
      case 'gym':
      case 'sport':
        return Icons.fitness_center_rounded;
      case 'beer':
      case 'pub':
        return Icons.sports_bar_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  bool _isAdValid(Map<String, dynamic> data, DateTime now) {
    if (data['isActive'] == false) return false;

    // placement 체크
    final docPlacement = (data['placement'] ?? 'all').toString().toLowerCase().trim();
    final targetPlacement = placement.toLowerCase().trim();
    if (docPlacement != 'all' && targetPlacement != 'all' && docPlacement != targetPlacement) {
      return false;
    }

    // 시작일 체크
    if (data['startDate'] != null) {
      DateTime? start;
      final val = data['startDate'];
      if (val is Timestamp) {
        start = val.toDate();
      } else if (val is String) {
        start = DateTime.tryParse(val);
      }
      if (start != null && now.isBefore(start)) return false;
    }

    // 종료일 체크
    if (data['endDate'] != null) {
      DateTime? end;
      final val = data['endDate'];
      if (val is Timestamp) {
        end = val.toDate();
      } else if (val is String) {
        end = DateTime.tryParse(val);
        if (end != null && val.length <= 10) {
          end = DateTime(end.year, end.month, end.day, 23, 59, 59);
        }
      }
      if (end != null && now.isAfter(end)) return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 1. 직접 넘겨준 데이터가 있는 경우 우선 사용
    if (title != null || targetUrl != null) {
      return _buildCardContent(
        context: context,
        cardTitle: title ?? "교원대생 맞춤 혜택 & 캠퍼스 소식",
        cardSubtitle: subtitle ?? "KNUE MATE와 함께하는 유용한 정보와 제휴 혜택을 확인해보세요.",
        cardCta: callToAction ?? "자세히 보기",
        cardIcon: icon ?? Icons.campaign_rounded,
        cardTargetUrl: targetUrl,
      );
    }

    // 2. Firebase 미초기화 시 기본 fallback 렌더링
    if (Firebase.apps.isEmpty) {
      return _buildDefaultFallback(context);
    }

    // 3. Firestore 'sponsors' 컬렉션 실시간 구독
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sponsors').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final now = DateTime.now();
          final validDocs = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data;
          }).where((data) => _isAdValid(data, now)).toList();

          if (validDocs.isNotEmpty) {
            // priority 높은 순, 없으면 기본 정렬
            validDocs.sort((a, b) {
              final int pa = (a['priority'] is num) ? (a['priority'] as num).toInt() : 0;
              final int pb = (b['priority'] is num) ? (b['priority'] as num).toInt() : 0;
              return pb.compareTo(pa);
            });

            final sponsor = validDocs.first;
            final sponsorTitle = sponsor['title']?.toString() ?? "교원대 제휴 스폰서";
            final sponsorSubtitle = sponsor['subtitle']?.toString() ?? "KNUE MATE 제휴 혜택을 확인해보세요.";
            final sponsorCta = sponsor['callToAction']?.toString() ?? "자세히 보기";
            final sponsorIcon = _parseIcon(sponsor['icon']);
            final sponsorUrl = sponsor['targetUrl']?.toString();

            return _buildCardContent(
              context: context,
              cardTitle: sponsorTitle,
              cardSubtitle: sponsorSubtitle,
              cardCta: sponsorCta,
              cardIcon: sponsorIcon,
              cardTargetUrl: sponsorUrl,
            );
          }
        }

        // 제휴 스폰서가 없거나 기간 만료 시 기본 fallback 카드 노출
        return _buildDefaultFallback(context);
      },
    );
  }

  Widget _buildDefaultFallback(BuildContext context) {
    return _buildCardContent(
      context: context,
      cardTitle: "교원대생 맞춤 혜택 & 캠퍼스 소식",
      cardSubtitle: "KNUE MATE와 함께하는 유용한 정보와 제휴 혜택을 확인해보세요.",
      cardCta: "자세히 보기",
      cardIcon: Icons.campaign_rounded,
      cardTargetUrl: null,
    );
  }

  Widget _buildCardContent({
    required BuildContext context,
    required String cardTitle,
    required String cardSubtitle,
    required String cardCta,
    required IconData cardIcon,
    required String? cardTargetUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    if (isCompact) {
      // 슬림형 인셋 스타일 (식단, 버스, 설정 탭 등)
      return Container(
        decoration: BoxDecoration(
          color: KnueTokens.surface(isDark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: KnueTokens.hairline(isDark),
            width: 0.8,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleTap(context, cardTargetUrl),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(cardIcon, size: 20, color: primaryColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "AD",
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cardTitle,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cardSubtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 메인 홈 화면용 인라인 카드 스타일
    return Container(
      decoration: BoxDecoration(
        color: KnueTokens.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: KnueTokens.hairline(isDark),
          width: 0.8,
        ),
        boxShadow: KnueTokens.cardShadow(isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleTap(context, cardTargetUrl),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: AD 라벨 + 스폰서 태그
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "AD",
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "청람 추천 & 스폰서",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 본문: 아이콘 + 제목/설명
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: isDark ? 0.2 : 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Icon(
                          cardIcon,
                          size: 24,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cardTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cardSubtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 하단: 액션 버튼
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cardCta,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: primaryColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
