import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 用户模型
class User {
  final String phoneNumber;
  final String? password; // 可选，持久化时不保存密码

  User({required this.phoneNumber, this.password});
}

/// 用户服务（单例）
/// 管理当前登录用户的持久化
class UserService {
  static final UserService _instance = UserService._();
  factory UserService() => _instance;
  UserService._();

  static const String _fileName = 'user.json';

  User? _currentUser;

  User? get currentUser => _currentUser;

  /// 初始化，加载本地用户
  Future<void> init() async {
    await _load();
  }

  /// 保存登录用户
  Future<void> saveUser(User user) async {
    _currentUser = user;
    await _save();
  }

  /// 清除用户（退出登录）
  Future<void> clearUser() async {
    _currentUser = null;
    await _delete();
  }

  /// 是否已登录
  bool get isLoggedIn => _currentUser != null;

  /// 获取当前手机号，未登录返回 null
  String? get currentPhoneNumber => _currentUser?.phoneNumber;

  /// 从本地加载
  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      _currentUser = User(phoneNumber: json['phoneNumber'] as String);
    } catch (e) {
      print('[UserService] 加载失败: $e');
    }
  }

  /// 保存到本地（只保存手机号，不保存密码）
  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      final json = {'phoneNumber': _currentUser?.phoneNumber};
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print('[UserService] 保存失败: $e');
    }
  }

  /// 删除用户文件
  Future<void> _delete() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('[UserService] 删除失败: $e');
    }
  }
}
