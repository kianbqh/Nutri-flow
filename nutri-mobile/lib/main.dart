import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/upload_page.dart';
import 'pages/profile_page.dart';
import 'pages/history_page.dart';
import 'pages/onboarding_page.dart';

void main() {
  runApp(const NutriMobileApp());
}

class NutriMobileApp extends StatelessWidget {
  const NutriMobileApp({super.key});

  Future<bool> _isOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen_v1') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE97A3A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Nutri-Flow',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFFFF8F3),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: const Color(0xFF2E2A27),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        useMaterial3: true,
      ),
      routes: {
        '/upload': (_) => const UploadPage(),
        '/profile': (_) => const ProfilePage(),
        '/history': (_) => const HistoryPage(),
      },
      home: FutureBuilder<bool>(
        future: _isOnboardingSeen(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data! ? const HomePage() : const OnboardingPage();
        },
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('灵动食迹 Nutri-Flow')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              '拍照识别餐食，自动估算热量并生成个性化建议',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/upload'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('开始分析'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/profile'),
              icon: const Icon(Icons.flag),
              label: const Text('我的目标'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/history'),
              icon: const Icon(Icons.history),
              label: const Text('历史记录'),
            ),
          ],
        ),
      ),
    );
  }
}
