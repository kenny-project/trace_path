import 'package:flutter/material.dart';
import '../../../services/location_settings_service.dart';
import '../../../services/background_location_service.dart';
import '../../../widgets/location_settings_dialog.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  // 服务单例
  final LocationSettingsService _settingsService = LocationSettingsService();
  final BackgroundLocationService _locationService = BackgroundLocationService();

  @override
  void initState() {
    super.initState();
    _locationService.init().catchError((e) {
      print('[MinePage] init 异常: $e');
    });
  }

  // 截图实测色值
  static const Color primaryGreen = Color(0xFF50D2B2);
  static const Color logoutRed = Color(0xFFFF5E3A);
  static const Color dividerColor = Color(0xFFEEEEEE);
  static const Color greyText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ===== 1. 头像 + 登录提示 =====
              _buildAvatarSection(),

              const SizedBox(height: 16),

              // ===== 2. 三个图标按钮 =====
              _buildQuickActions(),

              const SizedBox(height: 16),
              const Divider(height: 1, color: dividerColor),

              // ===== 3. 菜单列表 =====
              _buildMenuItem(
                icon: Icons.location_on,
                label: '实时定位',
                onTap: _showLocationSettings,
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.settings,
                label: '权限设置',
                onTap: () {},
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.phone,
                label: '联系我们',
                onTap: () {},
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.info,
                label: '关于我们',
                onTap: () {},
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: dividerColor),

              // ===== 4. 退出按钮 =====
              _buildLogoutButton(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLocationSettings() async {
    try {
      await _settingsService.load();
    } catch (e) {
      print('[MinePage] load 异常: $e');
    }
    if (!mounted) return;

    try {
      await showDialog(
        context: context,
        builder: (context) => LocationSettingsDialog(
          settingsService: _settingsService,
          locationService: _locationService,
        ),
      );
    } catch (e, stack) {
      print('[MinePage] 对话框异常: $e\n$stack');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发生错误'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.toString(), style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(stack.toString(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
    }
  }

  Widget _buildAvatarSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          // 头像
          GestureDetector(
            onTap: () {}, // 登录
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: primaryGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 12),
          // 点击登录
          GestureDetector(
            onTap: () {},
            child: const Text(
              '点击登录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 开通VIP
          GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('开通VIP', style: TextStyle(fontSize: 13, color: greyText)),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 16, color: greyText),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionItem(Icons.share, '点击分享', () {}),
          _buildActionItem(Icons.question_answer, '常见问题', () {}),
          _buildActionItem(Icons.menu_book, '实用教程', () {}),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryGreen, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: primaryGreen, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 15, color: Colors.black87)),
            ),
            Icon(Icons.chevron_right, color: greyText, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: logoutRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 0,
          ),
          child: const Text('退出当前账户', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
