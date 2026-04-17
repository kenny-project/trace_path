# 定位模块问题修复报告

> 生成日期: 2026/04/17
> 问题平台: Android (Honor 设备)
> 最新更新: 添加 LocationRequest API 兼容性问题修复

---

## 一、用户反馈的问题

1. **有时定不上位**
2. **有时定上位了但不记录数据**
3. **有时定位界面的位置不更新**
4. **Google Play 服务检测到后台高耗电**
5. **通知栏时间更新但定位页面不更新**

---

## 二、排查发现的问题

### 问题 1: EventChannel 重复监听导致事件丢失 🔴 严重

**位置**: `BackgroundLocationService.init()` 和 `start()`

**问题描述**:
- `init()` 在第 91 行调用 `_eventHandler.startListening()`
- `init()` 在第 96 行调用 `start()`（没有 `await`）
- `start()` 在第 196 行又调用 `_eventHandler.startListening()`

`startListening()` 内部会先取消旧的 subscription 再创建新的。两次调用导致：
- 第一个 subscription 刚创建就被取消
- 存在短暂的监听窗口期，可能丢失事件

**修复方案**:
1. 添加 `_isInitialized` 标志防止重复初始化
2. `start()` 中不再调用 `startListening()`，避免重复取消 subscription
3. `init()` 中 `start()` 改为 `await start()`

**修改文件**:
- `lib/com/kenny/trace_path/services/background_location_service.dart`

---

### 问题 2: powerSaving 参数被完全忽略 🔴 严重

**位置**: `LocationForegroundService.kt`

**问题描述**:
- 第 225 行强制将 `currentPriority` 设为 `PRIORITY_HIGH_ACCURACY`
- 无论 `powerSaving` 设置为 `true` 还是 `false`，都使用高精度 GPS
- 导致省电模式失效，耗电严重

**修复方案**:
1. 移除强制覆盖代码
2. `startTracking()` 中根据 `powerSaving` 正确设置 `currentPriority`:
   - 省电模式: `PRIORITY_BALANCED_POWER_ACCURACY`
   - 精准模式: `PRIORITY_HIGH_ACCURACY`

**修改文件**:
- `android/app/src/main/kotlin/com/kenny/trace_path/LocationForegroundService.kt`

---

### 问题 3: accuracy 过滤条件过于严格 🔴 严重

**位置**: `LocationForegroundService.kt` `handleLocationResult()` 方法

**问题描述**:
| 过滤条件 | 原值 | 问题 |
|---------|------|------|
| 基础清洗 | accuracy > 200m 丢弃 | 城市峡谷环境 GPS 精度可能 50-200m |
| GPS 精度 | accuracy > 100m 丢弃 | 信号差环境 GPS 精度 100-200m |
| 网络定位 | accuracy > 100m 丢弃 | 城市网络定位通常 100-300m |
| 原地抖动 | timeDelta < 1.5s && distanceDelta < 2m | 静止时被误判为抖动 |

**修复方案**:
| 过滤条件 | 新值 | 说明 |
|---------|------|------|
| 基础清洗 | accuracy > 500m | 极端情况才丢弃 |
| GPS 精度 | accuracy > 200m | 信号差环境也能接受 |
| 网络定位 | accuracy > 300m | 城市网络定位通常范围 |
| 原地抖动 | timeDelta < 2s && distanceDelta < 3m | 稍微放宽条件 |

**修改文件**:
- `android/app/src/main/kotlin/com/kenny/trace_path/LocationForegroundService.kt`

---

### 问题 4: BackgroundLocationService 初始化依赖特定页面 🟡 中等

**位置**: `MyApp` 和 `MinePage`

**问题描述**:
- `BackgroundLocationService.init()` 只在 `MinePage.initState()` 中调用
- 如果用户直接进入 `LocationPage`，服务不会被初始化
- 导致 `_locationProvider` 为 `null`，定位功能失效

**修复方案**:
- 将 `BackgroundLocationService().init()` 移到 `MyApp` 应用启动时执行
- 添加 `_isInitialized` 标志防止重复初始化
- 即使 `MinePage` 仍会调用 init，也不会有问题

**修改文件**:
- `lib/com/kenny/trace_path/app/MyApp.dart`

---

### 问题 5: LocationRequest.Builder API 在 Honor 设备上不稳定 🔴 严重

**位置**: `LocationForegroundService.kt` `requestLocationUpdates()` 方法

**问题描述**:
- 使用 `LocationRequest.Builder` API 注册定位请求
- Honor 设备上系统强制将请求转换为 `Request[@0 HIGH_ACCURACY]`
- 导致 GPS 以最快速度持续运行，耗电极快
- 系统检测到异常耗电后自动停止定位服务
- 表现为：只收到 1-2 次定位后就不再有新更新

**问题现象**:
```
系统日志: Request[@0 HIGH_ACCURACY]  (实际应该是 @+60s0ms BALANCED)
我们的代码: registered with priority=102, interval=60000ms
```

**根因分析**:
- `LocationRequest.Builder` 是 Google 推荐的现代 API
- 但在部分 Honor/华为设备上，FusedLocationProviderClient 内部会忽略 Builder 的参数
- 系统强制使用 `HIGH_ACCURACY` 且 `interval=0`（最快速度）
- 导致 GPS 持续工作，快速耗电，被系统 kill

**修复方案**:
- 改用旧的 `@Suppress("DEPRECATION") LocationRequest` API
- 旧 API 在 Honor 设备上更稳定，能正确使用设置的参数

```kotlin
@Suppress("DEPRECATION")
val locationRequest = LocationRequest()
locationRequest.priority = currentPriority
locationRequest.interval = actualInterval
locationRequest.fastestInterval = 10000

fusedLocationClient.requestLocationUpdates(
    locationRequest,
    locationCallback!!,
    Looper.getMainLooper()
)
```

**修改文件**:
- `android/app/src/main/kotlin/com/kenny/trace_path/LocationForegroundService.kt`

---

### 问题 6: 自适应省电策略导致重复注册 🔴 严重

**位置**: `LocationForegroundService.kt` `handleLocationResult()` 方法

**问题描述**:
- `evaluateAndSwitchPriority()` 和 `reRegisterLocationUpdates()` 在 `onLocationResult` 回调内直接调用
- 导致在回调执行期间修改 callback，可能引起 FusedLocationProviderClient 内部状态冲突
- 表现为：定位更新突然中断

**修复方案**:
- 移除 `runOnMainThread` 包装（回调本身在主线程）
- 简化自适应逻辑，避免频繁重新注册
- 速度自适应功能暂时禁用（待优化）

**修改文件**:
- `android/app/src/main/kotlin/com/kenny/trace_path/LocationForegroundService.kt`

---

### 问题 7: 通知栏时间更新但定位页面不更新 🟡 中等

**位置**: Flutter 侧 `LocationPage` 和 `BackgroundLocationService`

**问题描述**:
- 通知栏时间每次都更新
- 但定位页面的时间戳不是每次都更新
- 位置数据已正确发送到 Flutter，但 UI 没有刷新

**问题分析**:
1. 通知栏通过 `updateNotification()` 每次都刷新
2. Flutter 侧通过 `EventChannel` 接收位置
3. `LocationPage` 订阅了定位更新，但 `lastUpdateTime` 可能没有每次都更新

**排查要点**:
- 检查 `LocationPage._onLocationEvent` 是否每次都被调用
- 检查 `setState()` 是否每次都触发
- 检查 `_friendService.updateFriendLocation` 的调用
- 检查是否有条件导致静默忽略更新

**修改文件**:
- `lib/com/kenny/trace_path/ui/home/pages/location_page.dart`

---

## 三、问题根因与用户反馈对应关系

| 用户反馈 | 根本原因 |
|---------|---------|
| 有时定不上位 | 1. powerSaving 被忽略，强制 GPS 高精度<br>2. accuracy > 200m/100m 过滤太严格<br>3. 服务未初始化（进入 LocationPage 前未访问 MinePage） |
| 定上位了但不记录数据 | 1. 数据被 Kotlin 过滤掉（accuracy 过滤）<br>2. EventChannel 监听丢失（重复订阅） |
| 定位界面位置不更新 | 1. 服务未初始化<br>2. EventChannel 重复监听导致事件丢失<br>3. 原地抖动过滤过于激进<br>4. LocationRequest.Builder 不稳定 |
| Google Play 高耗电 | LocationRequest.Builder 被系统强制转换为 HIGH_ACCURACY，GPS 持续运行 |
| 通知栏更新但页面不更新 | Flutter 侧接收或处理逻辑问题 |

---

## 四、修改文件汇总

| 文件 | 操作 | 说明 |
|------|------|------|
| `services/background_location_service.dart` | 修改 | 修复 EventChannel 重复监听 |
| `services/location_event_handler.dart` | 无变更 | - |
| `app/MyApp.dart` | 修改 | 应用启动时初始化定位服务 |
| `LocationForegroundService.kt` | 修改 | 修复 powerSaving 参数、accuracy 过滤、LocationRequest API 兼容性 |
| `ui/home/pages/location_page.dart` | 待查 | 通知栏更新但页面不更新问题 |
| `LocationPlugin.kt` | 无变更 | - |

---

## 五、后续建议

### 高优先级
1. **测试 Honor 设备兼容性**
   - 在 Honor/华为设备上使用旧版 LocationRequest API
   - 验证不同设备上的定位稳定性

2. **优化自适应省电策略**
   - 速度自适应定位间隔功能暂时禁用
   - 重新设计以避免频繁重新注册

### 中优先级
3. **添加定位状态监控**
   - 在 UI 层显示当前定位状态（GPS/网络定位、信号强度等）
   - 方便用户排查问题

4. **添加重连机制**
   - EventChannel 断开后自动重连
   - 避免 Flutter 重连后丢失事件

5. **优化省电模式体验**
   - 当用户选择省电模式时，降低定位频率
   - 使用 `PRIORITY_BALANCED_POWER_ACCURACY`

---

## 六、Honor/Huawei 设备 GPS 节流问题（待解决）

**问题等级**: 🔴 严重（系统级别限制）

**问题描述**:
即使使用了旧版 `LocationRequest` API 且应用已在电池白名单中，Honor 设备的系统级节流仍然影响定位功能：

1. **FusedLocationProviderClient 回调被节流**
   - GPS 硬件持续收到位置更新（GnssCallbackAidl 正常工作）
   - 但 FusedLocationProviderClient 的回调被系统节流
   - 表现为：长时间没有新位置推送

2. **Handler 定时器被节流**
   - 添加的 60 秒保活机制（Handler + getLastLocation）
   - 实际运行时 60 秒定时器变成 ~180 秒才触发
   - 说明 Honor 系统对 Handler 也有深层节流

**问题现象（Logcat）**:
```
# GPS 硬件在报告位置
GnssCallbackAidl: onGnssLocation result: lat=xx.x, lng=xx.x

# 但 FLP 回调没有触发（被节流）
# ... 长时间无日志 ...

# 保活定时器也延迟了
[保活] 触发延迟: actualDelay=178234ms (expected 60000ms)
```

**根因分析**:
- Honor/Huawei 的系统级电源管理会在后台限制 GPS 活动
- 即使应用在白名单中，系统仍会节流 GPS 回调和 Handler
- 这是设备制造商的系统策略，无法通过代码绕过

**已尝试的方案**:
1. ✅ 改用旧版 LocationRequest API（部分有效，但仍有节流）
2. ✅ 添加 Handler + getLastLocation 保活机制（Handler 本身也被节流）
3. ❌ 无法通过代码请求加入更高级别的白名单

**用户可执行的解决方案**:
需要在设备设置中手动配置：
1. **设置 → 电池 → 应用启动管理**
   - 找到 TracePath
   - 关闭"自动管理"，手动开启所有开关

2. **设置 → 电池 → 更多电池设置**
   - 关闭"限制后台进程"
   - 确保"耗电异常优化"未激活

3. **设置 → 应用 → TracePath → 电池**
   - 选择"无限制"（允许后台活动）

4. **部分 Honor 设备还需要**:
   - **设置 → 电池 → 右上角 ⚙ → 关闭"智能限制"**
   - **手机管家 → 应用启动管理 → 找到 TracePath → 手动管理**

**如仍有问题**:
1. 检查"手机管家"是否有独立的电源管理
2. 部分设备需要在"开发者选项"中关闭"后台进程限制"
3. 如果系统更新后问题加剧，可能需要恢复出厂设置（极端情况）

**后续优化方向**:
- 考虑添加"疑似被节流"时的用户提示
- 记录每次 getLastLocation 的成功率，辅助诊断
- 评估是否需要使用更耗电但更可靠的备选方案

---

## 七、测试验证清单

- [ ] 精准模式（powerSaving=false）下 GPS 定位正常
- [ ] 省电模式（powerSaving=true）下定位正常且耗电降低
- [ ] 城市峡谷环境（GPS 信号差）能正常定位
- [ ] 室内环境（无 GPS）能通过网络定位
- [ ] 静止时位置不会丢失（原地抖动过滤生效）
- [ ] 移动时轨迹连续（无跳变）
- [ ] 直接进入 LocationPage 能正常定位
- [ ] 定位数据正确保存到本地
- [ ] Honor 设备上定位信号稳定（60秒间隔）
- [ ] Google Play 不再报高耗电警告
- [ ] Honor 设备电池白名单配置正确后定位稳定
