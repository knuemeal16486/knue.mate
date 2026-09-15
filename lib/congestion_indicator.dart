import 'package:flutter/material.dart';

class CongestionIndicator extends StatelessWidget {
  final String level; // empty, normal, crowded, full

  /// 실제 차량 센서값이 아니라 시간대 기준 추정치일 때 true.
  ///
  /// 국토교통부 버스위치정보 API는 혼잡도 필드를 아예 안 준다 — 그래서 지금은
  /// 이 값이 사실상 항상 true다. 추정치를 실측처럼 보여주면("만석"이라고 딱
  /// 잘라 말하면) 사용자가 실제 상황과 다를 때 앱을 못 믿게 된다. 작은 "예상"
  /// 표시 하나로 그 차이를 밝힌다.
  final bool isEstimated;

  const CongestionIndicator(
    this.level, {
    super.key,
    this.isEstimated = true,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String text;

    switch (level) {
      case 'full':
        icon = Icons.people;
        color = Colors.red;
        text = '만석';
        break;
      case 'crowded':
        icon = Icons.people_outline;
        color = Colors.orange;
        text = '혼잡';
        break;
      case 'empty':
        icon = Icons.person;
        color = Colors.green;
        text = '여유';
        break;
      default:
        icon = Icons.person_outline;
        color = Colors.grey;
        text = '보통';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(text, style: TextStyle(fontSize: 10, color: color)),
        if (isEstimated) ...[
          const SizedBox(width: 2),
          Text(
            '(예상)',
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
          ),
        ],
      ],
    );
  }
}
