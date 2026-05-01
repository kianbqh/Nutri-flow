import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';
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
  static const int _slowWarningSeconds = 90;
  static const int _timeoutSeconds = 300;
  static const Duration _pollInterval = Duration(seconds: 1);

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
          _errorMessage = '这次等待时间有些长，你可以重试或稍后再看结果。';
          _finished = true;
        });
        timer.cancel();
        return;
      }

      if (_elapsed >= _slowWarningSeconds && _status == 'PENDING' && _errorMessage == null) {
        setState(() {
          _errorMessage = '图片较复杂时可能会稍久一些，系统仍在继续计算中。';
        });
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
          _errorMessage = ApiService.describeError(e, action: '状态查询');
          _finished = true;
        });
        timer.cancel();
      }
    });
  }

  String _statusText() {
    switch (_status) {
      case 'COMPLETED':
        return '分析完成，正在为你打开结果...';
      case 'FAILED':
        return '这次分析没有顺利完成';
      case 'TIMEOUT':
        return '等待时间较长';
      default:
        return '正在识别餐食并估算热量';
    }
  }

  String _progressHint() {
    switch (_status) {
      case 'COMPLETED':
        return '结果已经准备好，马上进入详情页。';
      case 'FAILED':
      case 'TIMEOUT':
        return '如果网络较慢或图片较复杂，可以稍后再试一次。';
      default:
        if (_elapsed < 20) {
          return '通常约 10-20 秒完成图片识别、热量计算和建议生成。';
        }
        return '这次分析比平时稍久一些，请再等待片刻。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRetry = _status == 'FAILED' || _status == 'TIMEOUT';

    return Scaffold(
      appBar: AppBar(title: const Text('分析处理中')),
      body: AppSoftBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            children: [
              const AppHeroCard(
                icon: Icons.auto_awesome_rounded,
                title: '正在分析这顿餐食',
                subtitle: '系统正在识别餐食区域、估算热量并生成建议，通常约 10-20 秒完成。',
              ),
              const SizedBox(height: 18),
              AppSurfaceCard(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _statusText(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _progressHint(),
                      style: const TextStyle(color: Color(0xFF7A6A5D), height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    StatusBanner(status: _status, message: _errorMessage),
                    const SizedBox(height: 18),
                    if (canRetry)
                      FilledButton.icon(
                        onPressed: _startPolling,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试查询'),
                      ),
                    if (canRetry) const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => backOrGo(context, fallbackRoute: RoutePaths.home),
                      child: const Text('返回首页'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
