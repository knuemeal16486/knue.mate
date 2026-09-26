import 'package:flutter/material.dart';

import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_service.dart';
import 'ui_utils.dart';

/// 자취방 목록 뷰 위젯
class HousingListView extends StatelessWidget {
  final List<BaseBuilding> buildings;
  final Map<String, HousingSummary> summaries;
  final Map<String, HousingBuildingOverride> overrides;
  final Set<String> favoriteIds;
  final HousingFilter filter;
  final HousingZone? selectedZone;
  final bool onlyFavorites;
  final String searchQuery;
  final HousingSortType sortType;
  final bool isDark;
  final Color themeColor;
  final ValueChanged<HousingSortType> onSortChanged;
  final ValueChanged<BaseBuilding> onTapBuilding;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<BaseBuilding>? onShowOnMap;

  const HousingListView({
    super.key,
    required this.buildings,
    required this.summaries,
    required this.overrides,
    required this.favoriteIds,
    required this.filter,
    required this.selectedZone,
    required this.onlyFavorites,
    required this.searchQuery,
    required this.sortType,
    required this.isDark,
    required this.themeColor,
    required this.onSortChanged,
    required this.onTapBuilding,
    required this.onToggleFavorite,
    this.onShowOnMap,
  });

  OneRoomName? _resolvedKnown(String buildingId) {
    final override = overrides[buildingId];
    if (override != null && override.isNamed) return override.toOneRoomName();
    final oneRoomId = summaries[buildingId]?.oneRoomId;
    return oneRoomId == null ? null : kOneRoomNameById[oneRoomId];
  }

  String _displayName(BaseBuilding b) {
    return _resolvedKnown(b.id)?.name ?? b.officialName ?? '이름 미확인 건물';
  }

  @override
  Widget build(BuildContext context) {
    // 1. 후보 건물 필터링 (원룸으로 볼 만한 건물)
    final candidateBuildings = buildings.where((b) {
      if (!looksLikeOneRoom(b, summaries)) return false;

      // 구역 필터
      if (selectedZone != null) {
        final k = _resolvedKnown(b.id);
        if (k == null || k.zone != selectedZone) return false;
      }

      // 찜한 방 필터
      if (onlyFavorites && !favoriteIds.contains(b.id)) return false;

      // "내 조건 찾기" 필터
      if (!filter.isEmpty) {
        final v = evaluateHousingFilter(summaries[b.id], overrides[b.id], filter).verdict;
        if (!housingPassesFilter(v, filter)) return false;
      }

      // 검색어 필터
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final name = _displayName(b).toLowerCase();
        final road = (b.road ?? '').toLowerCase();
        final no = (b.buildingNo ?? '').toLowerCase();
        if (!name.contains(q) && !road.contains(q) && !no.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();

    // 2. 정렬 적용 (순수 함수)
    final sorted = sortHousingItems<BaseBuilding>(
      items: candidateBuildings,
      sortType: sortType,
      getSummary: (b) => summaries[b.id] ?? HousingSummary.empty,
      getBuilding: (b) => b,
      getName: _displayName,
    );

    return Column(
      children: [
        // 상단 검색바 & 구역칩 영역 여백 (약 92px)
        const SizedBox(height: 94),

        // 정렬 및 결과 카운트 바
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '전체 ${sorted.length}곳',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontFeatures: KnueTokens.tabularFigures,
                ),
              ),
              const Spacer(),

              // 정렬 팝업 메뉴
              PopupMenuButton<HousingSortType>(
                initialValue: sortType,
                onSelected: onSortChanged,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 15,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sortType.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ],
                  ),
                ),
                itemBuilder: (context) {
                  return HousingSortType.values.map((st) {
                    final isSel = st == sortType;
                    return PopupMenuItem<HousingSortType>(
                      value: st,
                      child: Row(
                        children: [
                          if (isSel)
                            Icon(Icons.check_rounded, size: 16, color: themeColor)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(
                            st.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                              color: isSel ? themeColor : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
              ),
            ],
          ),
        ),

        // 목록 리스트
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '조건에 맞는 자취방이 없어요',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '필터 금액을 올리거나 검색어를 줄여보세요',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final b = sorted[index];
                    final s = summaries[b.id] ?? HousingSummary.empty;
                    final known = _resolvedKnown(b.id);
                    final isFav = favoriteIds.contains(b.id);
                    final name = _displayName(b);

                    final distGate = walkingDistanceMeters(b.center, CampusLandmark.mainGate);
                    final distLib = walkingDistanceMeters(b.center, CampusLandmark.library);

                    final monthly = s.avgMonthlyTotal ?? s.avgRent;

                    return InkWell(
                      onTap: () => onTapBuilding(b),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.06),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 상단 줄: 구역 뱃지 + 이름 + (지도에서 보기 / 찜) 액션
                            Row(
                              children: [
                                // 구역 딱지는 "캠퍼스 시설"만.
                                if (known != null && b.isCampus) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: badgeZone(b, known).color.withValues(alpha: isDark ? 0.22 : 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: badgeZone(b, known).color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          badgeZone(b, known).label,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: badgeZone(b, known).color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (onShowOnMap != null)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    icon: Icon(
                                      Icons.map_outlined,
                                      color: isDark ? Colors.white60 : Colors.black45,
                                      size: 19,
                                    ),
                                    tooltip: '지도에서 위치 보기',
                                    onPressed: () => onShowOnMap!(b),
                                  ),
                                GestureDetector(
                                  onTap: () => onToggleFavorite(b.id),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: isFav ? Colors.redAccent : (isDark ? Colors.white38 : Colors.black26),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),

                            // 주소 및 층수
                            Text(
                              [
                                b.addressLabel,
                                '지상 ${overrides[b.id]?.floors ?? b.floors}층',
                                if (known?.builtYear ?? builtYearByName(b.officialName) case final year?)
                                  '$year년 준공',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontFeatures: KnueTokens.tabularFigures,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 시세 및 제보 현황 앵커 박스
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (s.hasData && monthly != null) ...[
                                    Text(
                                      '월 $monthly',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontFeatures: KnueTokens.tabularFigures,
                                      ),
                                    ),
                                    Text(
                                      '만원',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    if (s.avgDeposit != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '/ 보증금 ${s.avgDeposit}만원',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                          fontFeatures: KnueTokens.tabularFigures,
                                        ),
                                      ),
                                    ],
                                  ] else ...[
                                    Icon(
                                      Icons.help_outline_rounded,
                                      size: 14,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '시세 제보 대기 중',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white38 : Colors.black38,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      s.hasData ? s.sourceLabel : '첫 제보 필요',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                        fontFeatures: KnueTokens.tabularFigures,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 도보 거리 뱃지
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (isDark ? Colors.blueAccent : Colors.blue)
                                          .withValues(alpha: isDark ? 0.16 : 0.09),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.directions_walk_rounded,
                                          size: 14,
                                          color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '정문 ${walkingMinutes(distGate)}분 (${distGate}m)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                                              fontFeatures: KnueTokens.tabularFigures,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (isDark ? Colors.purpleAccent : Colors.purple)
                                          .withValues(alpha: isDark ? 0.16 : 0.09),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.menu_book_rounded,
                                          size: 13,
                                          color: isDark ? Colors.purpleAccent : Colors.purple.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '도서관 ${walkingMinutes(distLib)}분 (${distLib}m)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? Colors.purpleAccent : Colors.purple.shade700,
                                              fontFeatures: KnueTokens.tabularFigures,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // 특징 태그 및 후기 미리보기
                            if (s.topFeatures.isNotEmpty || s.recentReviews.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if (s.roomTypes.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF0),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        s.roomTypes.map((t) => t.label).join('/'),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ...s.topFeatures.take(3).map(
                                    (f) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF0),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        f,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // 최신 후기 한줄 미리보기
                            if (s.recentReviews.isNotEmpty) ...[
                              const SizedBox(height: 9),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF242426) : const Color(0xFFF6F6F8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                                    width: 0.6,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '💬 ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '"${s.recentReviews.first}"',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.35,
                                          fontStyle: FontStyle.italic,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
