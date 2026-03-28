import 'package:flutter/material.dart';
import 'location_page.dart';
import 'track_page.dart';
import 'guard_page.dart';
import 'mine_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    LocationPage(),
    TrackPage(),
    GuardPage(),
    MinePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.location_on, 'label': '定位'},
      {'icon': Icons.route, 'label': '轨迹'},
      {'icon': Icons.shield, 'label': '守护'},
      {'icon': Icons.person, 'label': '我的'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentIndex = i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tabs[i]['icon'] as IconData,
                      color: isActive ? const Color(0xFF00C853) : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tabs[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? const Color(0xFF00C853) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
