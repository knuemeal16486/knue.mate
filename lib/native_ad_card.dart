import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';
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
          "KNUE Mate는 한국교원대학교 학생들을 위한 비영리 서비스입니다.\n\n"
          "쾌적한 서버 운영 및 서비스 유지를 위한 제휴/광고 영역입니다.\n"
          "제휴 및 광고 문의: KNUE Mate 운영팀",
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
        cardSubtitle: subtitle ?? "KNUE Mate와 함께하는 유용한 정보와 제휴 혜택을 확인해보세요.",
        cardCta: callToAction ?? "자세히 보기",
        cardIcon: icon ?? Icons.campaign_rounded,
        cardImageUrl: imageUrl,
        cardTargetUrl: targetUrl,
      );
    }

    // 2. Firebase 미초기화 시 — Firestore는 못 쓰지만 AdMob은 Firebase와
    //    무관하니 그쪽부터 시도한다.
    if (Firebase.apps.isEmpty) {
      return _DefaultFallbackWithAdMob(isCompact: isCompact);
    }

    // 3. Firestore 'sponsors' 컬렉션 실시간 구독
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sponsors').snapshots(),
      builder: (context, snapshot) {
        // 규칙 미배포·권한 오류는 hasData가 false로만 나타나 조용히
        // fallback으로 넘어간다. 그 자체는 맞는 동작(광고 하나 때문에 화면이
        // 깨지면 안 된다)이지만, 로그가 없으면 "광고가 계속 안 뜬다"는 문제를
        // 진단할 길이 없다 — 실제로 sponsors 컬렉션에 규칙이 없어 전부
        // PERMISSION_DENIED였던 적이 있다.
        if (snapshot.hasError) {
          debugPrint('KnueNativeAdCard: sponsors 구독 실패: ${snapshot.error}');
        }
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
            final sponsorSubtitle = sponsor['subtitle']?.toString() ?? "KNUE Mate 제휴 혜택을 확인해보세요.";
            final sponsorCta = sponsor['callToAction']?.toString() ?? "자세히 보기";
            final sponsorIcon = _parseIcon(sponsor['icon']);
            final sponsorImageUrl = sponsor['imageUrl']?.toString();
            final sponsorUrl = sponsor['targetUrl']?.toString();

            return _buildCardContent(
              context: context,
              cardTitle: sponsorTitle,
              cardSubtitle: sponsorSubtitle,
              cardCta: sponsorCta,
              cardIcon: sponsorIcon,
              cardImageUrl: sponsorImageUrl,
              cardTargetUrl: sponsorUrl,
            );
          }
        }

        // 제휴 스폰서가 없거나 기간 만료 시 — AdMob으로 먼저 채워보고,
        // 그것도 안 되면 기본 안내 카드.
        return _DefaultFallbackWithAdMob(isCompact: isCompact);
      },
    );
  }

  Widget _buildDefaultFallback(BuildContext context) {
    return _buildCardContent(
      context: context,
      cardTitle: "교원대생 맞춤 혜택 & 캠퍼스 소식",
      cardSubtitle: "KNUE Mate와 함께하는 유용한 정보와 제휴 혜택을 확인해보세요.",
      cardCta: "자세히 보기",
      cardIcon: Icons.campaign_rounded,
      cardImageUrl: null,
      cardTargetUrl: null,
    );
  }

  Widget _buildCardContent({
    required BuildContext context,
    required String cardTitle,
    required String cardSubtitle,
    required String cardCta,
    required IconData cardIcon,
    required String? cardImageUrl,
    required String? cardTargetUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // 스폰서가 로고/사진(imageUrl)을 넣었으면 그걸, 아니면 아이콘을 담는
    // 정사각 박스. 예전에는 imageUrl을 받기만 하고 그리는 코드가 없어서
    // 제휴처가 이미지를 등록해도 항상 기본 아이콘만 나왔다.
    Widget mediaBox({
      required double size,
      required double radius,
      required double iconSize,
    }) {
      final iconBox = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Center(child: Icon(cardIcon, size: iconSize, color: primaryColor)),
      );
      if (cardImageUrl == null || cardImageUrl.isEmpty) return iconBox;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          cardImageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 잘못된 URL이거나 오프라인이면 조용히 아이콘으로 돌아간다 —
          // 광고 하나 때문에 깨진 이미지 아이콘이 보이면 안 된다.
          errorBuilder: (_, _, _) => iconBox,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : iconBox,
        ),
      );
    }

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
                  mediaBox(size: 36, radius: 10, iconSize: 20),
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
                    mediaBox(size: 44, radius: 14, iconSize: 24),
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

/// 스폰서(Firestore `sponsors` 컬렉션)가 없을 때 마지막 대체 수단.
/// AdMob 네이티브 광고를 먼저 띄워보고, 못 띄우면(웹·데스크톱, 미지원 플랫폼,
/// 노 필, 로드 실패) 기존 기본 안내 카드로 조용히 물러난다 — 광고 하나
/// 때문에 화면에 빈 공간이나 깨진 모습이 남으면 안 된다.
///
/// 처음부터 기본 안내 카드를 그려두고, AdMob이 로드에 성공했을 때만 그
/// 자리를 native 광고로 바꿔치기한다. 로딩 중 빈 화면이 잠깐 보이는 것보다
/// 이쪽이 덜 어색하다.
///
/// 컴팩트(isCompact) 자리(식단·버스·설정 탭)는 전용 압축 레이아웃
/// (native_ad_layout_compact.xml, NativeAdFactoryImpl(isCompact: true))을 쓴다
/// — KnueNativeAdCard의 압축 스폰서 카드와 같은 한 줄짜리 모양으로, 이미지
/// 없이 아이콘+제목/설명+버튼만 있다.
class _DefaultFallbackWithAdMob extends StatefulWidget {
  final bool isCompact;
  const _DefaultFallbackWithAdMob({required this.isCompact});

  @override
  State<_DefaultFallbackWithAdMob> createState() =>
      _DefaultFallbackWithAdMobState();
}

class _DefaultFallbackWithAdMobState extends State<_DefaultFallbackWithAdMob> {
  NativeAd? _ad;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final adUnitId = AdService.nativeAdUnitId;
    if (adUnitId == null) return; // 웹·데스크톱 등 미지원 플랫폼

    NativeAd(
      adUnitId: adUnitId,
      factoryId: AdService.nativeAdFactoryId(widget.isCompact),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _ad = ad as NativeAd);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('KnueNativeAdCard: AdMob 대체 광고 로드 실패: $error');
          ad.dispose();
          // 실패해도 이미 그려져 있는 기본 안내 카드가 그대로 남는다.
        },
      ),
    ).load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad != null) {
      // 네이티브 레이아웃의 실제 렌더 높이에 맞춘 고정 높이 — 플랫폼 뷰는
      // Flutter가 내재 크기를 알 수 없어 반드시 필요하다.
      final height = widget.isCompact ? 80.0 : 290.0;
      return SizedBox(height: height, child: AdWidget(ad: ad));
    }
    // 같은 파일(라이브러리) 안이라 private 메서드를 직접 호출할 수 있다.
    return KnueNativeAdCard(
      isCompact: widget.isCompact,
    )._buildDefaultFallback(context);
  }
}
