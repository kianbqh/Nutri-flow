import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_page.dart';
import 'upload_page.dart';

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
      MaterialPageRoute(builder: (_) => const UploadPage()),
    );
  }

  Future<void> _goToProfileFirst() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('欢迎使用灵动食迹')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: const Text(
                '建议先设置目标，再开始拍照分析。\n\n你也可以直接开始，稍后再补充目标信息。',
                style: TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _goToProfileFirst,
              icon: const Icon(Icons.flag),
              label: const Text('先设置我的目标'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _goToUpload,
              icon: const Icon(Icons.camera_alt),
              label: const Text('先体验拍照分析'),
            ),
            const SizedBox(height: 18),
            const Text(
              '提示：本应用仅提供热量估算与饮食建议，不提供医疗诊断。',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
