import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_chrome.dart';

class AccessGatePage extends StatefulWidget {
  const AccessGatePage({
    super.key,
    required this.onGranted,
  });

  final VoidCallback onGranted;

  @override
  State<AccessGatePage> createState() => _AccessGatePageState();
}

class _AccessGatePageState extends State<AccessGatePage> {
  final TextEditingController _controller = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入测试授权码');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ApiService.instance.verifyAndSaveAccessCode(code);
      if (!mounted) return;
      widget.onGranted();
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '授权验证'));
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppSoftBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/branding/nutriflow-app-icon-1024.png',
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '灵动食迹',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF30271F),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '输入测试授权码后继续',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF7A6A5D)),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _controller,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        onSubmitted: (_) {
                          if (!_verifying) {
                            _submit();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: '授权码',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _verifying ? null : _submit,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(_verifying ? '正在验证...' : '进入 NutriFlow'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
