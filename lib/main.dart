import 'package:flutter/material.dart';
import 'com/kenny/trace_path/app/MyApp.dart';
import 'com/kenny/trace_path/services/user_service.dart';
import 'com/kenny/trace_path/services/friend_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务（确保 UserService 先于 FriendService）
  await UserService().init();
  await FriendService().init();

  runApp(const MyApp());
}
