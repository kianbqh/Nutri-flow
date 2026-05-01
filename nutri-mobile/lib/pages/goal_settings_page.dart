import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/profile_context_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';

class GoalSettingsPage extends StatefulWidget {
  const GoalSettingsPage({super.key});

  @override
  State<GoalSettingsPage> createState() => _GoalSettingsPageState();
}

class _GoalSettingsPageState extends State<GoalSettingsPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _assistantInput = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  bool _assistantBusy = false;
  bool _listening = false;
  String? _error;
  String? _assistantError;
  String? _assistantSummary;
  String? _phone;
  String? _nickname;

  String _healthGoal = 'WEIGHT_LOSS';
  int _dailyTarget = 1800;
  final Set<String> _restrictions = {};
  String _gender = 'FEMALE';
  String _activity = 'MEDIUM';

  static const List<_RestrictionOption> _restrictionOptions = [
    _RestrictionOption('high_sugar', '控糖'),
    _RestrictionOption('spicy', '少辣'),
    _RestrictionOption('dairy', '乳制品限制'),
    _RestrictionOption('lactose', '乳糖不耐'),
    _RestrictionOption('gluten', '麸质限制'),
    _RestrictionOption('seafood', '海鲜限制'),
    _RestrictionOption('nuts', '坚果过敏'),
  ];

  static const Map<String, String> _goalZh = {
    'WEIGHT_LOSS': '减脂',
    'MUSCLE_GAIN': '增肌',
    'MAINTENANCE': '维持',
    'GENERAL_HEALTH': '综合健康',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _assistantInput.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String get _displayNickname {
    final nickname = (_nickname ?? '').trim();
    if (nickname.isNotEmpty) {
      return nickname;
    }

    final phone = (_phone ?? '').trim();
    if (phone.length >= 4) {
      return '食迹用户${phone.substring(phone.length - 4)}';
    }

    return '食迹用户';
  }

  String get _assistantContextSummary {
    final parts = <String>[];
    final ageText = _ageController.text.trim();
    final heightText = _heightController.text.trim();
    final weightText = _weightController.text.trim();

    if (ageText.isNotEmpty) {
      parts.add('年龄 $ageText 岁');
    }
    if (heightText.isNotEmpty) {
      parts.add('身高 $heightText cm');
    }
    if (weightText.isNotEmpty) {
      parts.add('体重 $weightText kg');
    }
    parts.add('性别 ${_gender == 'MALE' ? '男' : '女'}');
    parts.add('活动量 ${switch (_activity) { 'LOW' => '低', 'HIGH' => '高', _ => '中' }}');

    return '当前解析会参考：${parts.join(' / ')}。你可以先语音说出目标，再往下微调。';
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.ensureLoaded();
      final UserProfile profile = await ApiService.instance.getProfile();
      final ProfileContextSnapshot snapshot = await ProfileContextService.instance.loadSnapshot();
      setState(() {
        _phone = (profile.phone != null && profile.phone!.trim().isNotEmpty)
            ? profile.phone
            : AuthService.instance.currentPhone;
        _nickname = profile.nickname;
        _healthGoal = profile.healthGoal;
        _dailyTarget = profile.dailyCalorieTarget;
        _restrictions
          ..clear()
          ..addAll(profile.dietaryRestrictions);
        _ageController.text = snapshot.age?.toString() ?? '';
        final int? heightCm = profile.heightCm ?? snapshot.heightCm;
        final double? weightKg = profile.weightKg ?? snapshot.weightKg;
        final String gender = (profile.gender ?? snapshot.gender ?? '').toUpperCase();
        final String activity = (snapshot.activityLevel ?? '').toUpperCase();
        _heightController.text = heightCm?.toString() ?? '';
        _weightController.text = weightKg?.toStringAsFixed(1) ?? '';
        if (gender == 'MALE' || gender == 'FEMALE') {
          _gender = gender;
        }
        if (activity == 'LOW' || activity == 'MEDIUM' || activity == 'HIGH') {
          _activity = activity;
        }
      });
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '加载目标设置'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final UserProfile profile = await ApiService.instance.updateProfile(
        nickname: (_nickname ?? '').trim().isEmpty ? null : _nickname!.trim(),
        healthGoal: _healthGoal,
        dailyCalorieTarget: _dailyTarget,
        restrictions: _restrictions.toList(),
        heightCm: int.tryParse(_heightController.text.trim()),
        weightKg: double.tryParse(_weightController.text.trim()),
        gender: _gender,
      );
      await ProfileContextService.instance.saveSnapshot(
        ProfileContextSnapshot(
          age: int.tryParse(_ageController.text.trim()),
          heightCm: int.tryParse(_heightController.text.trim()),
          weightKg: double.tryParse(_weightController.text.trim()),
          gender: _gender,
          activityLevel: _activity,
        ),
      );
      setState(() {
        _phone = profile.phone ?? _phone;
        _nickname = profile.nickname;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('目标设置已保存')));
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '保存目标设置'));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    final bool available = await _speech.initialize();
    if (!available) {
      setState(() => _assistantError = '当前设备不支持语音识别');
      return;
    }

    setState(() {
      _assistantError = null;
      _listening = true;
    });
    await _speech.listen(onResult: (result) {
      setState(() {
        _assistantInput.text = result.recognizedWords;
      });
    });
  }

  Future<void> _useAssistant({required bool apply}) async {
    if (_assistantInput.text.trim().isEmpty) {
      setState(() => _assistantError = '请先输入或语音描述你的目标');
      return;
    }

    setState(() {
      _assistantBusy = true;
      _assistantError = null;
      _assistantSummary = null;
    });

    try {
      final Map<String, dynamic> parsed = await ApiService.instance.parseGoalByAssistant(
        rawText: _assistantInput.text.trim(),
        age: int.tryParse(_ageController.text.trim()),
        heightCm: int.tryParse(_heightController.text.trim()),
        weightKg: double.tryParse(_weightController.text.trim()),
        gender: _gender,
        activityLevel: _activity,
        applyToProfile: apply,
      );

      setState(() {
        _healthGoal = (parsed['healthGoal'] ?? _healthGoal).toString();
        _dailyTarget = (parsed['dailyCalorieTarget'] ?? _dailyTarget) as int;
        _restrictions
          ..clear()
          ..addAll(((parsed['dietaryRestrictions'] ?? []) as List).map((item) => item.toString()));
        _assistantSummary = (parsed['summary'] ?? '').toString();
      });

      if (apply) {
        await ProfileContextService.instance.saveSnapshot(
          ProfileContextSnapshot(
            age: int.tryParse(_ageController.text.trim()),
            heightCm: int.tryParse(_heightController.text.trim()),
            weightKg: double.tryParse(_weightController.text.trim()),
            gender: _gender,
            activityLevel: _activity,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已应用到当前目标')));
      }
    } catch (e) {
      setState(() => _assistantError = ApiService.describeError(e, action: '助手解析'));
    } finally {
      setState(() => _assistantBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool pageBusy = _saving || _assistantBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('目标设置'),
        leading: const SafeBackButton(),
      ),
      body: _loading
          ? const AppSoftBackground(child: Center(child: CircularProgressIndicator()))
          : AppSoftBackground(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  AppHeroCard(
                    icon: Icons.flag_rounded,
                    title: '目标设置',
                    subtitle: '先说出你的目标，再微调基础信息、热量与饮食限制，让建议更贴近你的实际状态。',
                    badges: [
                      if ((_phone ?? '').trim().isNotEmpty)
                        AppGlassChip(icon: Icons.phone_iphone_rounded, label: _phone!),
                      AppGlassChip(icon: Icons.person_outline_rounded, label: _displayNickname),
                    ],
                    footer: const AppHintStrip(
                      icon: Icons.mic_rounded,
                      text: '先说说你最近想调整的方向，系统会先帮你整理一版建议。',
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppSectionHeading(
                          title: '先说你的目标',
                          subtitle: '优先使用语音或一句话描述，让系统先帮你整理方向。',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: pageBusy ? null : _toggleVoice,
                          icon: Icon(_listening ? Icons.mic_off_rounded : Icons.mic_rounded),
                          label: Text(_listening ? '停止语音输入' : '语音输入目标'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _assistantInput,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '目标描述',
                            hintText: '例如：我想减脂，乳糖不耐受，每周运动 3 次，帮我设目标',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7F0),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFF1DDD0)),
                          ),
                          child: Text(
                            _assistantContextSummary,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.55,
                              color: Color(0xFF7A6A5D),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: pageBusy ? null : () => _useAssistant(apply: false),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text(_assistantBusy ? '生成中...' : '先看建议'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: pageBusy ? null : () => _useAssistant(apply: true),
                                icon: const Icon(Icons.auto_fix_high_rounded),
                                label: const Text('应用到目标'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '先看看建议，合适的话再一键应用到当前目标。',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF7A6A5D)),
                        ),
                        if (_assistantSummary != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade100),
                            ),
                            child: Text(_assistantSummary!),
                          ),
                        ],
                        if (_assistantError != null) ...[
                          const SizedBox(height: 10),
                          Text(_assistantError!, style: const TextStyle(color: Colors.red)),
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
                          title: '手动调整设置',
                          subtitle: '如果你想更精确控制目标，可以直接修改基础信息、热量和饮食限制。',
                        ),
                        const SizedBox(height: 16),
                        _GoalSettingsBlock(
                          title: '基础信息',
                          subtitle: '年龄、身高、体重、性别和活动水平会作为后续分析上下文。',
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _ageController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: '年龄（可选）'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _heightController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: '身高 cm（可选）'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _weightController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: '体重 kg（可选）'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      key: ValueKey('gender-$_gender'),
                                      initialValue: _gender,
                                      decoration: const InputDecoration(labelText: '性别'),
                                      items: const [
                                        DropdownMenuItem(value: 'MALE', child: Text('男')),
                                        DropdownMenuItem(value: 'FEMALE', child: Text('女')),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() => _gender = value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey('activity-$_activity'),
                                initialValue: _activity,
                                decoration: const InputDecoration(labelText: '活动水平'),
                                items: const [
                                  DropdownMenuItem(value: 'LOW', child: Text('活动量低')),
                                  DropdownMenuItem(value: 'MEDIUM', child: Text('活动量中')),
                                  DropdownMenuItem(value: 'HIGH', child: Text('活动量高')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _activity = value);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _GoalSettingsBlock(
                          title: '目标与限制',
                          subtitle: '这里决定系统应该优先按什么方向给建议。',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey('goal-$_healthGoal'),
                                initialValue: _healthGoal,
                                decoration: const InputDecoration(labelText: '健康目标'),
                                items: _goalZh.entries
                                    .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _healthGoal = value);
                                },
                              ),
                              const SizedBox(height: 14),
                              Slider(
                                value: _dailyTarget.toDouble(),
                                min: 1200,
                                max: 3200,
                                divisions: 40,
                                label: '$_dailyTarget 千卡',
                                onChanged: (value) => setState(() => _dailyTarget = value.round()),
                              ),
                              Text(
                                '每日目标：$_dailyTarget 千卡',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                              const Text('饮食限制（可多选）', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _restrictionOptions.map((option) {
                                  final bool selected = _restrictions.contains(option.code);
                                  return FilterChip(
                                    selected: selected,
                                    label: Text(option.label),
                                    onSelected: (checked) {
                                      setState(() {
                                        if (checked) {
                                          _restrictions.add(option.code);
                                        } else {
                                          _restrictions.remove(option.code);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: pageBusy ? null : _saveSettings,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? '保存中...' : '保存本页目标设置'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本页的基础信息、目标和饮食限制会一起保存，后续分析会优先参考这里。',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF7A6A5D)),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _GoalSettingsBlock extends StatelessWidget {
  const _GoalSettingsBlock({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1DDD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F2722),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF7A6A5D),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RestrictionOption {
  const _RestrictionOption(this.code, this.label);

  final String code;
  final String label;
}
