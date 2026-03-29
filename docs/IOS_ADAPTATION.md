# iOS 适配文档

> 创建时间: 2026-03-29
> 更新时间: 2026-03-29

## 概述

本文档记录 Android 版本功能向 iOS 移植的过程、已实现功能、差异说明及待处理事项。

---

## 一、已实现功能

### 1.1 iOS 后台定位服务

**文件**: `ios/Runner/LocationManager.swift`

**实现方式**: CoreLocation Framework

| 功能 | 状态 | 说明 |
|-----|------|------|
| 获取当前位置 | ✅ | CLLocationManager.requestLocation() |
| 启动后台定位 | ✅ | startUpdatingLocation() |
| 停止后台定位 | ✅ | stopUpdatingLocation() |
| 配置更新(热更新) | ✅ | updateConfig() |
| 服务运行状态 | ✅ | isTracking 标志 |
| 文件目录获取 | ✅ | NSDocumentDirectory |

**MethodChannel 名称**: `com.kenny.trace_path/location_service`

**支持的 Method**:
- `getCurrentPosition` - 获取当前位置
- `start` - 启动后台定位
- `stop` - 停止后台定位
- `updateConfig` - 更新配置（间隔、省电模式）
- `isRunning` - 检查服务运行状态
- `getFilesDir` - 获取文档目录路径

### 1.2 AppDelegate 注册

**文件**: `ios/Runner/AppDelegate.swift`

已添加 LocationManager 注册代码。

### 1.3 Info.plist 配置

**文件**: `ios/Runner/Info.plist`

已配置权限描述和使用场景：

| Key | 状态 | 说明 |
|-----|------|------|
| NSLocationWhenInUseUsageDescription | ✅ | 前台定位权限 |
| NSLocationAlwaysAndWhenInUseUsageDescription | ✅ | 后台定位权限 |
| UIBackgroundModes: location | ✅ | 后台位置更新 |

### 1.4 权限设置页面适配

**文件**: `lib/.../permission_settings_page.dart`

| 权限卡片 | Android | iOS |
|---------|---------|-----|
| 定位权限 | ✅ 显示 | ✅ 显示 |
| 电池优化 | ✅ 显示 | ❌ 隐藏（iOS系统管理） |
| 自启动/后台运行 | ✅ 显示 | ❌ 隐藏（iOS限制） |
| 通知权限 | ✅ 显示 | ✅ 显示 |

**平台检测代码**:
```dart
if (Platform.isAndroid) ...[
  // 电池优化卡片
  // 自启动卡片
]
```

### 1.5 通用功能（无需修改）

以下功能使用 Flutter 插件或跨平台代码，无需修改：

| 功能 | 实现方式 |
|-----|---------|
| 定位页面地图 | flutter_map + 高德瓦片 |
| 轨迹列表 | 纯 Dart 代码 |
| 轨迹地图 | flutter_map |
| 坐标转换 | WGS84→GCJ02 Dart实现 |
| 轨迹存储 | CSV文件，Dart I/O |

---

## 二、无法实现的功能

由于 iOS 系统限制，以下功能无法实现：

### 2.1 电池优化设置

| 项目 | 说明 |
|-----|------|
| **Android功能** | 跳转电池优化设置页面 |
| **iOS限制** | iOS不提供应用级别的电池优化API |
| **替代方案** | 用户在系统设置中统一管理 |

### 2.2 自启动/开机启动

| 项目 | 说明 |
|-----|------|
| **Android功能** | 引导用户开启自启动权限 |
| **iOS限制** | iOS不允许应用开机自启动 |
| **替代方案** | iOS应用商店版本可在后台持续运行（需用户授权） |

### 2.3 应用间跳转

| 项目 | 说明 |
|-----|------|
| **Android功能** | 通过 Intent 跳转到各种系统设置页 |
| **iOS限制** | iOS的 URL Scheme 和设置跳转非常受限 |
| **替代方案** | 仅能打开系统设置的"应用详情"页 |

---

## 三、iOS 开发环境要求

### 3.1 必要条件

| 项目 | 要求 |
|-----|------|
| **硬件** | Mac 电脑 |
| **IDE** | Xcode 15+ |
| **账号** | Apple Developer 账号 |
| **系统** | macOS 13+ |

### 3.2 待配置项

| 项目 | 当前值 | 需修改为 |
|-----|-------|---------|
| Bundle Identifier | com.example.trace_path | com.kenny.trace_path |
| 包名 | trace_path | trace_path |
| Display Name | Trace Path | 待定（建议：行迹/随行/足迹） |
| Code Signing | 未配置 | 需要配置 |

### 3.3 获取 iOS 开发资源

1. 访问 [Apple Developer Portal](https://developer.apple.com/)
2. 创建 App ID: `com.kenny.trace_path`
3. 创建 Development Certificate
4. 创建 Provisioning Profile
5. 在 Xcode 中配置 Signing & Capabilities

---

## 四、测试清单

### 4.1 功能测试

- [ ] 首次安装，定位权限请求弹窗
- [ ] 前台定位，获取位置准确
- [ ] 后台定位，持续更新位置
- [ ] 轨迹记录，CSV文件正确保存
- [ ] 轨迹列表，正确读取和显示
- [ ] 轨迹地图，正确显示路线
- [ ] 删除轨迹功能

### 4.2 权限测试

- [ ] 定位权限"仅使用时" vs "始终"
- [ ] 后台定位刷新频率
- [ ] 应用被杀掉后，是否还能定位（需配置Background Modes）

### 4.3 兼容性测试

- [ ] iPhone SE (小屏)
- [ ] iPhone 14/15/16 (常规屏)
- [ ] iPhone Pro Max (大屏)
- [ ] iOS 16 / iOS 17 / iOS 18

---

## 五、后续工作

### 5.1 高优先级

1. **Mac 环境配置**
   - 安装 Xcode
   - 配置 Apple Developer 账号
   - 创建 App ID 和证书

2. **Bundle ID 修改**
   - iOS 项目中配置 `com.kenny.trace_path`

3. **真机测试**
   - 定位功能验证
   - 后台运行验证

### 5.2 中优先级

1. **推送通知（APNs）**
   - 离线推送支持
   - 需要配置 APNs 证书

2. **icloud 同步**
   - 轨迹数据云端备份
   - 多设备同步

### 5.3 低优先级

1. **Widget 小组件**
   - iOS Widget 扩展
   - 快速查看位置

2. **Shortcuts 支持**
   - Siri 快捷指令集成

---

## 六、相关文件清单

### 6.1 iOS 原生代码（新建）

| 文件 | 说明 |
|-----|------|
| `ios/Runner/LocationManager.swift` | CoreLocation 后台定位实现 |
| `ios/Runner/AppDelegate.swift` | 已修改，注册 LocationManager |

### 6.2 Flutter 代码（修改）

| 文件 | 修改内容 |
|-----|---------|
| `lib/.../permission_settings_page.dart` | 添加 Platform.isAndroid 判断 |
| 其他页面 | 无需修改，跨平台兼容 |

### 6.3 iOS 配置（已有）

| 文件 | 说明 |
|-----|------|
| `ios/Runner/Info.plist` | 已有位置权限和后台模式配置 |

---

## 七、联系信息

如有 iOS 开发环境配置问题，请联系：
- 开发者: wmh
- 备注: 需要 Mac 电脑和 Apple Developer 账号
