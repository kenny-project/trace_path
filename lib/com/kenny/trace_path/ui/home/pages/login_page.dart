import 'package:flutter/material.dart';
import 'package:trace_path/constants/colors.dart';
import 'package:trace_path/constants/mine_strings.dart';
import '../../../services/user_service.dart';
import '../../../services/friend_service.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agreed = false;
  bool _obscurePassword = true;
  String? _phoneError;
  String? _passwordError;

  final UserService _userService = UserService();
  final FriendService _friendService = FriendService();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 验证手机号格式
  bool _validatePhone(String phone) {
    // 中国大陆手机号正则：1开头，第二位3-9，后面9位数字
    final regex = RegExp(r'^1[3-9]\d{9}$');
    return regex.hasMatch(phone);
  }

  /// 验证密码（最小6位）
  bool _validatePassword(String password) {
    return password.length >= 6;
  }

  /// 执行登录验证
  bool _doValidate() {
    bool valid = true;
    setState(() {
      _phoneError = null;
      _passwordError = null;

      if (!_validatePhone(_phoneController.text)) {
        _phoneError = '请输入正确的手机号';
        valid = false;
      }

      if (!_validatePassword(_passwordController.text)) {
        _passwordError = '密码至少6位';
        valid = false;
      }
    });
    return valid;
  }

  /// 处理登录
  Future<void> _handleLogin() async {
    if (!_agreed) {
      _showToast('请先阅读并同意协议');
      return;
    }

    if (!_doValidate()) return;

    // 保存用户
    await _userService.saveUser(User(phoneNumber: _phoneController.text));

    // 更新"我自己"的手机号
    await _friendService.updateSelf(phoneNumber: _phoneController.text);

    if (mounted) {
      _showToast('登录成功');
      Navigator.pop(context); // 返回上一页
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),

            // 手机号输入
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: '手机号',
                hintText: '请输入手机号',
                prefixIcon: const Icon(Icons.phone),
                border: const OutlineInputBorder(),
                errorText: _phoneError,
              ),
              onChanged: (_) {
                if (_phoneError != null) {
                  setState(() => _phoneError = null);
                }
              },
            ),
            const SizedBox(height: 20),

            // 密码输入
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入密码',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                errorText: _passwordError,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
            ),
            const SizedBox(height: 24),

            // 协议同意
            Row(
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.primary,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _agreed = !_agreed),
                    child: const Text(
                      '我已阅读并同意《用户协议》和《隐私政策》',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 登录按钮
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '登录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
