import 'package:flutter/material.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 64, color: Color(0xFF00C853)),
          SizedBox(height: 16),
          Text('我的', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('个人信息设置', style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}
