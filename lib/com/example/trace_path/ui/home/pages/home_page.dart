import 'package:flutter/material.dart';
import 'package:trace_path/constants/colors.dart';
import 'location_page.dart';
import 'track_page.dart';
import 'guard_page.dart';
import 'mine_page.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/home_strings.dart' as hs;

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
    print('[HomePage] build');
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  void _showErrorDialog(BuildContext context, Object e, StackTrace stack) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hs.HomeStrings.errorTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stack.toString(),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(hs.HomeStrings.confirm),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.location_on, 'label': hs.HomeStrings.tabLocation},
      {'icon': Icons.route, 'label': hs.HomeStrings.tabTrack},
      {'icon': Icons.shield, 'label': hs.HomeStrings.tabGuard},
      {'icon': Icons.person, 'label': hs.HomeStrings.tabMine},
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
              onTap: () {
                print('[HomePage] tab点击: index=$i, label=${tabs[i]['label']}');
                try {
                  setState(() => _currentIndex = i);
                } catch (e, stack) {
                  _showErrorDialog(context, e, stack);
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tabs[i]['icon'] as IconData,
                      color: isActive ? AppColors.primary : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tabs[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? AppColors.primary : Colors.grey,
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
