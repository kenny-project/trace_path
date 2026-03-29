# 字符串管理规范

## 概述

为解决硬编码字符串分散、难以维护、多语言支持困难等问题，采用集中式字符串管理方案。

## 文件结构

```
lib/
  constants/
    strings.dart              # 统一导出文件
    brand_strings.dart        # 品牌相关字符串（华为/荣耀/小米等）
    permission_strings.dart   # permission_settings_page.dart
    home_strings.dart        # home_page.dart / guard_page.dart
    location_strings.dart     # location_page.dart
    mine_strings.dart        # mine_page.dart
    widget_strings.dart       # 通用组件字符串
```

## 命名规范

### 文件命名
- `{功能/页面名}_strings.dart`
- 全部小写，单词用下划线分隔

### 类命名
- `xxxStrings` (PascalCase)
- 与文件名对应

### 变量命名
- `static const String {描述}` = '文字内容';
- 全部大写字母，单词用下划线分隔

## 使用规则

### 1. 导入方式

```dart
// 方式一：从 constants/strings.dart 导入（推荐）
import '../../../../constants/strings.dart';
import '../../../../constants/permission_strings.dart' as ps;

// 方式二：直接导入
import '../../../../constants/permission_strings.dart';
```

### 2. 使用方式

```dart
// 使用别名避免类名冲突
Text(ps.PermissionStrings.pageTitle)

// 直接使用
Text(WidgetStrings.cancel)
```

### 3. 品牌字符串访问

```dart
// 获取帮助信息
final helpInfo = BrandStrings.getHelpInfo(brand);
print(helpInfo['brandName']);
print(helpInfo['path']);

// 获取开关列表
final switches = helpInfo['switches'] as List<Map<String, String>>;
```

## 后续新增字符串

1. 找到对应页面的字符串文件（如有新页面则新建 `{page}_strings.dart`）
2. 在类中添加对应的 const 字符串
3. 更新 `strings.dart` 的导出
4. 在业务代码中通过 `StringsClass.stringName` 访问

## 禁止事项

- ❌ 禁止在业务代码中硬编码中文字符串
- ❌ 禁止在不同文件中定义相同的字符串
- ❌ 禁止使用非 const 的字符串

## 多语言支持（未来扩展）

如需支持多语言，可将 `const String` 改为函数：

```dart
// 未来扩展方案
String appName(BuildContext context) {
  return Localizations.of<AppLocalizations>(context, AppLocalizations).appName;
}
```

## 当前支持的页面

| 页面文件 | 字符串文件 |
|---------|-----------|
| permission_settings_page.dart | permission_strings.dart |
| home_page.dart | home_strings.dart |
| guard_page.dart | home_strings.dart |
| location_page.dart | location_strings.dart |
| mine_page.dart | mine_strings.dart |
| location_settings_dialog.dart | widget_strings.dart |
| (品牌相关) | brand_strings.dart |
