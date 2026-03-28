import 'package:flutter/material.dart';

class TrackPage extends StatelessWidget {
  const TrackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route, size: 64, color: Color(0xFF00C853)),
          SizedBox(height: 16),
          Text('轨迹页', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('历史轨迹查询等功能', style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}
