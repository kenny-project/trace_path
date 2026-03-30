import 'package:flutter/material.dart';
import 'package:trace_path/constants/colors.dart';
import '../../../services/location_settings_service.dart';
import '../../../services/background_location_service.dart';
import '../../../services/user_service.dart';
import '../../../services/friend_service.dart';
import '../../../widgets/location_settings_dialog.dart';
import 'permission_settings_page.dart';
import 'login_page.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/mine_strings.dart' as ms;

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final LocationSettingsService _settingsService = LocationSettingsService();
  final BackgroundLocationService _locationService = BackgroundLocationService();
  final UserService _userService = UserService();
  final FriendService _friendService = FriendService();

  @override
  void initState() {
    super.initState();
    _locationService.init().catchError((e) {
      print('[MinePage] init 异常: $e');
    });
    _initUser();
  }

  Future<void> _initUser() async {
    await _userService.init();
    setState(() {});
  }

  /// 跳转到登录页面
  void _goToLogin() {
    if (_userService.isLoggedIn) {
      _showToast('当前已登录');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    ).then((_) {
      // 登录返回后刷新
      setState(() {});
    });
  }

  /// 处理退出登录
  Future<void> _handleLogout() async {
    await _userService.clearUser();
    // 清空好友列表，重新初始化"我自己"
    _friendService.clearAllFriends();
    await _friendService.init();
    setState(() {});
    _showToast('已退出登录');
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  static const Color primaryGreen = AppColors.primary;
  static const Color logoutRed = AppColors.logoutRed;
  static const Color dividerColor = AppColors.divider2;
  static const Color greyText = AppColors.textHint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 16),
              _buildQuickActions(),
              const SizedBox(height: 16),
              const Divider(height: 1, color: dividerColor),
              _buildMenuItem(
                icon: Icons.location_on,
                label: ms.MineStrings.realTimeLocation,
                onTap: _showLocationSettings,
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.settings,
                label: ms.MineStrings.permissionSettings,
                onTap: () {
                  print('[MinePage] 点击: 权限设置');
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PermissionSettingsPage()),
                  );
                },
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.phone,
                label: ms.MineStrings.contactUs,
                onTap: () {},
              ),
              const Divider(height: 1, color: dividerColor, indent: 56),
              _buildMenuItem(
                icon: Icons.info,
                label: ms.MineStrings.aboutUs,
                onTap: () {},
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: dividerColor),
              if (_userService.isLoggedIn) _buildLogoutButton(),
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
          title: Text(ms.MineStrings.errorTitle),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ms.MineStrings.confirm)),
          ],
        ),
      );
    }
  }

  Widget _buildAvatarSection() {
    final phone = _userService.currentPhoneNumber;
    final isLoggedIn = phone != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          GestureDetector(
            onTap: _goToLogin,
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
          GestureDetector(
            onTap: _goToLogin,
            child: Text(
              isLoggedIn ? phone : ms.MineStrings.clickToLogin,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ms.MineStrings.openVip, style: TextStyle(fontSize: 13, color: greyText)),
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
          _buildActionItem(Icons.share, ms.MineStrings.clickToShare, () {}),
          _buildActionItem(Icons.question_answer, ms.MineStrings.faq, () {}),
          _buildActionItem(Icons.menu_book, ms.MineStrings.tutorial, () {}),
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
          onPressed: _handleLogout,
          style: ElevatedButton.styleFrom(
            backgroundColor: logoutRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 0,
          ),
          child: Text(ms.MineStrings.logout, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
