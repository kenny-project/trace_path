import 'package:flutter/material.dart';

/// 应用颜色定义 - 类似 Android colors.xml
/// 所有颜色统一在此定义，方便管理和修改

class AppColors {
  AppColors._();

  // ========== 品牌色 ==========

  /// 品牌蓝色 - 主色调
  /// 用于: 按钮、图标、边框、轨迹等
  static const Color primary = Color(0xFF2D7AF6);

  /// 品牌绿色 - 定位/成功状态
  /// 用于: 定位按钮、起点标记、成功提示等
  static const Color success = Color(0xFF4CAF50);

  /// 警告橙色 - 终点标记
  static const Color warning = Color(0xFFFF5722);

  /// 危险红色 - 删除按钮等
  static const Color danger = Color(0xFFF44336);

  // ========== 功能色 ==========

  /// VIP金色 - 标识
  static const Color vipGold = Color(0xFFFFD700);

  /// 高德蓝 - 版权标识
  static const Color amapBlue = Color(0xFF02C1E0);

  /// 定位绿 - 当前位置
  static const Color locationGreen = Color(0xFF00C853);

  /// 追踪绿 - 开始追踪
  static const Color trackingGreen = Color(0xFF00C853);

  // ========== 中性色 ==========

  /// 标题文字
  static const Color textPrimary = Color(0xFF333333);

  /// 正文文字
  static const Color textSecondary = Color(0xFF666666);

  /// 地址文字
  static const Color textAddress = Color(0xFF888888);

  /// 次要文字
  static const Color textHint = Color(0xFF999999);

  // ========== 背景色 ==========

  /// 分割线
  static const Color divider = Color(0xFFF0F0F0);

  /// 卡片背景
  static const Color cardBackground = Color(0xFFF5F5F5);

  /// 列表项背景
  static const Color listItemBackground = Color(0xFFF5F5F5);

  /// 浅灰背景
  static const Color backgroundLight = Color(0xFFFFF3E0);

  // ========== 补充颜色 ==========

  /// 浅黄背景（用于帮助信息等）
  static const Color lightYellow = Color(0xFFFFF3E0);

  /// 橙色（帮助信息等）
  static const Color orange = Color(0xFFE65100);

  /// 浅橙色边框
  static const Color lightOrangeBorder = Color(0xFFFFE0B2);

  /// 警告橙色
  static const Color warningOrange = Color(0xFFFF6B00);

  /// 浅红（用于警示）
  static const Color lightRed = Color(0xFFFF6B6B);

  /// 退出红
  static const Color logoutRed = Color(0xFFFF5E3A);

  /// 分割线2
  static const Color divider2 = Color(0xFFEEEEEE);

  /// 灰文字
  static const Color greyText = Color(0xFF999999);

  /// 深蓝渐变
  static const Color deepBlue1 = Color(0xFF1A1A66);

  /// 深蓝渐变2
  static const Color deepBlue2 = Color(0xFF3D2B8A);
}
