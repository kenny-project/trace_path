import 'dart:io';
import 'package:trace_path/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/permission_strings.dart' as ps;
import 'package:trace_path/constants/brand_strings.dart';

/// 权限设置页
class PermissionSettingsPage extends StatefulWidget {
  const PermissionSettingsPage({super.key});

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage>
    with WidgetsBindingObserver {
  static const Color primaryGreen = AppColors.primary;

  // 权限状态
  bool _locationAlwaysGranted = false;
  bool _locationWhenInUseGranted = false;
  bool _backgroundLocationGranted = false;
  bool _batteryOptimizationGranted = false;
  bool _notificationGranted = false;
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    if (!mounted) return;

    final locationAlways = await Permission.locationAlways.status;
    final locationWhenInUse = await Permission.locationWhenInUse.status;
    final backgroundLocation = await Permission.location.status;
    final batteryOpt = await PermissionService.isIgnoringBatteryOptimizations();
    final notification = await Permission.notification.status;

    if (!mounted) return;

    setState(() {
      _locationAlwaysGranted = locationAlways.isGranted;
      _locationWhenInUseGranted = locationWhenInUse.isGranted;
      _backgroundLocationGranted = backgroundLocation.isGranted;
      _batteryOptimizationGranted = batteryOpt;
      _notificationGranted = notification.isGranted;
      _isCheckingPermissions = false;
    });
  }

  Widget _buildPermissionStatus({
    required bool isGranted,
    required String grantedText,
    required String notGrantedText,
    required List<String> missingPermissions,
  }) {
    final Color statusColor = isGranted ? AppColors.primary : AppColors.danger;
    final String displayText = isGranted ? grantedText : notGrantedText;
    final List<String> displayMissing = isGranted ? [] : missingPermissions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isGranted ? Icons.check_circle : Icons.cancel,
              color: statusColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              displayText,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (displayMissing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.lightYellow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ps.PermissionStrings.missingPermissions,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                ...displayMissing.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            p,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          ps.PermissionStrings.pageTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              setState(() => _isCheckingPermissions = true);
              _checkAllPermissions();
            },
          ),
        ],
      ),
      body: _isCheckingPermissions
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPermissionCard(
                  icon: Icons.location_on,
                  title: ps.PermissionStrings.locationTitle,
                  description: ps.PermissionStrings.locationDesc,
                  buttonLabel: ps.PermissionStrings.quickSet,
                  onTap: _openLocationSettings,
                  helpOnTap: _showLocationHelpDialog,
                  statusWidget: _buildPermissionStatus(
                    isGranted:
                        _locationAlwaysGranted && _backgroundLocationGranted,
                    grantedText: ps.PermissionStrings.locationGranted,
                    notGrantedText: ps.PermissionStrings.locationNotGranted,
                    missingPermissions: [
                      if (!_backgroundLocationGranted)
                        ps.PermissionStrings.backgroundLocation,
                      if (!_locationWhenInUseGranted)
                        ps.PermissionStrings.foregroundLocation,
                      if (!_locationAlwaysGranted)
                        ps.PermissionStrings.alwaysLocation,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  icon: Icons.battery_std,
                  title: ps.PermissionStrings.batteryTitle,
                  description: ps.PermissionStrings.batteryDesc,
                  buttonLabel: ps.PermissionStrings.quickSet,
                  onTap: _openBatteryOptimizationSettings,
                  helpOnTap: _showBatteryHelpDialog,
                  statusWidget: _buildPermissionStatus(
                    isGranted: _batteryOptimizationGranted,
                    grantedText: ps.PermissionStrings.batteryGranted,
                    notGrantedText: ps.PermissionStrings.batteryNotGranted,
                    missingPermissions: [
                      ps.PermissionStrings.batteryOptimization,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  icon: Icons.history,
                  title: ps.PermissionStrings.backgroundTitle,
                  description: ps.PermissionStrings.backgroundDesc,
                  buttonLabel: ps.PermissionStrings.quickSet,
                  onTap: _openAutoStartSettings,
                  helpOnTap: _showAutoStartHelpDialog,
                  statusWidget: _buildPermissionStatus(
                    isGranted: _batteryOptimizationGranted,
                    grantedText: ps.PermissionStrings.backgroundGranted,
                    notGrantedText: ps.PermissionStrings.backgroundNotGranted,
                    missingPermissions: [
                      ps.PermissionStrings.backgroundPermission,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  icon: Icons.notifications,
                  title: ps.PermissionStrings.notificationTitle,
                  description: ps.PermissionStrings.notificationDesc,
                  buttonLabel: ps.PermissionStrings.quickSet,
                  onTap: _openNotificationSettings,
                  helpOnTap: _showNotificationHelpDialog,
                  statusWidget: _buildPermissionStatus(
                    isGranted: _notificationGranted,
                    grantedText: ps.PermissionStrings.notificationGranted,
                    notGrantedText: ps.PermissionStrings.notificationNotGranted,
                    missingPermissions: [
                      ps.PermissionStrings.notificationPermission,
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildWarningCard(),
              ],
            ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonLabel,
    required VoidCallback onTap,
    required Widget statusWidget,
    VoidCallback? helpOnTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (helpOnTap != null)
                GestureDetector(
                  onTap: helpOnTap,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.help_outline,
                      color: Colors.grey.shade600,
                      size: 18,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  onTap();
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      setState(() => _isCheckingPermissions = true);
                      _checkAllPermissions();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          statusWidget,
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightYellow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightOrangeBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: AppColors.warningOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ps.PermissionStrings.warningTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ps.PermissionStrings.warningContent,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade800,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocationSettings() async {
    final locationStatus = await Permission.locationAlways.status;
    final locationWhenInUseStatus = await Permission.locationWhenInUse.status;

    if (locationStatus.isGranted && locationWhenInUseStatus.isGranted) {
      Fluttertoast.showToast(
        msg: ps.PermissionStrings.locationAlreadyGranted,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
      return;
    }

    final alwaysResult = await Permission.locationAlways.request();
    final whenInUseResult = await Permission.locationWhenInUse.request();

    if (alwaysResult.isGranted && whenInUseResult.isGranted) {
      _checkAllPermissions();
    } else {
      await openAppSettings();
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    final isIgnoring = await PermissionService.isIgnoringBatteryOptimizations();
    if (isIgnoring) {
      Fluttertoast.showToast(
        msg: ps.PermissionStrings.batteryAlreadyGranted,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
      return;
    }
    await PermissionService.requestIgnoreBatteryOptimization();
  }

  Future<void> _openNotificationSettings() async {
    final notificationStatus = await Permission.notification.status;
    if (notificationStatus.isGranted) {
      Fluttertoast.showToast(
        msg: ps.PermissionStrings.notificationAlreadyGranted,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
      return;
    }

    final result = await Permission.notification.request();

    if (result.isGranted) {
      _checkAllPermissions();
    } else if (result.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _openAutoStartSettings() async {
    await PermissionService.openAutoStartSettings();
  }

  Future<void> _showAutoStartHelpDialog() async {
    final brand = await PermissionService.getPhoneBrand();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AutoStartHelpContent(brand: brand),
    );
  }

  Future<void> _showLocationHelpDialog() async {
    final brand = await PermissionService.getPhoneBrand();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LocationHelpContent(brand: brand),
    );
  }

  Future<void> _showBatteryHelpDialog() async {
    final brand = await PermissionService.getPhoneBrand();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BatteryHelpContent(brand: brand),
    );
  }

  Future<void> _showNotificationHelpDialog() async {
    final brand = await PermissionService.getPhoneBrand();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _NotificationHelpContent(brand: brand),
    );
  }
}

/// 定位权限帮助内容
class _LocationHelpContent extends StatelessWidget {
  final String brand;

  const _LocationHelpContent({required this.brand});

  @override
  Widget build(BuildContext context) {
    final helpInfo = BrandStrings.getBatteryHelpInfo(brand);
    return _HelpContentBuilder(
      icon: Icons.location_on,
      title:
          '${helpInfo['brandName']} ${ps.PermissionStrings.locationHelpTitle}',
      path: ps.PermissionStrings.locationHelpPath,
      switches: [
        {
          'name': ps.PermissionStrings.locationHelpStep1Name,
          'desc': ps.PermissionStrings.locationHelpStep1Desc,
        },
        {
          'name': ps.PermissionStrings.locationHelpStep2Name,
          'desc': ps.PermissionStrings.locationHelpStep2Desc,
        },
        {
          'name': ps.PermissionStrings.locationHelpStep3Name,
          'desc': ps.PermissionStrings.locationHelpStep3Desc,
        },
      ],
    );
  }
}

/// 电池优化帮助内容
class _BatteryHelpContent extends StatelessWidget {
  final String brand;

  const _BatteryHelpContent({required this.brand});

  @override
  Widget build(BuildContext context) {
    final helpInfo = BrandStrings.getBatteryHelpInfo(brand);
    return _HelpContentBuilder(
      icon: Icons.battery_std,
      title:
          '${helpInfo['brandName']} ${ps.PermissionStrings.batteryHelpTitle}',
      path: helpInfo['path'] as String,
      switches: helpInfo['switches'] as List<Map<String, String>>,
    );
  }
}

/// 通知权限帮助内容
class _NotificationHelpContent extends StatelessWidget {
  final String brand;

  const _NotificationHelpContent({required this.brand});

  @override
  Widget build(BuildContext context) {
    final helpInfo = BrandStrings.getBatteryHelpInfo(brand);
    return _HelpContentBuilder(
      icon: Icons.notifications,
      title:
          '${helpInfo['brandName']} ${ps.PermissionStrings.notificationHelpTitle}',
      path: ps.PermissionStrings.notificationHelpPath,
      switches: [
        {
          'name': ps.PermissionStrings.notificationHelpStep1Name,
          'desc': ps.PermissionStrings.notificationHelpStep1Desc,
        },
        {
          'name': ps.PermissionStrings.notificationHelpStep2Name,
          'desc': ps.PermissionStrings.notificationHelpStep2Desc,
        },
      ],
    );
  }
}

/// 通用帮助内容构建器
class _HelpContentBuilder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String path;
  final List<Map<String, String>> switches;

  const _HelpContentBuilder({
    required this.icon,
    required this.title,
    required this.path,
    required this.switches,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.route, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    path,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ps.PermissionStrings.requiredSwitches,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...switches.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          item['desc']!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 后台运行权限帮助内容
class _AutoStartHelpContent extends StatelessWidget {
  final String brand;

  const _AutoStartHelpContent({required this.brand});

  @override
  Widget build(BuildContext context) {
    final helpInfo = BrandStrings.getAutoStartHelpInfo(brand);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.help_outline,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                '${helpInfo['brandName']} ${ps.PermissionStrings.helpDialogTitle}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.route, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    helpInfo['path']!,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ps.PermissionStrings.switchLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...(helpInfo['switches'] as List<Map<String, String>>).map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          item['desc']!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 权限设置服务（供外部调用）
class PermissionService {
  static Future<Map<Permission, PermissionStatus>>
  requestAllPermissions() async {
    final results = <Permission, PermissionStatus>{};

    results[Permission.locationAlways] = await Permission.locationAlways
        .request();

    if (Platform.isAndroid) {
      results[Permission.notification] = await Permission.notification
          .request();
    }

    results[Permission.storage] = await Permission.storage.request();

    return results;
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await const MethodChannel(
        'com.kenny.trace_path/location_service',
      ).invokeMethod<bool>('isIgnoringBatteryOptimizations');
      print('[PermissionService] isIgnoringBatteryOptimizations: $result');
      return result ?? false;
    } catch (e) {
      print('[PermissionService] isIgnoringBatteryOptimizations 异常: $e');
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (Platform.isAndroid) {
      await openBatteryOptimizationSettings();
      return true;
    }
    return false;
  }

  /// 跳转电池优化白名单设置（按品牌）
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;

    final manufacturer = await _getManufacturer();
    print('[PermissionService] openBatteryOptimizationSettings() 被调用');
    print('[PermissionService] 检测到手机品牌: $manufacturer');

    String? pkg;
    String? cls;

    // 各品牌电池优化页面的intent（部分品牌共用后台运行的页面）
    switch (manufacturer) {
      case 'huawei':
        // 华为使用系统电池优化页面
        pkg = 'com.android.settings';
        cls = 'com.android.settings.BatterySettings';
        break;
      case 'honor':
        // 荣耀也使用系统电池优化页面
        pkg = 'com.android.settings';
        cls = 'com.android.settings.BatterySettings';
        break;
      case 'xiaomi':
        // 小米使用MIUI电池管理
        pkg = 'com.miui.powerkeeper';
        cls = 'com.miui.powerkeeper.ui.HiddenAppsConfigActivity';
        break;
      case 'vivo':
        // vivo使用后台管理页面
        pkg = 'com.vivo.permissionmanager';
        cls = 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity';
        break;
      case 'oppo':
        // OPPO使用电池优化页面
        pkg = 'com.coloros.oppoguardelf';
        cls = 'com.coloros.powermanager.fuelgaue.PowerUsageModelActivity';
        break;
      case 'samsung':
        // 三星使用电池页面
        pkg = 'com.samsung.android.lool';
        cls = 'com.samsung.android.sm.ui.battery.BatteryActivity';
        break;
      case 'oneplus':
        // 一加使用电池优化
        pkg = 'com.oneplus.security';
        cls =
            'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity';
        break;
      default:
        pkg = null;
        cls = null;
    }

    print('[PermissionService] 电池优化跳转参数 - pkg: $pkg, cls: $cls');

    try {
      final result = await const MethodChannel(
        'com.kenny.trace_path/location_service',
      ).invokeMethod('openBatteryOptimization', {'package': pkg, 'class': cls});
      print('[PermissionService] openBatteryOptimization 返回: $result');
      if (result != true) {
        print('[PermissionService] 跳转失败，fallback到应用详情页');
        await openAppSettings();
      } else {
        print('[PermissionService] 跳转成功');
      }
    } catch (e) {
      print('[PermissionService] 跳转异常: $e，fallback到应用详情页');
      await openAppSettings();
    }
  }

  static Future<void> openAutoStartSettings() async {
    if (!Platform.isAndroid) return;

    final manufacturer = await _getManufacturer();
    print('[PermissionService] openAutoStartSettings() 被调用');
    print('[PermissionService] 检测到手机品牌: $manufacturer');

    String? pkg;
    String? cls;

    switch (manufacturer) {
      case 'huawei':
        pkg = 'com.huawei.systemmanager';
        cls =
            'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity';
        break;
      case 'honor':
        pkg = 'com.hihonor.systemmanager';
        cls =
            'com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity';
        break;
      case 'xiaomi':
        pkg = 'com.miui.securitycenter';
        cls = 'com.miui.permcenter.autostart.AutoStartManagementActivity';
        break;
      case 'vivo':
        pkg = 'com.vivo.permissionmanager';
        cls = 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity';
        break;
      case 'oppo':
        pkg = 'com.coloros.safecenter';
        cls =
            'com.coloros.safecenter.permission.startup.StartupAppListActivity';
        break;
      case 'samsung':
        pkg = 'com.samsung.android.lool';
        cls = 'com.samsung.android.sm.ui.battery.BatteryActivity';
        break;
      case 'oneplus':
        pkg = 'com.oneplus.security';
        cls =
            'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity';
        break;
      default:
        pkg = null;
        cls = null;
    }

    print('[PermissionService] 跳转参数 - pkg: $pkg, cls: $cls');

    try {
      if (pkg != null && cls != null) {
        final result = await const MethodChannel(
          'com.kenny.trace_path/location_service',
        ).invokeMethod('openAutoStart', {'package': pkg, 'class': cls});
        print('[PermissionService] openAutoStart 返回: $result');
        if (result != true) {
          print('[PermissionService] 跳转失败，fallback到应用详情页');
          await openAppSettings();
        } else {
          print('[PermissionService] 跳转成功');
        }
      } else {
        print('[PermissionService] 未匹配到品牌，fallback到应用详情页');
        await openAppSettings();
      }
    } catch (e) {
      print('[PermissionService] 跳转异常: $e，fallback到应用详情页');
      await openAppSettings();
    }
  }

  static Future<String> _getManufacturer() async {
    try {
      final result = await const MethodChannel(
        'com.kenny.trace_path/location_service',
      ).invokeMethod<String>('getManufacturer');
      return (result ?? 'unknown').toLowerCase();
    } catch (e) {
      return 'unknown';
    }
  }

  static Future<String> getPhoneBrand() async {
    return await _getManufacturer();
  }
}
