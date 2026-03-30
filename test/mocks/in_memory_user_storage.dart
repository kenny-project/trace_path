import 'package:trace_path/com/kenny/trace_path/services/user_service.dart';

/// 内存用户存储（用于测试）
class InMemoryUserStorage implements UserStorage {
  User? _user;

  @override
  Future<User?> load() async {
    return _user;
  }

  @override
  Future<void> save(User? user) async {
    _user = user;
  }

  @override
  Future<void> delete() async {
    _user = null;
  }
}
