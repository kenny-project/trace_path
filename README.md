# trace_path

一个 Flutter 跨平台项目。

## 项目结构

项目采用 Java 代码组织风格，按功能模块分层：

```
lib/
├── main.dart                                    # 程序入口
└── com/example/trace_path/
    ├── app/
    │   └── MyApp.dart                          # 应用主类（StatelessWidget）
    └── ui/
        └── home/
            ├── MyHomePage.dart                 # 页面组件（StatefulWidget）
            └── MyHomePageState.dart           # 页面状态类
```

### 目录结构说明

| 目录 | 说明 |
|------|------|
| `app/` | 应用层，包含全局配置和主组件 |
| `ui/` | 界面层，按页面或功能模块组织 |
| `ui/home/` | 主页模块 |

### 代码风格规范

1. **包命名**：使用反向域名命名法 `com.example.trace_path.*`
2. **类文件组织**：
   - 每个类单独一个文件
   - 文件名与类名一致（首字母大写）
3. **State 分离**：StatefulWidget 的 State 单独一个文件
4. **导入路径**：使用相对路径或包路径

## 开发指南

### 常用命令

```bash
# 运行 Android 应用
flutter run -d android

# 运行 Linux 桌面应用
flutter run -d linux

# 构建 Release 版本
flutter build release
```

### 添加新页面

1. 在 `lib/com/example/trace_path/ui/` 下创建模块目录
2. 创建 `XxxPage.dart`（页面组件）
3. 创建 `XxxPageState.dart`（页面状态）
4. 在 `main.dart` 中导入使用


# 运行 Linux 桌面应用
flutter run -d linux

# 运行 Android 真机 应用
flutter run -d "MEY AN00"

# 备份 Android 应用数据
adb backup -f trace_path_backup.ab -noapk com.example.trace_path
# 解压备份文件
java -jar abe.jar unpack trace_path_backup.ab trace_path_backup.tar

# 查看日志
adb logcat | grep -i "HomePage\|MinePage\|定位\|crash\|flutter"
