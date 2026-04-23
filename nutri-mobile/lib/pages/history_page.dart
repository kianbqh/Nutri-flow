import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(result: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载详情失败：$e')),
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
      setState(() => _error = '历史记录加载失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        leading: const BackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_items.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: Text('暂无历史记录')),
                    ),
                  ..._items.map((e) => Card(
                        child: ListTile(
                          onTap: _opening ? null : () => _openHistoryDetail(e),
                          title: Text('${_mealZh[e.mealType] ?? e.mealType} · ${_statusZh[e.status] ?? e.status}'),
                          subtitle: Text('识别项：${e.detectedItemsCount}  时间：${_formatTime(e.loggedAt)}'),
                          isThreeLine: e.adviceReport != null,
                          trailing: _opening
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.chevron_right),
                        ),
                      )),
                ],
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
