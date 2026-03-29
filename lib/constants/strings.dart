/// 字符串常量统一导出
///
/// 使用规则：
/// 1. 按文件名分类，每个页面/组件对应一个文件
/// 2. 品牌相关字符串统一放在 brand_strings.dart
/// 3. 所有字符串使用 const，保证全局唯一
/// 4. 命名规范：{页面名}Strings 或 {功能}Strings
///
/// 后续新增字符串：
/// - 找到对应页面的字符串文件（如有新页面则新建）
/// - 品牌相关的放 brand_strings.dart
/// - 不要在业务代码中硬编码中文字符串

export 'brand_strings.dart';
export 'permission_strings.dart';
export 'home_strings.dart';
export 'location_strings.dart';
export 'mine_strings.dart';
export 'widget_strings.dart';
