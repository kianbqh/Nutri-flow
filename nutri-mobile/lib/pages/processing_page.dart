import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/status_banner.dart';
import 'result_page.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({
    super.key,
    required this.taskId,
    this.imageBytes,
  });

  final String taskId;
  final Uint8List? imageBytes;

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  static const int _timeoutSeconds = 90;
  static const Duration _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  int _elapsed = 0;
  String _status = 'PENDING';
  String? _errorMessage;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    _elapsed = 0;
    _finished = false;
    _status = 'PENDING';
    _errorMessage = null;

    _timer = Timer.periodic(_pollInterval, (timer) async {
      if (!mounted || _finished) return;

      _elapsed += _pollInterval.inSeconds;
      if (_elapsed >= _timeoutSeconds) {
        setState(() {
          _status = 'TIMEOUT';
          _errorMessage = '分析超时，可点击重试继续查询';
          _finished = true;
        });
        timer.cancel();
        return;
      }

      try {
        final result = await ApiService.instance.getTaskStatus(widget.taskId);
        if (!mounted) return;

        setState(() {
          _status = result.status;
          _errorMessage = result.errorMessage;
        });

        if (result.status == 'COMPLETED') {
          _finished = true;
          timer.cancel();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ResultPage(
                imageBytes: widget.imageBytes,
                result: result,
              ),
            ),
          );
          return;
        }

        if (result.status == 'FAILED') {
          setState(() => _finished = true);
          timer.cancel();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _status = 'FAILED';
          _errorMessage = '状态查询失败：$e';
          _finished = true;
        });
        timer.cancel();
      }
    });
  }

  String _statusText() {
    switch (_status) {
      case 'COMPLETED':
        return '分析完成，正在跳转结果页...';
      case 'FAILED':
        return '分析失败';
      case 'TIMEOUT':
        return '查询超时';
      default:
        return '正在分析，请稍候...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRetry = _status == 'FAILED' || _status == 'TIMEOUT';

    return Scaffold(
      appBar: AppBar(title: const Text('分析处理中')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
              const SizedBox(height: 20),
              Text(
                _statusText(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              StatusBanner(status: _status, message: _errorMessage),
              const SizedBox(height: 8),
              Text('任务号：${widget.taskId}', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('已等待 ${_elapsed}s', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              if (canRetry)
                FilledButton.icon(
                  onPressed: _startPolling,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试查询'),
                ),
              if (canRetry) const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
