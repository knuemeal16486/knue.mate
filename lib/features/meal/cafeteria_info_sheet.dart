import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../ui_utils.dart';

/// 교직원 식당 상시 선택식 메뉴·가격표 및 식당 운영 정보 바텀시트.
Future<void> showCafeteriaInfoSheet(BuildContext context, MealSource source) {
  final isSado = source == MealSource.a;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primary = Theme.of(context).primaryColor;
  final accentFg = KnueTokens.accentForeground(primary, isDark);

  const staffMenus = [
    (
      category: '🍲 한식 & 찌개',
      items: [
        (name: '느티헌 교원백반', price: '6,000'),
        (name: '매화헌 교원백반', price: '6,000'),
        (name: '촌돼지김치찌개', price: '6,500'),
      ],
    ),
    (
      category: '🍜 라면',
      items: [
        (name: '해장라면+공기밥', price: '5,000'),
        (name: '떡만두라면+공기밥', price: '5,200'),
        (name: '치즈라면+공기밥', price: '5,200'),
        (name: '부대라면+공기밥', price: '5,500'),
      ],
    ),
    (
      category: '🍛 돈까스 & 알밥',
      items: [
        (name: '등심돈까스', price: '6,000'),
        (name: '등심돈까스+알밥', price: '6,500'),
        (name: '치즈돈까스', price: '6,500'),
        (name: '치즈돈까스+알밥', price: '7,000'),
        (name: '고구마치즈돈까스', price: '6,500'),
        (name: '고구마치즈돈까스+알밥', price: '7,000'),
        (name: '치킨까스', price: '6,000'),
        (name: '치킨까스+알밥', price: '6,500'),
      ],
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentFg.withValues(alpha: isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 22,
                      color: accentFg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${source.label} 운영 정보',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        isSado ? '사도교육원 관리동 1층' : '학생회관 1층 느티헌·매화헌',
                        style: TextStyle(
                          fontSize: 12,
                          color: KnueTokens.caption(isDark),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KnueCard(
                        isDark: isDark,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.place_outlined,
                              label: '위치',
                              text: isSado ? '관리동 1층' : '학생회관 1층',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.payments_outlined,
                              label: '가격',
                              text: isSado ? '의무입사생 무료' : '6,000원 (느티헌)',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.access_time_rounded,
                              label: '운영',
                              text: isSado ? '연중무휴' : '주말·공휴일 휴무',
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                      if (!isSado) ...[
                        const SizedBox(height: 20),
                        const Text(
                          '선택식 상시 메뉴',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final group in staffMenus) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.category,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: accentFg,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                KnueCard(
                                  isDark: isDark,
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < group.items.length; i++) ...[
                                        if (i > 0)
                                          Divider(
                                            height: 0.5,
                                            thickness: 0.5,
                                            color: KnueTokens.hairline(isDark),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  group.items[i].name,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${group.items[i].price}원',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  fontFeatures:
                                                      KnueTokens.tabularFigures,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: KnueTokens.onAccent(primary),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '닫기',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KnueTokens.caption(isDark)),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KnueTokens.caption(isDark),
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
