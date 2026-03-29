import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/friend_model.dart';

/// 好友服务（单例）
/// 管理好友列表的持久化
class FriendService {
  static final FriendService _instance = FriendService._();
  factory FriendService() => _instance;
  FriendService._();

  static const String _fileName = 'friends.json';

  List<Friend> _friends = [];

  List<Friend> get friends => List.unmodifiable(_friends);

  /// 初始化，加载本地数据
  Future<void> init() async {
    await _load();
    // 如果列表为空，添加默认用户
    if (_friends.isEmpty) {
      _friends.add(Friend(
        phoneNumber: '18511698488',
        name: '我自己',
        emoji: '🐤',
      ));
      await _save();
    }
  }

  /// 添加好友
  Future<bool> addFriend(Friend friend) async {
    // 检查是否已存在
    if (_friends.any((f) => f.phoneNumber == friend.phoneNumber)) {
      return false; // 已存在
    }
    _friends.add(friend);
    await _save();
    return true;
  }

  /// 删除好友
  Future<bool> removeFriend(String phoneNumber) async {
    final index = _friends.indexWhere((f) => f.phoneNumber == phoneNumber);
    if (index == -1) return false;
    _friends.removeAt(index);
    await _save();
    return true;
  }

  /// 更新好友位置
  Future<void> updateFriendLocation(String phoneNumber, double lat, double lng, {String? address}) async {
    final index = _friends.indexWhere((f) => f.phoneNumber == phoneNumber);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(
        lat: lat,
        lng: lng,
        address: address,
        lastUpdateTime: DateTime.now(),
      );
      await _save();
    }
  }

  /// 根据手机号获取好友
  Friend? getFriend(String phoneNumber) {
    try {
      return _friends.firstWhere((f) => f.phoneNumber == phoneNumber);
    } catch (_) {
      return null;
    }
  }

  /// 从本地加载
  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      _friends = jsonList.map((json) => Friend.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('[FriendService] 加载失败: $e');
    }
  }

  /// 保存到本地
  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      final jsonList = _friends.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('[FriendService] 保存失败: $e');
    }
  }
}
