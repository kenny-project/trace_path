# 定位服务 Flutter 重连问题排查报告

**日期**：2026-04-04
**问题**：Flutter 进程被杀后重新打开，定位消息无法到达 Flutter，地图停止实时更新
**状态**：✅ 已解决

---

## 问题现象

1. Flutter 存活时，定位消息正常推送到地图
2. Flutter 进程被杀（从最近任务划掉），Android ForegroundService 继续运行
3. Flutter 重连后，地图不再实时更新位置
4. 轨迹记录也在 Flutter 重连后中断

---

## 排查过程

### 第一阶段：MethodChannel 不通

**发现**：Flutter 报 `MissingPluginException(No implementation found for method startLocationService)`

**原因**：
- Dart 侧调用 `startLocationService` / `stopLocationService`
- Java MainActivity 接收的是 `start` / `stop`（旧方法名）
- 同时存在 Java `LocationForegroundService.java` 和 Kotlin `LocationForegroundService.kt` 重复类声明

**修复**：
1. 删除 `LocationForegroundService.java`，保留 Kotlin 版本
2. `LocationPlugin.kt` 已实现新旧方法名兼容（同时支持 `startLocationService` 和 `start`）
3. 发现根本问题：MainActivity 和 LocationPlugin 都创建了同名 `location_service` MethodChannel，后注册的把先注册的覆盖了
4. 重构 MainActivity：移除 `location_service` MethodChannel 创建，统一由 LocationPlugin 处理

### 第二阶段：EventChannel 重连后不通

**发现**：Flutter 报 `FlutterJNI: Tried to send a platform message to Flutter, but FlutterJNI was detached`

**原因链**：
1. Flutter 死亡时，`EventChannel.StreamHandler.onCancel()` 被调用 → `LocationPluginBinder.eventSink = null`
2. Kotlin `sendLocationToFlutter()` 检查 `eventSink ?: LocationPluginBinder.getEventSink()` → 返回 null → 位置被静默丢弃
3. Flutter 重连后，`LocationPlugin.registerWith()` 被调用 → `onListen()` → `LocationPluginBinder.eventSink` 被设置
4. 但 `ACTION_NOTIFY_SINK_READY` 通知 Service 时，`isTracking=false`（服务被系统杀后重建，状态丢失）
5. `lastLocation=null`，无法立即发送当前位置，只能等下一个 interval

**修复**：
1. Flutter `init()` 里调用 `_listenToLocationEvents()` 注册 EventChannel 监听（之前只在 `start()` 里注册）
2. `_requestAndBroadcastCurrentLocation()` 主动拉一次当前位置（不依赖 Kotlin push）
3. `ACTION_NOTIFY_SINK_READY` 发现 `isTracking=false` 时，自动调用 `startTracking()` 重新启动追踪

### 第三阶段：定位消息仍不更新

**发现**：EventChannel 注册了，`sink=true`，但 `_handleLocationEvent` 始终没被调用

**原因**：
- Kotlin locationThread 在 `sendLocationToFlutter()` 时用的是 `LocationPluginBinder.getEventSink()`
- Flutter Dart 侧 `receiveBroadcastStream().listen()` 接收消息
- 两者之间的连接在 Service 被系统杀后重建时出现问题

**根因**：`startTracking()` 中的 guard 逻辑问题：
```kotlin
if (isTracking.get() && locationThread?.isAlive == true) {
    Log.w(TAG, "Already tracking, ignore")
    return
}
```
Flutter 被杀时 `isTracking=true`，线程被 interrupt 但 Service 重建后线程是新的，`isAlive` 检查正确，但真正问题在于 Service 被杀重建后追踪没有自动恢复。

**最终修复**：在 `ACTION_NOTIFY_SINK_READY` 中，当 `isTracking=false` 时自动调用 `startTracking()` 重新启动追踪循环。

---

## 定位服务架构（重构后）

### 数据流

```
[Flutter 存活时]
Kotlin Service (locationThread 循环)
  → requestSingleLocation()
  → sendLocationToFlutter() → EventChannel → Flutter
  → saveLocationToFile() → CSV 文件（兜底）

[Flutter 被杀期间]
Kotlin Service (locationThread 继续循环)
  → requestSingleLocation()
  → sendLocationToFlutter() → EventChannel 断开，位置丢弃
  → saveLocationToFile() → CSV 文件（持续记录）

[Flutter 重连后]
1. LocationPlugin.registerWith() → onListen() → LocationPluginBinder.eventSink 更新
2. ACTION_NOTIFY_SINK_READY → Service 发现 isTracking=false → 自动 startTracking()
3. Flutter init() → _recoverKotlinTrackData() → 从 CSV 恢复历史轨迹
4. Flutter init() → _requestAndBroadcastCurrentLocation() → 主动拉一次当前位置
5. Flutter init() → _listenToLocationEvents() → 注册 EventChannel 监听
6. 后续 Kotlin 推送 → EventChannel → Flutter → 实时更新
```

### 关键文件

| 文件 | 作用 |
|------|------|
| `LocationForegroundService.kt` | Android ForegroundService，定位循环，EventChannel 发送端 |
| `LocationPlugin.kt` | MethodChannel + EventChannel Handler，Flutter 和 Service 之间的桥梁 |
| `MainActivity.java` | 统一管理 `location_service` MethodChannel，分发到 LocationPlugin |
| `LocationPluginBinder` | 静态对象，在 Plugin 和 Service 之间传递 EventSink |
| `background_location_service.dart` | Flutter 定位服务单例，EventChannel 接收端，轨迹记录 |

---

## 踩的坑

### 1. Java + Kotlin 重复类
同时存在 `.java` 和 `.kt` 的同名类，编译时报 `Redeclaration`。

### 2. MethodChannel 覆盖
`MainActivity` 和 `LocationPlugin` 都创建了同名 `location_service` MethodChannel，后注册的覆盖了先注册的，导致 LocationPlugin 的 handler 永远不生效。
**教训**：同一个 Channel 只允许一个 Handler，必须统一管理。

### 3. EventChannel 的 sink 是静态单例
`LocationPluginBinder` 用静态对象存 `EventSink`，Flutter 被杀时 `onCancel()` 会清空。但 Kotlin Service 持有的是同一个静态引用，所以 Service 端 sink 也会变 null。
**教训**：EventChannel 的 sink 连接依赖 Flutter 进程存活，Flutter 死后必须重新建立。

### 4. `onListen` 时机问题
Flutter Dart 侧 `receiveBroadcastStream().listen()` 是异步的，`onListen()` 回调触发时 Dart 侧的 listener 可能还没完全就绪。
**教训**：不能依赖 `onListen` 后立即发送数据，需要 Flutter 侧主动拉一次。

### 5. Android Service 被杀重建
`START_STICKY` 保证 Service 被杀后重建，但所有成员变量（`isTracking`、`lastLocation`、`intervalSeconds`）全部重置为默认值。
**教训**：Service 被杀重建后，状态全丢，不能依赖内存中的状态。需要在 `onStartCommand` 中根据 intent 重新初始化。

### 6. Dart print 和 Kotlin Log 不是一个出口
Dart 的 `print()` 输出到 logcat（`I flutter :`），Kotlin 的 `Log.d()` 也输出到 logcat。但 error.log 是 `_errorLogger` 写入的，需要区分。
**教训**：排查 Flutter 侧问题时看 logcat（`I flutter :`），排查 Kotlin 侧问题时看 logcat（`D LocationForegroundService:` 等 tag）。

### 7. `_listenToLocationEvents()` 只在 `start()` 里调用
Flutter 重启后如果用户没有点"启动定位"，EventChannel 监听就没有注册，Kotlin 发过来的位置 Flutter 永远收不到。
**教训**：EventChannel 监听应该在 `init()` 里注册，和服务启动状态解耦。

---

## 优缺点

### 优点

1. **双保险轨迹记录**：Kotlin CSV 文件兜底，Flutter 被杀期间轨迹不丢
2. **Flutter 重连自动恢复**：无需用户手动重新启动定位
3. **EventChannel 和主动拉结合**：即使 push 不通，主动拉也能恢复显示
4. **历史轨迹恢复**：从 Kotlin CSV 读取恢复地图轨迹

### 缺点

1. **复杂**：涉及 Kotlin Service、LocationPlugin、MainActivity、Flutter EventChannel、MethodChannel，多层交互
2. **状态丢失**：Service 被杀重建后所有内存状态丢失，依赖 `onStartCommand` intent 恢复
3. **调试困难**：logcat 多进程交织，Flutter Dart 和 Kotlin 日志格式不同
4. **没有真正解决 EventChannel 断开期间的数据丢失**：只是兜底存 CSV，实时性依赖重连后主动拉

---

## 未来改进方向

1. **持久化追踪状态**：将 `interval`、`powerSaving` 等配置存 SharedPreferences，Service 重建时读取
2. **EventChannel 可靠性**：考虑用带确认的 push 机制替代无状态的 EventChannel
3. **轨迹合并**：Flutter 重连后，Kotlin CSV 数据和 EventChannel push 数据可能有重复，需要去重
4. **日志规范化**：统一用 `ErrorLoggerService` 记录所有关键事件到 error.log，方便远程排查
