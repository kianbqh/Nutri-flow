import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.nextRoute = RoutePaths.home});

  final String nextRoute;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _sending = false;
  bool _verifying = false;
  String? _error;
  String? _helperText;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalizedPhone() => _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').trim();

  Future<void> _sendCode() async {
    final phone = _normalizedPhone();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位大陆手机号');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
      _helperText = null;
    });

    try {
      final dispatch = await ApiService.instance.sendLoginCode(phone);
      setState(() {
        _codeController.text = dispatch.debugCode;
        _helperText = '开发环境验证码：${dispatch.debugCode}（${dispatch.expiresInSeconds ~/ 60} 分钟内有效）';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dispatch.message)),
      );
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '发送验证码'));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    final phone = _normalizedPhone();
    final code = _codeController.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位大陆手机号');
      return;
    }
    if (code.length < 4) {
      setState(() => _error = '请输入验证码');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final session = await ApiService.instance.verifyLoginCode(phone: phone, code: code);
      await AuthService.instance.saveSession(session);
      if (!mounted) return;

      final targetRoute = session.isNewUser && widget.nextRoute == RoutePaths.home
          ? RoutePaths.goals
          : widget.nextRoute;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.isNewUser ? '注册成功，请继续设置目标' : '登录成功')),
      );
      Navigator.pushNamedAndRemoveUntil(context, targetRoute, (_) => false);
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '验证码登录'));
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手机号登录 / 注册')),
      body: AppSoftBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const AppHeroCard(
              icon: Icons.lock_rounded,
              title: '登录后继续记录你的饮食',
              subtitle: '输入手机号和验证码，继续拍照分析、查看历史记录和个性化建议。',
              footer: AppHintStrip(
                icon: Icons.developer_mode_rounded,
                text: '当前是开发环境，验证码会直接展示，便于切换账号测试。',
              ),
            ),
            const SizedBox(height: 18),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(
                    title: '输入登录信息',
                    subtitle: '手机号用于区分账号，验证码用于快速进入系统。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '例如 13800000001',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '验证码'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 136,
                        child: FilledButton(
                          onPressed: _sending || _verifying ? null : _sendCode,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _sending ? '发送中' : '发送验证码',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_helperText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Text(
                        _helperText!,
                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _sending || _verifying ? null : _verifyCode,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: Text(_verifying ? '登录中...' : '登录 / 注册'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}