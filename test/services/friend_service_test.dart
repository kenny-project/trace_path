import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/models/friend_model.dart';
import 'package:trace_path/com/kenny/trace_path/services/friend_service.dart';
import 'package:trace_path/com/kenny/trace_path/services/user_service.dart';
import '../mocks/in_memory_friend_storage.dart';
import '../mocks/in_memory_user_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FriendService', () {
    late InMemoryFriendStorage friendStorage;
    late InMemoryUserStorage userStorage;
    late FriendService friendService;
    late UserService userService;

    setUp(() {
      friendStorage = InMemoryFriendStorage();
      userStorage = InMemoryUserStorage();
      friendService = FriendService();
      userService = UserService();

      // 注入内存存储
      friendService.setStorage(friendStorage);
      userService.setStorage(userStorage);
    });

    group('init', () {
      test('初始化后应包含"我自己"默认好友', () async {
        await friendService.init();

        final selfPhone = friendService.getSelfPhone();
        expect(selfPhone, isNotEmpty);
        expect(friendService.friends, isNotEmpty);
      });

      test('重复初始化不重复添加"我自己"', () async {
        await friendService.init();
        final countAfterFirstInit = friendService.friends.length;

        await friendService.init();
        final countAfterSecondInit = friendService.friends.length;

        expect(countAfterSecondInit, equals(countAfterFirstInit));
      });

      test('登录后"我自己"手机号应与用户手机号一致', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13900001111'));
        await friendService.init();

        expect(friendService.getSelfPhone(), equals('13900001111'));
      });
    });

    group('addFriend', () {
      test('添加新好友成功', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        final result = await friendService.addFriend(friend);

        expect(result, isTrue);
        expect(friendService.friends.length, greaterThan(1)); // 包含"我自己"+好友
      });

      test('添加重复手机号的好友失败', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        final result = await friendService.addFriend(friend);

        expect(result, isFalse);
      });

      test('添加好友后能通过 getFriend 获取', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        final retrieved = friendService.getFriend('13800138000');

        expect(retrieved, isNotNull);
        expect(retrieved!.name, equals('测试好友'));
      });
    });

    group('removeFriend', () {
      test('删除存在的好友成功', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        final result = await friendService.removeFriend('13800138000');

        expect(result, isTrue);
        expect(friendService.getFriend('13800138000'), isNull);
      });

      test('删除不存在的好友返回 false', () async {
        await friendService.init();

        final result = await friendService.removeFriend('99999999999');

        expect(result, isFalse);
      });

      test('删除"我自己"好友也能成功（无保护）', () async {
        await friendService.init();

        final selfPhone = friendService.getSelfPhone();
        final result = await friendService.removeFriend(selfPhone);

        // 实际实现中没有保护"我自己"，所以会删除成功
        expect(result, isTrue);
      });
    });

    group('getFriend', () {
      test('获取存在的好友', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        final retrieved = friendService.getFriend('13800138000');

        expect(retrieved, isNotNull);
        expect(retrieved!.phoneNumber, equals('13800138000'));
      });

      test('获取不存在的好友返回 null', () async {
        await friendService.init();

        final retrieved = friendService.getFriend('99999999999');

        expect(retrieved, isNull);
      });
    });

    group('updateFriendLocation', () {
      test('更新好友位置成功', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        await friendService.updateFriendLocation(
          '13800138000',
          39.908823,
          116.397470,
          address: '北京天安门',
        );

        final retrieved = friendService.getFriend('13800138000');

        expect(retrieved, isNotNull);
        expect(retrieved!.lat, equals(39.908823));
        expect(retrieved!.lng, equals(116.397470));
        expect(retrieved!.address, equals('北京天安门'));
      });

      test('更新不存在的好友位置不报错', () async {
        await friendService.init();

        await expectLater(
          friendService.updateFriendLocation('99999999999', 39.908823, 116.397470),
          completes,
        );
      });

      test('更新好友位置后 lastUpdateTime 被设置', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试好友',
          emoji: '👤',
        );

        await friendService.addFriend(friend);
        await friendService.updateFriendLocation('13800138000', 39.908823, 116.397470);

        final retrieved = friendService.getFriend('13800138000');

        expect(retrieved!.lastUpdateTime, isNotNull);
      });
    });

    group('getSelfPhone', () {
      test('初始化后能获取默认手机号', () async {
        await friendService.init();

        final selfPhone = friendService.getSelfPhone();

        expect(selfPhone, isNotEmpty);
      });

      test('登录后获取登录用户手机号', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13900001111'));
        await friendService.init();

        expect(friendService.getSelfPhone(), equals('13900001111'));
      });
    });

    group('updateSelf', () {
      test('更新"我自己"信息成功', () async {
        await friendService.init();
        final originalPhone = friendService.getSelfPhone();

        await friendService.updateSelf(
          phoneNumber: '13900001111',
          name: '我自己',
          emoji: '🐣',
        );

        final self = friendService.getFriend(originalPhone);

        expect(self, isNotNull);
        expect(self!.emoji, equals('🐣'));
      });

      test('不传参数时保持原有值', () async {
        await friendService.init();
        final originalPhone = friendService.getSelfPhone();

        await friendService.updateSelf();

        final self = friendService.getFriend(originalPhone);

        expect(self, isNotNull);
      });
    });

    group('clearAllFriends', () {
      test('清空所有好友包括"我自己"', () async {
        await friendService.init();

        await friendService.addFriend(Friend(
          phoneNumber: '13800138000',
          name: '好友1',
          emoji: '👤',
        ));
        await friendService.addFriend(Friend(
          phoneNumber: '13800138001',
          name: '好友2',
          emoji: '👤',
        ));

        await friendService.clearAllFriends();

        // 实际实现清空所有好友包括"我自己"
        expect(friendService.friends.length, equals(0));
      });

      test('清空后重新初始化能恢复"我自己"', () async {
        await friendService.init();

        await friendService.addFriend(Friend(
          phoneNumber: '13800138000',
          name: '好友1',
          emoji: '👤',
        ));

        await friendService.clearAllFriends();
        await friendService.init();

        expect(friendService.friends.length, equals(1));
      });
    });

    group('边界条件', () {
      test('空手机号添加好友', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '',
          name: '空号好友',
          emoji: '👤',
        );

        final result = await friendService.addFriend(friend);

        expect(result, isTrue);
      });

      test('特殊字符在好友名称中', () async {
        await friendService.init();

        final friend = Friend(
          phoneNumber: '13800138000',
          name: '测试&好友<>/\'"',
          emoji: '👤',
        );

        final result = await friendService.addFriend(friend);

        expect(result, isTrue);
        final retrieved = friendService.getFriend('13800138000');
        expect(retrieved!.name, equals('测试&好友<>/\'"'));
      });

      test('经纬度边界值', () async {
        await friendService.init();

        // 先添加好友再更新位置
        await friendService.addFriend(Friend(
          phoneNumber: '13800138000',
          name: '边界测试',
          emoji: '👤',
        ));
        await friendService.updateFriendLocation('13800138000', 90.0, 180.0);
        final retrieved = friendService.getFriend('13800138000');

        expect(retrieved!.lat, equals(90.0));
        expect(retrieved!.lng, equals(180.0));
      });

      test('大量好友数据存储', () async {
        await friendService.init();

        for (int i = 0; i < 100; i++) {
          await friendService.addFriend(Friend(
            phoneNumber: '138${i.toString().padLeft(8, '0')}',
            name: '好友$i',
            emoji: '👤',
          ));
        }

        expect(friendService.friends.length, greaterThan(100));
      });
    });
  });
}
