import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

/// 用户模型
class User {
  final String phoneNumber;
  final String? password; // 可选，持久化时不保存密码

  User({required this.phoneNumber, this.password});
}

/// 用户存储接口（用于依赖注入和测试）
abstract class UserStorage {
  Future<User?> load();
  Future<void> save(User? user);
  Future<void> delete();
}

/// 基于文件的用户存储实现
class FileBasedUserStorage implements UserStorage {
  static const String _fileName = 'user.json';

  @override
  Future<User?> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      return User(phoneNumber: json['phoneNumber'] as String);
    } catch (e) {
      Log.e(LogTag.SRVC, 'FileBasedUserStorage 加载失败: $e');
      return null;
    }
  }

  @override
  Future<void> save(User? user) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      final json = {'phoneNumber': user?.phoneNumber};
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      Log.e(LogTag.SRVC, 'FileBasedUserStorage 保存失败: $e');
    }
  }

  @override
  Future<void> delete() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      Log.e(LogTag.SRVC, 'FileBasedUserStorage 删除失败: $e');
    }
  }
}

/// 用户服务（单例）
/// 管理当前登录用户的持久化
class UserService {
  static final UserService _instance = UserService._();
  factory UserService() => _instance;
  UserService._();

  static const _channel = MethodChannel('com.kenny.trace_path/location_service');

  // 存储实现（默认使用文件存储）
  UserStorage _storage = FileBasedUserStorage();

  User? _currentUser;

  User? get currentUser => _currentUser;

  /// 设置自定义存储（用于测试注入）
  void setStorage(UserStorage storage) {
    _storage = storage;
  }

  /// 初始化，加载本地用户
  Future<void> init() async {
    await _load();
  }

  /// 保存登录用户
  Future<void> saveUser(User user) async {
    _currentUser = user;
    await _save();
    // 同步手机号到原生层（供 LocationForegroundService 使用）
    await _syncPhoneToNative(user.phoneNumber);
  }

  /// 同步手机号到原生 SharedPreferences
  Future<void> _syncPhoneToNative(String phoneNumber) async {
    try {
      await _channel.invokeMethod('setPhoneNumber', {'phoneNumber': phoneNumber});
      Log.d(LogTag.SRVC, '同步手机号到原生: $phoneNumber');
    } catch (e) {
      Log.e(LogTag.SRVC, '同步手机号失败: $e');
    }
  }

  /// 清除用户（退出登录）
  Future<void> clearUser() async {
    _currentUser = null;
    await _storage.delete();
  }

  /// 是否已登录
  bool get isLoggedIn => _currentUser != null;

  /// 获取当前手机号，未登录返回 null
  String? get currentPhoneNumber => _currentUser?.phoneNumber;

  /// 从本地加载（通过存储接口）
  Future<void> _load() async {
    _currentUser = await _storage.load();
  }

  /// 保存到本地（通过存储接口）
  Future<void> _save() async {
    await _storage.save(_currentUser);
  }
}
