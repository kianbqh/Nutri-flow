import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _nicknameController = TextEditingController();

  bool _loading = false;
  bool _savingNickname = false;
  bool _editingNickname = false;
  String? _error;
  int? _userId;
  String? _phone;
  String? _nickname;
  String _healthGoal = 'GENERAL_HEALTH';
  int _dailyTarget = 2000;
  final Set<String> _restrictions = {};
  int? _heightCm;
  double? _weightKg;
  String? _gender;

  static const Map<String, String> _goalZh = {
    'WEIGHT_LOSS': '减脂',
    'MUSCLE_GAIN': '增肌',
    'MAINTENANCE': '维持',
    'GENERAL_HEALTH': '综合健康',
  };

  static const Map<String, String> _restrictionZh = {
    'high_sugar': '控糖',
    'spicy': '少辣',
    'dairy': '乳制品限制',
    'lactose': '乳糖不耐',
    'gluten': '麸质限制',
    'seafood': '海鲜限制',
    'nuts': '坚果过敏',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  String get _displayNickname {
    final nickname = (_editingNickname ? _nicknameController.text : (_nickname ?? '')).trim();
    if (nickname.isNotEmpty) {
      return nickname;
    }

    final phone = (_phone ?? '').trim();
    if (phone.length >= 4) {
      return '食迹用户${phone.substring(phone.length - 4)}';
    }

    if (_userId != null) {
      return '食迹用户${_userId.toString().padLeft(2, '0')}';
    }

    return '食迹用户';
  }

  String get _accountCaption {
    final phone = (_phone ?? '').trim();
    if (phone.length >= 7) {
      return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
    }
    return phone.isNotEmpty ? phone : '暂未读取到手机号';
  }

  String get _nicknameActionLabel => ((_nickname ?? '').trim().isEmpty ? '设置昵称' : '修改昵称');

  String get _goalLabel => _goalZh[_healthGoal] ?? '综合健康';

  String get _restrictionLabel {
    if (_restrictions.isEmpty) {
      return '暂未设置';
    }
    return _restrictions.map((item) => _restrictionZh[item] ?? item).join('、');
  }

  String get _bodyStatsLabel {
    final parts = <String>[];
    if (_heightCm != null) {
      parts.add('身高 $_heightCm cm');
    }
    if (_weightKg != null) {
      parts.add('体重 ${_weightKg!.toStringAsFixed(1)} kg');
    }
    if ((_gender ?? '').isNotEmpty) {
      parts.add(_gender == 'MALE' ? '男' : '女');
    }
    return parts.isEmpty ? '还没有补充基础身体信息' : parts.join(' / ');
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.ensureLoaded();
      final UserProfile profile = await ApiService.instance.getProfile();
      setState(() {
        _userId = profile.userId > 0 ? profile.userId : AuthService.instance.currentUserId;
        _phone = (profile.phone != null && profile.phone!.trim().isNotEmpty)
            ? profile.phone
            : AuthService.instance.currentPhone;
        _nickname = profile.nickname;
        _nicknameController.text = profile.nickname ?? '';
        _healthGoal = profile.healthGoal;
        _dailyTarget = profile.dailyCalorieTarget;
        _restrictions
          ..clear()
          ..addAll(profile.dietaryRestrictions);
        _heightCm = profile.heightCm;
        _weightKg = profile.weightKg;
        _gender = profile.gender?.toUpperCase();
      });
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '加载个人主页'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveNickname() async {
    setState(() {
      _savingNickname = true;
      _error = null;
    });

    try {
      final UserProfile profile = await ApiService.instance.updateProfile(
        nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        healthGoal: _healthGoal,
        dailyCalorieTarget: _dailyTarget,
        restrictions: _restrictions.toList(),
        heightCm: _heightCm,
        weightKg: _weightKg,
        gender: _gender,
      );
      setState(() {
        _nickname = profile.nickname;
        _nicknameController.text = profile.nickname ?? '';
        _editingNickname = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('昵称已保存')));
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '保存昵称'));
    } finally {
      setState(() => _savingNickname = false);
    }
  }

  void _startEditNickname() {
    setState(() {
      _nicknameController.text = _nickname ?? '';
      _editingNickname = true;
      _error = null;
    });
  }

  void _cancelEditNickname() {
    setState(() {
      _nicknameController.text = _nickname ?? '';
      _editingNickname = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人主页'),
        leading: const SafeBackButton(),
      ),
      body: _loading
          ? const AppSoftBackground(child: Center(child: CircularProgressIndicator()))
          : AppSoftBackground(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  AppHeroCard(
                    icon: Icons.account_circle_rounded,
                    title: '个人主页',
                    subtitle: '这里查看账号信息和主页称呼，也可以随时继续完善你的目标与饮食习惯。',
                    badges: [
                      if ((_phone ?? '').trim().isNotEmpty)
                        AppGlassChip(icon: Icons.phone_iphone_rounded, label: _accountCaption),
                      if (_userId != null) AppGlassChip(icon: Icons.pin_outlined, label: 'ID #$_userId'),
                    ],
                    footer: const AppHintStrip(
                      icon: Icons.person_outline_rounded,
                      text: '你可以随时修改昵称，让主页里的称呼更符合自己的习惯。',
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppSectionHeading(
                          title: '账号与昵称',
                          subtitle: '这里处理“我是哪个账号”和“个人主页怎么显示我的名称”。',
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7F0),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF1DDD0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayNickname,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2F2722),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _accountCaption,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  color: Color(0xFF7A6A5D),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_userId != null) Chip(label: Text('用户 ID #$_userId')),
                                  Chip(label: Text((_phone ?? '').trim().isNotEmpty ? '手机号 $_accountCaption' : '手机号未读取')),
                                  Chip(label: Text(((_nickname ?? '').trim().isEmpty) ? '当前使用默认昵称' : '已设置昵称')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (!_editingNickname) ...[
                          OutlinedButton.icon(
                            onPressed: _savingNickname ? null : _startEditNickname,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(_nicknameActionLabel),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '未手动设置昵称时，系统会继续显示默认昵称。',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF7A6A5D)),
                          ),
                        ],
                        if (_editingNickname) ...[
                          TextField(
                            controller: _nicknameController,
                            maxLength: 24,
                            decoration: InputDecoration(
                              labelText: '昵称',
                              hintText: '未设置时会显示为 $_displayNickname',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _savingNickname ? null : _saveNickname,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(_savingNickname ? '保存中...' : '保存昵称'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _savingNickname ? null : _cancelEditNickname,
                                  child: const Text('取消'),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppSectionHeading(
                          title: '当前设置概览',
                          subtitle: '个人主页只做查看和昵称维护，目标与基础信息编辑请去单独的目标设置页。',
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _ProfileOverviewTile(
                              title: '当前目标',
                              value: _goalLabel,
                              detail: '每日目标 $_dailyTarget 千卡',
                            ),
                            _ProfileOverviewTile(
                              title: '饮食限制',
                              value: _restrictionLabel,
                              detail: _restrictions.isEmpty ? '还没有添加限制标签' : '可在目标设置页继续调整',
                            ),
                            _ProfileOverviewTile(
                              title: '身体信息',
                              value: _bodyStatsLabel,
                              detail: '目标解析会参考这些基础信息',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => Navigator.pushNamed(context, RoutePaths.goals),
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('前往目标设置页'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pushNamed(context, RoutePaths.history),
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('查看历史记录'),
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

class _ProfileOverviewTile extends StatelessWidget {
  const _ProfileOverviewTile({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1DDD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A6A5D),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F2722),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF7A6A5D),
            ),
          ),
        ],
      ),
    );
  }
}
