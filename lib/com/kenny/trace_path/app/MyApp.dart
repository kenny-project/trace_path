import 'package:flutter/material.dart';
import '../ui/home/pages/home_page.dart';
import '../services/background_location_service.dart';
import '../services/error_logger_service.dart';
import '../utils/logger.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  /// 初始化核心服务
  /// 在应用启动时立即初始化，避免依赖特定页面
  Future<void> _initializeServices() async {
    // 确保日志服务先初始化，避免 Log 调用时 init 未完成
    await ErrorLoggerService().init();

    Log.i(LogTag.SRVC, 'APP_START');
    // 初始化定位服务（后台启动，不阻塞 UI）
    BackgroundLocationService().init().catchError((e) {
      Log.e(LogTag.SRVC, 'APP_INIT_FAILED: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Log.i(LogTag.SRVC, 'APP_STOP');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trace Path',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}