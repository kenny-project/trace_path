import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/services/user_service.dart';
import '../mocks/in_memory_user_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserService', () {
    late InMemoryUserStorage storage;
    late UserService userService;

    setUp(() {
      storage = InMemoryUserStorage();
      userService = UserService();
      userService.setStorage(storage);
    });

    group('init', () {
      test('初始化后无用户数据', () async {
        await userService.init();

        expect(userService.isLoggedIn, isFalse);
        expect(userService.currentPhoneNumber, isNull);
      });

      test('初始化后有已保存用户', () async {
        await storage.save(User(phoneNumber: '13800138000'));
        await userService.init();

        expect(userService.isLoggedIn, isTrue);
        expect(userService.currentPhoneNumber, equals('13800138000'));
      });

      test('重复初始化不改变状态', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));
        await userService.init();

        expect(userService.isLoggedIn, isTrue);
        expect(userService.currentPhoneNumber, equals('13800138000'));
      });
    });

    group('saveUser', () {
      test('保存用户后 isLoggedIn 为 true', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '13800138000'));

        expect(userService.isLoggedIn, isTrue);
      });

      test('保存用户后 currentPhoneNumber 正确', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '13800138000'));

        expect(userService.currentPhoneNumber, equals('13800138000'));
      });

      test('保存用户后 currentUser 正确', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '13800138000'));

        expect(userService.currentUser, isNotNull);
        expect(userService.currentUser!.phoneNumber, equals('13800138000'));
      });

      test('覆盖保存用户', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));
        await userService.saveUser(User(phoneNumber: '13900001111'));

        expect(userService.currentPhoneNumber, equals('13900001111'));
      });

      test('保存用户数据持久化', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        // 重新初始化后能读取到保存的用户
        final newService = UserService();
        newService.setStorage(storage);
        await newService.init();

        expect(newService.isLoggedIn, isTrue);
        expect(newService.currentPhoneNumber, equals('13800138000'));
      });
    });

    group('clearUser', () {
      test('清除用户后 isLoggedIn 为 false', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        await userService.clearUser();

        expect(userService.isLoggedIn, isFalse);
      });

      test('清除用户后 currentPhoneNumber 为 null', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        await userService.clearUser();

        expect(userService.currentPhoneNumber, isNull);
      });

      test('清除用户后 currentUser 为 null', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        await userService.clearUser();

        expect(userService.currentUser, isNull);
      });

      test('清除用户后存储被删除', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        await userService.clearUser();

        // 重新初始化后应该是未登录状态
        final newService = UserService();
        newService.setStorage(storage);
        await newService.init();

        expect(newService.isLoggedIn, isFalse);
      });

      test('重复清除用户不报错', () async {
        await userService.init();

        await userService.clearUser();
        await expectLater(userService.clearUser(), completes);
      });
    });

    group('isLoggedIn', () {
      test('初始状态为 false', () async {
        await userService.init();

        expect(userService.isLoggedIn, isFalse);
      });

      test('保存用户后为 true', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '13800138000'));

        expect(userService.isLoggedIn, isTrue);
      });

      test('清除用户后为 false', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));
        await userService.clearUser();

        expect(userService.isLoggedIn, isFalse);
      });
    });

    group('currentPhoneNumber', () {
      test('未登录时返回 null', () async {
        await userService.init();

        expect(userService.currentPhoneNumber, isNull);
      });

      test('登录后返回正确手机号', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '13800138000'));

        expect(userService.currentPhoneNumber, equals('13800138000'));
      });

      test('不同格式手机号', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '+8613800138000'));

        expect(userService.currentPhoneNumber, equals('+8613800138000'));
      });
    });

    group('边界条件', () {
      test('空手机号', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: ''));

        expect(userService.isLoggedIn, isTrue);
        expect(userService.currentPhoneNumber, equals(''));
      });

      test('超长手机号', () async {
        await userService.init();

        final longPhone = '1' * 50;
        await userService.saveUser(User(phoneNumber: longPhone));

        expect(userService.currentPhoneNumber, equals(longPhone));
      });

      test('特殊字符手机号', () async {
        await userService.init();

        await userService.saveUser(User(phoneNumber: '138-0013-8000'));

        expect(userService.currentPhoneNumber, equals('138-0013-8000'));
      });

      test('保存用户后立即清除', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));
        await userService.clearUser();

        expect(userService.isLoggedIn, isFalse);
        expect(userService.currentPhoneNumber, isNull);
      });

      test('保存 null 用户后重新加载', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));
        expect(userService.isLoggedIn, isTrue);

        // 直接操作 storage 保存 null
        await storage.save(null);

        // userService 内存中仍是登录状态，但存储已为 null
        // 重新初始化后会从存储加载 null
        final newService = UserService();
        newService.setStorage(storage);
        await newService.init();

        expect(newService.isLoggedIn, isFalse);
      });
    });
  });
}
