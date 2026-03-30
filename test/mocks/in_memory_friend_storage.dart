import 'package:trace_path/com/kenny/trace_path/models/friend_model.dart';
import 'package:trace_path/com/kenny/trace_path/services/friend_service.dart';

/// 内存好友存储（用于测试）
class InMemoryFriendStorage implements FriendStorage {
  final List<Friend> _friends = [];

  @override
  Future<List<Friend>> load() async {
    return List.from(_friends);
  }

  @override
  Future<void> save(List<Friend> friends) async {
    _friends.clear();
    _friends.addAll(friends);
  }

  @override
  Future<void> clear() async {
    _friends.clear();
  }
}
