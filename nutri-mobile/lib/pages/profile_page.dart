import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_models.dart';
import '../services/api_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _assistantInput = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  bool _listening = false;
  String? _error;
  String? _assistantSummary;

  String _healthGoal = 'WEIGHT_LOSS';
  int _dailyTarget = 1800;
  final Set<String> _restrictions = {};

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
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
    _loadProfile();
  }

  @override
  void dispose() {
    _assistantInput.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final UserProfile p = await ApiService.instance.getProfile();
      setState(() {
        _healthGoal = p.healthGoal;
        _dailyTarget = p.dailyCalorieTarget;
        _restrictions
          ..clear()
          ..addAll(p.dietaryRestrictions);
      });
    } catch (e) {
      setState(() => _error = '加载目标失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiService.instance.updateProfile(
        healthGoal: _healthGoal,
        dailyCalorieTarget: _dailyTarget,
        restrictions: _restrictions.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
    } catch (e) {
      setState(() => _error = '保存失败：$e');
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

    final available = await _speech.initialize();
    if (!available) {
      setState(() => _error = '当前设备不支持语音识别');
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(onResult: (result) {
      setState(() {
        _assistantInput.text = result.recognizedWords;
      });
    });
  }

  Future<void> _useAssistant({required bool apply}) async {
    if (_assistantInput.text.trim().isEmpty) {
      setState(() => _error = '请先输入或语音描述你的目标');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _assistantSummary = null;
    });

    try {
      final parsed = await ApiService.instance.parseGoalByAssistant(
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
          ..addAll(((parsed['dietaryRestrictions'] ?? []) as List).map((e) => e.toString()));
        _assistantSummary = (parsed['summary'] ?? '').toString();
      });

      if (apply) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已应用到目标设置')));
      }
    } catch (e) {
      setState(() => _error = '助手解析失败：$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的目标'),
        leading: const BackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('目标设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _healthGoal,
                  decoration: const InputDecoration(labelText: '健康目标'),
                  items: _goalZh.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _healthGoal = v);
                  },
                ),
                const SizedBox(height: 10),
                Slider(
                  value: _dailyTarget.toDouble(),
                  min: 1200,
                  max: 3200,
                  divisions: 40,
                  label: '$_dailyTarget 千卡',
                  onChanged: (v) => setState(() => _dailyTarget = v.round()),
                ),
                Text('每日目标：$_dailyTarget 千卡'),
                const SizedBox(height: 10),
                const Text('饮食限制（可多选）'),
                Wrap(
                  spacing: 8,
                  children: _restrictionOptions.map((opt) {
                    final selected = _restrictions.contains(opt.code);
                    return FilterChip(
                      selected: selected,
                      label: Text(opt.label),
                      onSelected: (ok) {
                        setState(() {
                          if (ok) {
                            _restrictions.add(opt.code);
                          } else {
                            _restrictions.remove(opt.code);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: Text(_saving ? '保存中...' : '保存设置'),
                ),
                const Divider(height: 28),
                const Text('目标助手（文本/语音）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _assistantInput,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '例如：我想减脂，乳糖不耐受，每周运动3次，帮我设目标',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _toggleVoice,
                        icon: Icon(_listening ? Icons.mic_off : Icons.mic),
                        label: Text(_listening ? '停止语音' : '语音输入'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                        decoration: const InputDecoration(labelText: '身高cm（可选）'),
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
                        decoration: const InputDecoration(labelText: '体重kg（可选）'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        items: const [
                          DropdownMenuItem(value: 'MALE', child: Text('男')),
                          DropdownMenuItem(value: 'FEMALE', child: Text('女')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _gender = v);
                        },
                        decoration: const InputDecoration(labelText: '性别'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _activity,
                  items: const [
                    DropdownMenuItem(value: 'LOW', child: Text('活动量低')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('活动量中')),
                    DropdownMenuItem(value: 'HIGH', child: Text('活动量高')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _activity = v);
                  },
                  decoration: const InputDecoration(labelText: '活动水平'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _useAssistant(apply: false),
                        child: const Text('先解析看看'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : () => _useAssistant(apply: true),
                        child: const Text('解析并应用'),
                      ),
                    ),
                  ],
                ),
                if (_assistantSummary != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_assistantSummary!),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
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
