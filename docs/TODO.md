# TODO - 待处理事项

## 权限设置页面

### 1. 荣耀电池优化跳转路径错误
- **问题**：电池优化白名单的快速设置跳转路径不正确
- **当前**：使用 `com.hihonor.systemmanager` 的后台管理页面
- **期望**：需要找到荣耀手机电池优化的正确设置路径
- **状态**：待处理
- **优先级**：中
- **备注**：需要确认荣耀手机上 `设置 → 电池 → 电池优化` 对应的 Intent 和 Activity

### 2. 各品牌电池优化跳转路径验证
- **问题**：各品牌的电池优化跳转intent未经验证
- **当前品牌配置**：
  - 华为：com.android.settings.BatterySettings
  - 荣耀：com.android.settings.BatterySettings（待确认）
  - 小米：com.miui.powerkeeper.ui.HiddenAppsConfigActivity
  - vivo：com.vivo.permissionmanager（与后台运行共用）
  - OPPO：com.coloros.oppoguardelf
  - 三星：com.samsung.android.lool
  - 一加：com.oneplus.security
- **状态**：待处理
- **优先级**：中
