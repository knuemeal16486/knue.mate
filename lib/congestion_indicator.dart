import 'package:flutter/material.dart';

class CongestionIndicator extends StatelessWidget {
  final String level; // empty, normal, crowded, full

  const CongestionIndicator(this.level, {Key? key}) : super(key: key);

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
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(text, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}
