import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/friend_model.dart';
import 'user_service.dart';

/// 好友服务（单例）
/// 管理好友列表的持久化
class FriendService {
  static final FriendService _instance = FriendService._();
  factory FriendService() => _instance;
  FriendService._();

  static const String _fileName = 'friends.json';
  static const String _defaultSelfPhone = '1000000'; // 默认"我自己"手机号
  static const String _defaultSelfName = '我自己';
  static const String _defaultSelfEmoji = '🐤';

  final UserService _userService = UserService();

  List<Friend> _friends = [];

  List<Friend> get friends => List.unmodifiable(_friends);

  /// 初始化，加载本地数据
  Future<void> init() async {
    await _load();
    // 确保"我自己"存在
    await _ensureSelfExists();
  }

  /// 确保"我自己"存在
  Future<void> _ensureSelfExists() async {
    // 获取当前登录用户手机号，如果没登录则使用默认
    final selfPhone = _userService.currentPhoneNumber ?? _defaultSelfPhone;

    // 查找"我自己"
    final selfIndex = _friends.indexWhere((f) => f.name == _defaultSelfName);

    if (selfIndex == -1) {
      // 不存在，添加"我自己"
      _friends.insert(0, Friend(
        phoneNumber: selfPhone,
        name: _defaultSelfName,
        emoji: _defaultSelfEmoji,
      ));
      await _save();
    } else {
      // 存在，更新手机号（登录后可能变化）
      _friends[selfIndex] = _friends[selfIndex].copyWith(phoneNumber: selfPhone);
      await _save();
    }
  }

  /// 更新"我自己"信息（登录后调用）
  Future<void> updateSelf({String? phoneNumber, String? name, String? emoji}) async {
    final selfIndex = _friends.indexWhere((f) => f.name == _defaultSelfName);
    if (selfIndex != -1) {
      _friends[selfIndex] = _friends[selfIndex].copyWith(
        phoneNumber: phoneNumber ?? _friends[selfIndex].phoneNumber,
        name: name ?? _defaultSelfName,
        emoji: emoji ?? _defaultSelfEmoji,
      );
      await _save();
    }
  }

  /// add friend
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

  /// 清空所有好友（退出登录时使用）
  Future<void> clearAllFriends() async {
    _friends.clear();
    await _save();
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
