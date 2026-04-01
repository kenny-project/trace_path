# 坐标系设计文档

> 建立时间: 2026-04-01
> 更新记录:
> - 2026-04-01: 初始文档，定义坐标系流程

## 一、坐标系基础

### 1.1 常用坐标系

| 坐标系 | 说明 | 应用场景 |
|--------|------|---------|
| **WGS84** | GPS 原始坐标系统 | 设备定位、轨迹存储 |
| **GCJ-02** | 中国国测局坐标（火星坐标） | 国内地图显示（高德、腾讯） |
| **BD-09** | 百度坐标 | 百度地图专用 |

### 1.2 本项目使用的坐标系

- **存储层**: WGS84（原始坐标，不丢失精度）
- **显示层**: GCJ-02（国内地图必须）

## 二、坐标流程图

```
┌─────────────────────────────────────────────────────────────────────┐
│                          数据流方向                                  │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Geolocator  │     │  TrackRecorder   │     │   地图显示层      │
│   (GPS/网络)  │     │  (存储 WGS84)    │     │   (GCJ-02)       │
└──────┬───────┘     └────────┬─────────┘     └────────┬─────────┘
       │                       │                       │
       ▼                       ▼                       ▼
   WGS84 坐标            WGS84 存储             GCJ-02 显示
       │                       │                       │
       │                       │                       │
       └───────────────────────┴───────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  BackgroundLocation │
                    │     Service         │
                    └─────────────────────┘
```

## 三、各环节坐标系处理

### 3.1 定位获取

| 类/方法 | 返回坐标 | 说明 |
|--------|---------|------|
| `Geolocator.getCurrentPosition()` | WGS84 | 设备原始坐标 |
| `BackgroundLocationService.getCurrentPosition()` | WGS84 | 不做转换 |

### 3.2 轨迹存储

| 操作 | 坐标系 | 说明 |
|------|--------|------|
| `TrackRecorder.record(position)` | WGS84 | 直接保存原始坐标 |
| 存储文件格式 | WGS84 | 保持原始精度 |

### 3.3 地图显示

| 场景 | 坐标系 | 转换位置 |
|------|--------|---------|
| 定位页面实时位置 | GCJ-02 | `LocationPage` 调用 `wgs84ToGcj02()` |
| 好友位置标记 | GCJ-02 | 存储的 GCJ-02 坐标直接使用 |
| 历史轨迹显示 | GCJ-02 | `TrackService.readDayTrack()` 读取时转换 |

### 3.4 地址解析

| API | 需要的坐标系 | 转换 |
|-----|------------|------|
| Nominatim (OSM) | WGS84 | 调用 `gcj02ToWgs84()` 转换后再请求 |

## 四、坐标系转换方法

### 4.1 WGS84 → GCJ-02

```dart
// BackgroundLocationService.wgs84ToGcj02(lat, lng)
final gcj02 = _locationService.wgs84ToGcj02(position.latitude, position.longitude);
// gcj02[0] = latitude, gcj02[1] = longitude
```

### 4.2 GCJ-02 → WGS84 (逆转换)

```dart
// BackgroundLocationService.gcj02ToWgs84(lat, lng)
final wgs84 = _locationService.gcj02ToWgs84(gcjLat, gcjLng);
// wgs84[0] = latitude, wgs84[1] = longitude
```

## 五、开发规范（强制遵守）

### 5.1 新增代码时

1. **获取定位后**：`getCurrentPosition()` 返回 WGS84，不要在此转换
2. **保存轨迹时**：使用 WGS84 原始坐标
3. **显示到地图前**：必须调用 `wgs84ToGcj02()` 转换
4. **调用外部 API 时**：根据 API 要求选择坐标系（OSM 用 WGS84）

### 5.2 禁止事项

- ❌ 禁止在 `getCurrentPosition()` 内部进行 GCJ-02 转换
- ❌ 禁止对已转换的坐标重复转换
- ❌ 禁止混用 WGS84 和 GCJ-02

### 5.3 调试技巧

查看日志中坐标变化：
```
[BLS] 定位成功: lat=39.9..., lng=116.3...  // WGS84 原始坐标
[LocationPage] 显示坐标: lat=39.9..., lng=116.3...  // GCJ-02 显示坐标
```

## 六、相关文件

| 文件 | 职责 |
|------|------|
| `services/background_location_service.dart` | 定位服务，提供坐标转换方法 |
| `services/track_recorder.dart` | 轨迹录制，始终保存 WGS84 |
| `services/track_service.dart` | 轨迹服务，读取时转换为 GCJ-02 |
| `services/compressed_track_storage.dart` | 压缩存储，存储 WGS84 |
| `ui/home/pages/location_page.dart` | 定位页面，显示时转换 |

## 七、历史问题记录

### 7.1 2026-04-01 修复的问题

**问题1**: 定位界面显示的位置与轨迹记录不一致

- **原因**: `BackgroundLocationService.getCurrentPosition()` 内部做了 GCJ-02 转换，但服务未启动导致 `LocationPage` 直接调用 `getCurrentPosition()` 时拿到的是已转换坐标，而 `TrackRecorder` 保存的也是这个已转换坐标
- **修复**: `getCurrentPosition()` 不再转换，`LocationPage` 负责显示时的转换

**问题2**: 历史轨迹加载时坐标二次转换

- **原因**: 保存时已存 GCJ-02，读取时 `readDayTrack()` 又调用 `toGcj02()` 导致双重转换
- **修复**: 保存时存 WGS84，读取时单次转换

## 八、测试验证

### 8.1 坐标一致性验证

1. 同一个位置，WGS84 和 GCJ-02 应该有差异（北京地区约 100-300 米）
2. 轨迹点显示位置应与地图底图匹配
3. 地址解析结果应与实际位置一致

### 8.2 验证代码

```dart
// 验证 WGS84 → GCJ-02 → WGS84 是否能还原
final original = [39.908823, 116.397470]; // WGS84
final gcj = wgs84ToGcj02(original[0], original[1]);
final还原 = gcj02ToWgs84(gcj[0], gcj[1]);
// 还原后应与 original 非常接近（误差 < 0.0001）
```
