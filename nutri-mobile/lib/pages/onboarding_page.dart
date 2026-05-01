import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_page.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _seenKey = 'onboarding_seen_v1';

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  Future<void> _goToUpload() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: RoutePaths.auth),
        builder: (_) => const AuthPage(nextRoute: RoutePaths.upload),
      ),
    );
  }

  Future<void> _goToGoalSettingsFirst() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: RoutePaths.auth),
        builder: (_) => const AuthPage(nextRoute: RoutePaths.goals),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('欢迎使用灵动食迹')),
      body: AppSoftBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const AppHeroCard(
              icon: Icons.eco_rounded,
              title: '先设置你的目标',
              subtitle: '这样后续的热量建议和饮食提示都会更贴近你的当前状态，个人主页里的昵称稍后也能再改。',
              footer: AppHintStrip(
                icon: Icons.favorite_border_rounded,
                text: '你也可以先拍照体验，稍后再去目标设置页补充信息。',
              ),
            ),
            const SizedBox(height: 18),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(
                    title: '选择开始方式',
                    subtitle: '推荐先设置目标；如果只是先体验，也可以直接进入拍照分析。',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _goToGoalSettingsFirst,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('先设置目标'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _goToUpload,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('先体验拍照分析'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '提示：本应用提供热量估算与饮食建议，不替代医疗诊断。',
                    style: TextStyle(color: Color(0xFF7A6A5D), height: 1.5),
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
