# trace_path UML Mermaid Diagrams
# These diagrams can be rendered in any Mermaid-compatible viewer (e.g., draw.io, VS Code Mermaid Preview, GitHub, etc.)

## 1. 类图 (Class Diagram)

```mermaid
classDiagram
    class BackgroundLocationService {
        <<Singleton>>
        - LocationProvider _locationProvider
        - LocationSettingsService _settingsService
        - UserService _userService
        - ErrorLoggerService _errorLogger
        - List~LocationCallback~ _subscribers
        - bool _isTracking
        - int _intervalSeconds
        + start()
        + stop()
        + subscribe(cb)
        + unsubscribe(cb)
        + getCurrentPosition()
        + _broadcast(event)
    }

    class TrackRecorder {
        <<Singleton>>
        - TrackStorage _storage
        + record(Position position)
        + readDay(String phone, int year, int month, int day)
        + setStorage(TrackStorage storage)
    }

    class FriendService {
        <<Singleton>>
        - List~Friend~ _friends
        - FriendStorage _storage
        + addFriend(friend)
        + removeFriend(phoneNumber)
        + updateFriendLocation(phone, lat, lng)
        + getFriends()
        + saveFriends()
    }

    class UserService {
        <<Singleton>>
        - User? _currentUser
        - UserStorage _storage
        + saveUser(user)
        + clearUser()
        + isLoggedIn
        + currentPhoneNumber
    }

    class LocationProvider {
        <<abstract>>
        + getCurrentPosition() Position?
        + checkPermission() bool
        + isLocationServiceEnabled() bool
        + dispose()
    }

    class GeolocatorLocationProvider {
        - ErrorLoggerService? _errorLogger
        + getCurrentPosition() Position?
        + checkPermission() bool
        + isLocationServiceEnabled() bool
    }

    class NativeLocationProvider {
        - ErrorLoggerService? _errorLogger
        + getCurrentPosition() Position?
        + checkPermission() bool
        + isLocationServiceEnabled() bool
    }

    class TrackStorage {
        <<abstract>>
        + write(String phone, TrackPoint point)
        + readDay(String phone, int year, int month, int day) List~TrackPoint~
        + deleteDay(String phone, int year, int month, int day)
        + syncToServer()
        + pullFromServer()
    }

    class CompressedTrackStorage {
        - TrackStorageManager _manager
        + write(String phone, TrackPoint point)
        + readDay(...) List~TrackPoint~
        + deleteDay(...)
        + getCompressionRatio() double
    }

    class LocalCsvStorage {
        - TrackStorageManager _manager
        + write(String phone, TrackPoint point)
        + readDay(...) List~TrackPoint~
        + deleteDay(...)
    }

    class Friend {
        <<Model>>
        - String phoneNumber
        - String name
        - String emoji
        - double? lat
        - double? lng
        - String? address
        - DateTime? lastUpdateTime
        + toJson()
        + fromJson()
    }

    class TrackPoint {
        <<Model>>
        - DateTime timestamp
        - double latitude
        - double longitude
        - double altitude
        - double speed
        - double accuracy
        + fromPosition(Position pos)
        + toLatLng()
        + toCsvLine()
    }

    class LocationEvent {
        <<Model>>
        - LocationEventType type
        - Position? position
        - String? errorMessage
        + position() bool
        + error() bool
        + serviceStart()
        + serviceStop()
    }

    %% Relationships
    BackgroundLocationService ..> LocationProvider : "uses (delegates)"
    BackgroundLocationService ..> TrackRecorder : "calls .record()"
    BackgroundLocationService ..> LocationSettingsService : "uses"
    BackgroundLocationService ..> UserService : "uses"
    BackgroundLocationService ..> ErrorLoggerService : "uses"

    TrackRecorder ..> TrackStorage : "has (composition)"
    TrackRecorder ..> UserService : "uses"

    FriendService ..> Friend : "manages"
    FriendService ..> UserService : "uses"

    GeolocatorLocationProvider --|> LocationProvider : "implements"
    NativeLocationProvider --|> LocationProvider : "implements"
    CompressedTrackStorage --|> TrackStorage : "implements"
    LocalCsvStorage --|> TrackStorage : "implements"
```

## 2. 时序图 (Sequence Diagram) - 定位更新流程

```mermaid
sequenceDiagram
    participant User
    participant BackgroundLocationService
    participant LocationProvider
    participant GPS as GPS/Network
    participant TrackRecorder
    participant CompressedTrackStorage

    User->>BackgroundLocationService: start()
    BackgroundLocationService->>LocationProvider: checkPermission()
    LocationProvider-->>BackgroundLocationService: bool

    alt permission granted
        BackgroundLocationService->>BackgroundLocationService: start native foreground service
        Note right of BackgroundLocationService: 通知栏保活<br/>Android前台服务
    end

    BackgroundLocationService->>BackgroundLocationService: _startLocationLoop()
    loop Every intervalSeconds
        BackgroundLocationService->>LocationProvider: getCurrentPosition()
        LocationProvider->>GPS: GPS.getCurrentPosition()
        GPS-->>LocationProvider: Position or null
        alt GPS failed (< 60%)
            LocationProvider->>GPS: Network.getCurrentPosition()
            GPS-->>LocationProvider: Position or null (fallback)
        end
        LocationProvider-->>BackgroundLocationService: Position?

        alt Position available
            BackgroundLocationService->>BackgroundLocationService: _broadcast(LocationEvent)
            BackgroundLocationService->>TrackRecorder: record(position)
            TrackRecorder->>CompressedTrackStorage: write(phone, TrackPoint)
            CompressedTrackStorage-->>TrackRecorder: void
            CompressedTrackStorage->>CompressedTrackStorage: append .dat file
            TrackRecorder-->>BackgroundLocationService: void
            BackgroundLocationService->>BackgroundLocationService: _scheduleNextLocation()
        else Position null
            BackgroundLocationService->>BackgroundLocationService: _scheduleGpsRetry()
            Note right of BackgroundLocationService: 指数退避<br/>15s→30s→60s→120s→240s<br/>最多重试5次
        end
    end

    User->>BackgroundLocationService: stop()
    BackgroundLocationService->>BackgroundLocationService: stop native service
    BackgroundLocationService->>BackgroundLocationService: _broadcast(LocationEvent.serviceStop)
```

## 3. 架构图 (Architecture Diagram) - 模块分层

```mermaid
graph TB
    subgraph Presentation["📦 Presentation Layer（表现层）"]
        HomePage["HomePage / GuardPage / LoginPage / MinePage"]
        LocationPage["LocationPage / TrackPage / TrackMapPage"]
        PermissionPage["PermissionSettingsPage / LogViewerPage"]
    end

    subgraph Business["⚙️ Business Logic Layer（业务逻辑层）"]
        FBLS["BackgroundLocationService（单例）"]
        TR["TrackRecorder（单例）"]
        FS["FriendService（单例）"]
        US["UserService（单例）"]
        LSS["LocationSettingsService"]
        ELS["ErrorLoggerService"]
    end

    subgraph Abstraction["🔧 Service Abstraction Layer（服务抽象层）"]
        LP["LocationProvider（abstract）"]
        TS["TrackStorage（abstract）"]
        FST["FriendStorage（abstract）"]
        UST["UserStorage（abstract）"]
    end

    subgraph Data["💾 Data Access Layer（数据访问层）"]
        CTS["CompressedTrackStorage（默认，二进制）"]
        LCS["LocalCsvStorage（CSV明文）"]
        FBS["FileBasedFriendStorage"]
        FBUS["FileBasedUserStorage"]
    end

    subgraph Native["🔌 Native Platform Layer（原生平台层）"]
        AndroidService["Android: LocationForegroundService"]
        FusedLocation["Android: FusedLocationProviderClient"]
        MethodChannel["MethodChannel: com.kenny.trace_path/location_service"]
    end

    %% Presentation -> Business
    HomePage --> FBLS
    HomePage --> TR
    HomePage --> FS
    HomePage --> US

    %% Business -> Abstraction
    FBLS --> LP
    FBLS --> LSS
    FBLS --> ELS
    TR --> TS
    TR --> US
    FS --> FST
    FS --> US
    US --> UST

    %% Abstraction -> Data
    LP --> CTS
    LP --> LCS
    TS --> CTS
    TS --> LCS
    FST --> FBS
    UST --> FBUS

    %% Abstraction -> Native
    LP --> FusedLocation
    FBLS --> AndroidService
    FBLS --> MethodChannel

    %% Native -> Platform
    AndroidService --> FusedLocation
    MethodChannel --> FusedLocation
```

## 4. 状态图 - 定位服务状态机

```mermaid
stateDiagram-v2
    [*] --> Stopped: 初始状态
    Stopped --> CheckingPermission: start()
    CheckingPermission --> Stopped: 权限拒绝
    CheckingPermission --> StartingNativeService: 权限通过
    StartingNativeService --> Running: 原生服务启动成功
    StartingNativeService --> Stopped: 启动失败
    Running --> Running: 定时器触发
    Running --> GettingLocation: _startLocationLoop()
    GettingLocation --> GotLocation: 定位成功
    GettingLocation --> RetryingLocation: 定位失败
    GotLocation --> Broadcasting: _broadcast(event)
    Broadcasting --> SchedulingNext: _scheduleNextLocation()
    SchedulingNext --> Running: 定时器就绪
    RetryingLocation --> RetryingLocation: 重试次数 < 5
    RetryingLocation --> SchedulingNext: 重试次数 >= 5
    Running --> Stopped: stop()
    GotLocation --> Stopped: stop()
```
