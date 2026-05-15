import 'package:flutter/material.dart';

/// 앱 전역에서 사용하는 shimmer 스켈레톤 로딩 위젯
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 10,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2C2C30) : const Color(0xFFE8E8EE);
    final shimmerColor =
        isDark ? const Color(0xFF3D3D42) : const Color(0xFFF4F4F8);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final stops = [
          (_animation.value - 0.6).clamp(0.0, 1.0),
          _animation.value.clamp(0.0, 1.0),
          (_animation.value + 0.6).clamp(0.0, 1.0),
        ];
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [baseColor, shimmerColor, baseColor],
              stops: stops,
            ),
          ),
        );
      },
    );
  }
}

/// 식단 로딩 스켈레톤
class MealSkeletonCard extends StatelessWidget {
  const MealSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 60, height: 22, borderRadius: 11),
                const SizedBox(width: 12),
                SkeletonBox(width: 100, height: 16, borderRadius: 8),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            ...List.generate(6, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SkeletonBox(width: 8, height: 8, borderRadius: 4),
                  const SizedBox(width: 12),
                  SkeletonBox(
                    width: i % 3 == 0 ? 160 : i % 3 == 1 ? 130 : 180,
                    height: 16,
                  ),
                ],
              ),
            )),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 80, height: 14, borderRadius: 7),
                SkeletonBox(width: 100, height: 32, borderRadius: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 버스 카드 로딩 스켈레톤
class BusSkeletonCard extends StatelessWidget {
  const BusSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SkeletonBox(width: 52, height: 52, borderRadius: 16),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 18),
                const SizedBox(height: 8),
                SkeletonBox(width: 180, height: 14),
              ],
            ),
          ),
          SkeletonBox(width: 60, height: 36, borderRadius: 18),
        ],
      ),
    );
  }
}
