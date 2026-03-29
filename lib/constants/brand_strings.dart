/// 品牌相关字符串常量
/// 按手机品牌分类存放各品牌的设置路径和开关项描述

class BrandStrings {
  // ==================== 通用 ====================
  static const String unknownBrand = '您的手机';

  // ==================== 荣耀 ====================
  static const String honorBrandName = '荣耀';

  // 后台运行权限
  static const String honorAutoStartPath = '设置 → 电池 → 应用启动管理（或 应用启动）';
  static const List<Map<String, String>> honorAutoStartSwitches = [
    {'name': '允许自启动', 'desc': '开机自动启动应用'},
    {'name': '允许后台活动', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String honorBatteryPath = '设置 → 电池 → 电池优化 → trace_path → 不优化';
  static const List<Map<String, String>> honorBatterySwitches = [
    {'name': '不优化', 'desc': '允许应用在后台持续运行，不受省电策略影响'},
  ];

  // ==================== 华为 ====================
  static const String huaweiBrandName = '华为';

  // 后台运行权限
  static const String huaweiAutoStartPath = '设置 → 电池 → 应用启动管理（或 应用启动）';
  static const List<Map<String, String>> huaweiAutoStartSwitches = [
    {'name': '允许自启动', 'desc': '开机自动启动应用'},
    {'name': '允许后台活动', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String huaweiBatteryPath = '设置 → 电池 → 电池优化 → trace_path → 不优化';
  static const List<Map<String, String>> huaweiBatterySwitches = [
    {'name': '不优化', 'desc': '允许应用在后台持续运行，不受省电策略影响'},
  ];

  // ==================== 小米 ====================
  static const String xiaomiBrandName = '小米';

  // 后台运行权限
  static const String xiaomiAutoStartPath = '设置 → 应用设置 → 应用管理 → trace_path → 启动管理';
  static const List<Map<String, String>> xiaomiAutoStartSwitches = [
    {'name': '自启动', 'desc': '允许应用开机自动启动'},
    {'name': '后台唤醒', 'desc': '允许应用被其他应用唤醒'},
    {'name': '省电策略', 'desc': '设为“无限制”'},
  ];

  // 电池优化
  static const String xiaomiBatteryPath = '设置 → 电池 → 应用配置 → trace_path → 无限制';
  static const List<Map<String, String>> xiaomiBatterySwitches = [
    {'name': '无限制', 'desc': '允许应用在后台持续运行，关闭省电限制'},
  ];

  // ==================== OPPO ====================
  static const String oppoBrandName = 'OPPO';

  // 后台运行权限
  static const String oppoAutoStartPath = '设置 → 电池 → 耗电保护 → trace_path → 允许后台活动';
  static const List<Map<String, String>> oppoAutoStartSwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String oppoBatteryPath = '设置 → 电池 → 耗电保护 → trace_path → 允许后台运行';
  static const List<Map<String, String>> oppoBatterySwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
  ];

  // ==================== vivo ====================
  static const String vivoBrandName = 'vivo';

  // 后台运行权限
  static const String vivoAutoStartPath = '设置 → 电池 → 后台耗电管理 → trace_path → 允许后台运行';
  static const List<Map<String, String>> vivoAutoStartSwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String vivoBatteryPath = '设置 → 电池 → 后台耗电管理 → trace_path → 允许后台运行';
  static const List<Map<String, String>> vivoBatterySwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
  ];

  // ==================== 三星 ====================
  static const String samsungBrandName = '三星';

  // 后台运行权限
  static const String samsungAutoStartPath = '设置 → 电池 → 后台使用情况 → trace_path → 允许后台活动';
  static const List<Map<String, String>> samsungAutoStartSwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String samsungBatteryPath = '设置 → 电池 → 后台使用情况 → trace_path → 不优化';
  static const List<Map<String, String>> samsungBatterySwitches = [
    {'name': '不优化', 'desc': '允许应用在后台持续运行'},
  ];

  // ==================== 一加 ====================
  static const String oneplusBrandName = '一加';

  // 后台运行权限
  static const String oneplusAutoStartPath = '设置 → 电池 → 电池优化 → trace_path → 不优化';
  static const List<Map<String, String>> oneplusAutoStartSwitches = [
    {'name': '允许后台运行', 'desc': '允许应用在后台持续运行'},
    {'name': '允许关联启动', 'desc': '允许应用唤醒其他应用'},
  ];

  // 电池优化
  static const String oneplusBatteryPath = '设置 → 电池 → 电池优化 → trace_path → 不优化';
  static const List<Map<String, String>> oneplusBatterySwitches = [
    {'name': '不优化', 'desc': '允许应用在后台持续运行，不受省电策略影响'},
  ];

  /// 根据品牌获取后台运行权限帮助信息
  static Map<String, dynamic> getAutoStartHelpInfo(String brand) {
    switch (brand) {
      case 'honor':
        return {
          'brandName': honorBrandName,
          'path': honorAutoStartPath,
          'switches': honorAutoStartSwitches,
        };
      case 'huawei':
        return {
          'brandName': huaweiBrandName,
          'path': huaweiAutoStartPath,
          'switches': huaweiAutoStartSwitches,
        };
      case 'xiaomi':
        return {
          'brandName': xiaomiBrandName,
          'path': xiaomiAutoStartPath,
          'switches': xiaomiAutoStartSwitches,
        };
      case 'oppo':
        return {
          'brandName': oppoBrandName,
          'path': oppoAutoStartPath,
          'switches': oppoAutoStartSwitches,
        };
      case 'vivo':
        return {
          'brandName': vivoBrandName,
          'path': vivoAutoStartPath,
          'switches': vivoAutoStartSwitches,
        };
      case 'samsung':
        return {
          'brandName': samsungBrandName,
          'path': samsungAutoStartPath,
          'switches': samsungAutoStartSwitches,
        };
      case 'oneplus':
        return {
          'brandName': oneplusBrandName,
          'path': oneplusAutoStartPath,
          'switches': oneplusAutoStartSwitches,
        };
      default:
        return {
          'brandName': unknownBrand,
          'path': '设置 → 应用 → 应用启动管理',
          'switches': huaweiAutoStartSwitches,
        };
    }
  }

  /// 根据品牌获取电池优化帮助信息
  static Map<String, dynamic> getBatteryHelpInfo(String brand) {
    switch (brand) {
      case 'honor':
        return {
          'brandName': honorBrandName,
          'path': honorBatteryPath,
          'switches': honorBatterySwitches,
        };
      case 'huawei':
        return {
          'brandName': huaweiBrandName,
          'path': huaweiBatteryPath,
          'switches': huaweiBatterySwitches,
        };
      case 'xiaomi':
        return {
          'brandName': xiaomiBrandName,
          'path': xiaomiBatteryPath,
          'switches': xiaomiBatterySwitches,
        };
      case 'oppo':
        return {
          'brandName': oppoBrandName,
          'path': oppoBatteryPath,
          'switches': oppoBatterySwitches,
        };
      case 'vivo':
        return {
          'brandName': vivoBrandName,
          'path': vivoBatteryPath,
          'switches': vivoBatterySwitches,
        };
      case 'samsung':
        return {
          'brandName': samsungBrandName,
          'path': samsungBatteryPath,
          'switches': samsungBatterySwitches,
        };
      case 'oneplus':
        return {
          'brandName': oneplusBrandName,
          'path': oneplusBatteryPath,
          'switches': oneplusBatterySwitches,
        };
      default:
        return {
          'brandName': unknownBrand,
          'path': '设置 → 电池 → 电池优化',
          'switches': huaweiBatterySwitches,
        };
    }
  }
}
