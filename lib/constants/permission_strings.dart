/// 权限设置页面字符串常量
/// permission_settings_page.dart

class PermissionStrings {
  // ==================== 页面标题 ====================
  static const String pageTitle = '权限设置';

  // ==================== 定位权限 ====================
  static const String locationTitle = '定位权限开启';
  static const String locationDesc = '定位权限需要设置为本应用选择"始终允许"，才可以正常查看轨迹。';
  static const String quickSet = '快速设置';
  static const String locationGranted = '定位权限已全部开启';
  static const String locationNotGranted = '定位权限未完全开启';
  static const String backgroundLocation = '后台定位权限';
  static const String foregroundLocation = '前台定位权限';
  static const String alwaysLocation = '始终允许定位权限';
  static const String locationAlreadyGranted = '定位权限已开启，无需重复设置';

  // 定位权限帮助
  static const String locationHelpTitle = '定位权限设置';
  static const String locationHelpPath = '设置 → 应用 → 应用管理 → trace_path → 权限';
  static const String locationHelpStep1Name = '始终允许';
  static const String locationHelpStep1Desc = '允许应用在后台持续获取位置';
  static const String locationHelpStep2Name = '精确位置';
  static const String locationHelpStep2Desc = '获取精确 GPS 定位';
  static const String locationHelpStep3Name = '大致位置';
  static const String locationHelpStep3Desc = '通过网络获取大致位置';

  // ==================== 电池优化 ====================
  static const String batteryTitle = '电池优化白名单';
  static const String batteryDesc = '系统可能会为了省电，关闭后台的应用，避免出现轨迹异常，需要将本应用加入保护名单。';
  static const String batteryGranted = '已在电池白名单中';
  static const String batteryNotGranted = '未加入电池白名单';
  static const String batteryOptimization = '电池优化白名单';
  static const String batteryAlreadyGranted = '电池优化已在白名单中，无需重复设置';

  // 电池优化帮助
  static const String batteryHelpTitle = '电池优化白名单设置';
  static const String batteryHelpPath = '设置 → 电池 → 电池优化 → trace_path → 不优化';
  static const String batteryHelpStep1Name = '不优化';
  static const String batteryHelpStep1Desc = '允许应用在后台持续运行，不受省电策略影响';

  // ==================== 后台运行 ====================
  static const String backgroundTitle = '后台运行权限';
  static const String backgroundDesc = '将本应用加入后台权限名单，可以一定程度保护app在后台正常运行。';
  static const String backgroundGranted = '已在后台运行白名单中';
  static const String backgroundNotGranted = '未加入后台运行白名单';
  static const String backgroundPermission = '后台运行权限/自启动权限';

  // 后台运行帮助（各品牌不同，放BrandStrings中）

  // ==================== 通知权限 ====================
  static const String notificationTitle = '通知权限';
  static const String notificationDesc = '通知权限用于前台服务的常驻通知，显示定位状态。';
  static const String notificationGranted = '通知权限已开启';
  static const String notificationNotGranted = '通知权限未开启';
  static const String notificationPermission = '通知权限';
  static const String notificationAlreadyGranted = '通知权限已开启，无需重复设置';

  // 通知权限帮助
  static const String notificationHelpTitle = '通知权限设置';
  static const String notificationHelpPath = '设置 → 应用 → 应用管理 → trace_path → 通知';
  static const String notificationHelpStep1Name = '允许通知';
  static const String notificationHelpStep1Desc = '允许应用发送前台服务通知';
  static const String notificationHelpStep2Name = '悬浮通知';
  static const String notificationHelpStep2Desc = '允许通知在屏幕顶部显示';

  // ==================== 帮助对话框通用 ====================
  static const String helpDialogTitle = '后台运行权限设置';
  static const String missingPermissions = '缺少的权限：';
  static const String switchLabel = '需要开启的开关：';
  static const String operationPath = '操作路径';
  static const String requiredSwitches = '需要开启的开关';

  // ==================== 温馨提示 ====================
  static const String warningTitle = '温馨提示';
  static const String warningContent = '请勿开启【省电模式】，在省电模式下，可能会导致轨迹异常等问题，建议您关闭省电模式。';
}
