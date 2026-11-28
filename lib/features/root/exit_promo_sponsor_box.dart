import 'package:flutter/material.dart';

/// 행사 주최 측(광고주) 모집 안내 카드.
///
/// 좁은 폭에서도 문구가 줄바꿈 없이 한 줄로 유지되는지
/// `test/exit_promo_box_test.dart`에서 검증한다.
class ExitPromoSponsorBox extends StatelessWidget {
  final String phone;
  final String priceText;
  final Color accent;
  final VoidCallback onTap;

  const ExitPromoSponsorBox({
    super.key,
    required this.phone,
    required this.priceText,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.white60 : Colors.black54;

    return Semantics(
      button: true,
      label: "행사 홍보 문의 $phone",
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Text("📣", style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "행사 홍보하고 싶으신가요?",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(priceText, style: TextStyle(fontSize: 11, color: sub)),
                    const SizedBox(height: 4),
                    Text(
                      "문의 · $phone",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.sms_rounded, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
