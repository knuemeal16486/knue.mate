import 'package:flutter/material.dart';
import 'premium_service.dart';

class PremiumUpgradeSheet extends StatefulWidget {
  const PremiumUpgradeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PremiumUpgradeSheet(),
    );
  }

  @override
  State<PremiumUpgradeSheet> createState() => _PremiumUpgradeSheetState();
}

class _PremiumUpgradeSheetState extends State<PremiumUpgradeSheet> {
  bool _isLoading = false;

  Future<void> _purchase() async {
    setState(() => _isLoading = true);
    try {
      await PremiumService.instance.buyPro();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isLoading = true);
    try {
      await PremiumService.instance.restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매 복원을 시도했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 크라운 아이콘
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade600, Colors.orange.shade400],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),

          const Text(
            'KNUE Mate Pro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '광고 없이 더 쾌적하게 이용하세요',
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // 기능 목록
          _FeatureRow(icon: Icons.block_rounded, color: Colors.red, label: '모든 광고 완전 제거'),
          _FeatureRow(icon: Icons.widgets_rounded, color: Colors.indigo, label: '홈 위젯 고급 테마 확장'),
          _FeatureRow(icon: Icons.local_fire_department_rounded, color: Colors.orange, label: '30일 칼로리 기록 & 그래프'),
          _FeatureRow(icon: Icons.notifications_active_rounded, color: Colors.green, label: '버스 알림 고급 설정'),
          const SizedBox(height: 28),

          // 구매 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _purchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('₩3,900 영구 구매', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),

          // 복원 + 닫기
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _isLoading ? null : _restore,
                child: Text('구매 복원', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ),
              Text('·', style: TextStyle(color: isDark ? Colors.white24 : Colors.grey.shade300)),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('나중에', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _FeatureRow({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
