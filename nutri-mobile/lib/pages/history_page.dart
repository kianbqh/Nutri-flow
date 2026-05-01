import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';
import 'result_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loading = false;
  bool _opening = false;
  String? _error;
  List<HistoryItem> _items = [];

  static const Map<String, String> _mealZh = {
    'BREAKFAST': '早餐',
    'LUNCH': '午餐',
    'DINNER': '晚餐',
    'SNACK': '加餐',
  };

  static const Map<String, String> _statusZh = {
    'PENDING': '分析中',
    'COMPLETED': '已完成',
    'FAILED': '失败',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openHistoryDetail(HistoryItem item) async {
    if (_opening) return;

    setState(() => _opening = true);
    try {
      final result = await ApiService.instance.getTaskStatus(item.taskId);
      if (!mounted) return;

      if (result.status != 'COMPLETED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前任务状态：${_statusZh[result.status] ?? result.status}')),
        );
        return;
      }

      Uint8List? imageBytes;
      try {
        imageBytes = await ApiService.instance.getTaskImageBytes(item.taskId);
      } catch (_) {
        imageBytes = null;
      }
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            imageBytes: imageBytes,
            result: result,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.describeError(e, action: '加载详情'))),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.getHistory();
      setState(() => _items = data);
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '历史记录加载'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildHistoryCard(HistoryItem item) {
    return GestureDetector(
      onTap: _opening ? null : () => _openHistoryDetail(item),
      child: AppSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1E7),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFB86A3D)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_mealZh[item.mealType] ?? item.mealType} · ${_statusZh[item.status] ?? item.status}',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '识别项：${item.detectedItemsCount}  时间：${_formatTime(item.loggedAt)}',
                    style: const TextStyle(color: Color(0xFF706258), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _opening
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded, color: Color(0xFFB86A3D)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        leading: const SafeBackButton(),
      ),
      body: _loading
          ? const AppSoftBackground(child: Center(child: CircularProgressIndicator()))
          : AppSoftBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    const AppHeroCard(
                      icon: Icons.history_rounded,
                      title: '回看你的饮食记录',
                      subtitle: '这里会保留每次分析结果，方便你回顾热量和饮食结构变化。',
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      AppSurfaceCard(
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_items.isEmpty && _error == null)
                      const AppSurfaceCard(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('暂无历史记录，先去拍一餐吧。'),
                          ),
                        ),
                      ),
                    ..._items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildHistoryCard(item),
                        )),
                  ],
                ),
              ),
            ),
    );
  }

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
