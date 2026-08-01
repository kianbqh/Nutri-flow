import 'package:flutter/material.dart';

import 'pages/auth_page.dart';
import 'pages/access_gate_page.dart';
import 'pages/upload_page.dart';
import 'pages/profile_page.dart';
import 'pages/goal_settings_page.dart';
import 'pages/history_page.dart';
import 'services/auth_service.dart';
import 'services/access_code_service.dart';
import 'utils/navigation_utils.dart';

void main() {
  runApp(const NutriMobileApp());
}

class NutriMobileApp extends StatelessWidget {
  const NutriMobileApp({super.key});

  Future<_LaunchState> _loadLaunchState() async {
    await AuthService.instance.ensureLoaded();
    await AccessCodeService.instance.ensureLoaded();
    return _LaunchState(
      signedIn: AuthService.instance.isSignedIn,
      accessGranted: AccessCodeService.instance.hasAccessCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFC45F2A),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFFC45F2A),
      secondary: const Color(0xFF718168),
    );

    return MaterialApp(
      title: 'Nutri-Flow',
      debugShowCheckedModeBanner: false,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withAlpha(228),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: const TextStyle(color: Color(0xFF7A6A5D)),
          hintStyle: const TextStyle(color: Color(0xFFAD9A8A)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8D7CA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8D7CA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFC45F2A), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFFC45F2A),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle:
                const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: const Color(0xFF8B4D2A),
            side: const BorderSide(color: Color(0xFFD7B8A3)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: Colors.white.withAlpha(140),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFFFF1E7),
          selectedColor: const Color(0xFFF5D4BB),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: Color(0xFFF0D2BD)),
          labelStyle: const TextStyle(
              color: Color(0xFF6A4A34), fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEEDFD3),
          thickness: 1,
        ),
        useMaterial3: true,
      ),
      routes: {
        RoutePaths.auth: (_) => const AuthPage(),
        RoutePaths.home: (_) => const HomePage(),
        RoutePaths.upload: (_) => const UploadPage(),
        RoutePaths.profile: (_) => const ProfilePage(),
        RoutePaths.goals: (_) => const GoalSettingsPage(),
        RoutePaths.history: (_) => const HistoryPage(),
      },
      home: FutureBuilder<_LaunchState>(
        future: _loadLaunchState(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final state = snapshot.data!;
          if (!state.accessGranted) {
            return AccessGatePage(
              onGranted: () {
                final destination =
                    state.signedIn ? const HomePage() : const AuthPage();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => destination),
                );
              },
            );
          }
          if (!state.signedIn) {
            return const AuthPage();
          }
          return const HomePage();
        },
      ),
    );
  }
}

class _LaunchState {
  const _LaunchState({
    required this.signedIn,
    required this.accessGranted,
  });

  final bool signedIn;
  final bool accessGranted;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = AuthService.instance.currentPhone;

    void onStart() => Navigator.pushNamed(context, RoutePaths.upload);

    void onProfile() => Navigator.pushNamed(context, RoutePaths.profile);

    void onGoals() => Navigator.pushNamed(context, RoutePaths.goals);

    void onHistory() => Navigator.pushNamed(context, RoutePaths.history);

    return Scaffold(
      appBar: AppBar(
        title: const Text('灵动食迹 Nutri-Flow'),
        actions: [
          IconButton(
            tooltip: '个人主页',
            onPressed: onProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: _HomeHeroCard(
          phone: phone,
          onStart: onStart,
          onGoals: onGoals,
          onHistory: onHistory,
        ),
      ),
    );
  }
}

class _HomeHeroCard extends StatelessWidget {
  const _HomeHeroCard({
    required this.phone,
    required this.onStart,
    required this.onGoals,
    required this.onHistory,
  });

  final String? phone;
  final VoidCallback onStart;
  final VoidCallback onGoals;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final displayPhone = phone != null && phone!.isNotEmpty ? phone! : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF934F27),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F8B4D2A),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _HomeHeroChip(
                icon: Icons.auto_awesome_rounded,
                label: 'AI 餐食助手',
              ),
              if (displayPhone != null)
                _HomeHeroChip(
                  icon: Icons.verified_user_outlined,
                  label: displayPhone,
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '拍一餐，快速看懂\n这一餐吃了什么',
            style: TextStyle(
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: Color(0xFFFFFAF6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '上传清晰餐图，快速获得热量估算和更贴合目标的饮食建议。',
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Colors.white.withAlpha(230),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFF4EA),
              foregroundColor: const Color(0xFF6A3514),
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('开始分析'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HomeHeroActionButton(
                  icon: Icons.flag_rounded,
                  label: '目标设置',
                  onTap: onGoals,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomeHeroActionButton(
                  icon: Icons.history_rounded,
                  label: '历史记录',
                  onTap: onHistory,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeHeroChip extends StatelessWidget {
  const _HomeHeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(54)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(242),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeroActionButton extends StatelessWidget {
  const _HomeHeroActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withAlpha(16),
        side: BorderSide(color: Colors.white.withAlpha(82)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
