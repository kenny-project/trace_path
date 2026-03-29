import 'package:flutter/material.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/home_strings.dart' as hs;

class GuardPage extends StatelessWidget {
  const GuardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield, size: 64, color: Color(0xFF00C853)),
          const SizedBox(height: 16),
          Text(
            hs.GuardStrings.pageTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            hs.GuardStrings.developing,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
