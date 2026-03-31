import 'package:flutter/material.dart';
import '../ui/home/pages/home_page.dart';
import '../services/error_logger_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _logStart();
  }

  Future<void> _logStart() async {
    await _errorLogger.init();
    await _errorLogger.logAppStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errorLogger.logAppStop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _errorLogger.log(ErrorTag.app, 'action=PAUSED');
        break;
      case AppLifecycleState.resumed:
        _errorLogger.log(ErrorTag.app, 'action=RESUMED');
        break;
      case AppLifecycleState.inactive:
        _errorLogger.log(ErrorTag.app, 'action=INACTIVE');
        break;
      case AppLifecycleState.detached:
        _errorLogger.log(ErrorTag.app, 'action=DETACHED');
        break;
      case AppLifecycleState.hidden:
        _errorLogger.log(ErrorTag.app, 'action=HIDDEN');
        break;
    }
  }

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
