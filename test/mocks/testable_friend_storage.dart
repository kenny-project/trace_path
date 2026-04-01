import 'dart:convert';
import 'dart:io';
import 'package:trace_path/com/kenny/trace_path/models/friend_model.dart';
import 'package:trace_path/com/kenny/trace_path/services/friend_service.dart';

/// FriendStorage 的内存实现，用于测试
class InMemoryFriendStorage implements FriendStorage {
  List<Friend> _friends = [];

  @override
  Future<List<Friend>> load() async {
    return List.from(_friends);
  }

  @override
  Future<void> save(List<Friend> friends) async {
    _friends = List.from(friends);
  }

  @override
  Future<void> clear() async {
    _friends.clear();
  }
}

/// FriendStorage 的文件系统实现，用于测试
class FileBasedFriendStorage implements FriendStorage {
  final String testBasePath;
  static const String _fileName = 'friends.json';

  FileBasedFriendStorage(this.testBasePath);

  File get _file => File('$testBasePath/$_fileName');

  @override
  Future<List<Friend>> load() async {
    try {
      if (!await _file.exists()) {
        return [];
      }
      final content = await _file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) => Friend.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('[FileBasedFriendStorage] 加载失败: $e');
      return [];
    }
  }

  @override
  Future<void> save(List<Friend> friends) async {
    try {
      final dir = Directory(testBasePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final jsonList = friends.map((f) => f.toJson()).toList();
      await _file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('[FileBasedFriendStorage] 保存失败: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (e) {
      print('[FileBasedFriendStorage] 清除失败: $e');
    }
  }
}
