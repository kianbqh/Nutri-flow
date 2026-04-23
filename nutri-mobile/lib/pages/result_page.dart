import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../widgets/status_banner.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    this.imageBytes,
    required this.result,
  });

  final Uint8List? imageBytes;
  final AnalysisResult result;

  static const Map<String, String> _labelZh = {
    'rice': '米饭',
    'noodles': '面条',
    'chicken': '鸡肉',
    'beef': '牛肉',
    'pork': '猪肉',
    'fish': '鱼肉',
    'tofu': '豆腐',
    'broccoli': '西兰花',
    'carrot': '胡萝卜',
  };

  @override
  Widget build(BuildContext context) {
    final level = _calorieLevel(result.totalCalories);
    return Scaffold(
      appBar: AppBar(
        title: const Text('分析结果'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(imageBytes!, height: 220, fit: BoxFit.cover),
            )
          else
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(child: Text('图片预览不可用')),
            ),
          const SizedBox(height: 14),
          Text(
            '总热量：${result.totalCalories.toStringAsFixed(1)} 千卡',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          StatusBanner(status: result.status, message: result.errorMessage),
          if (result.workflowMode != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('工作流：${result.workflowMode}')),
                Chip(
                  label: Text(
                    result.workflowMode == 'CALORIE_ONLY' ? '降级输出' : '完整分析',
                  ),
                ),
              ],
            ),
          ],
          if (result.kcalRange != null) ...[
            const SizedBox(height: 4),
            Text(
              '估算区间：${result.kcalRange![0].toStringAsFixed(1)} - ${result.kcalRange![1].toStringAsFixed(1)} 千卡',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
          if (result.confidenceLevel != null) ...[
            const SizedBox(height: 2),
            Text('置信等级：${result.confidenceLevel}'),
          ],
          const SizedBox(height: 6),
          Text(
            '本餐判断：${level.label}（${level.description}）',
            style: TextStyle(
              fontSize: 15,
              color: level.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (result.workflowTrace.isNotEmpty) ...[
            const Text('工作流路径', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.workflowTrace
                    .map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $step'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: const Text('提示：热量与营养均为估算值，仅供饮食管理参考。'),
          ),
          const SizedBox(height: 12),
          const Text('识别明细', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (result.detectedItems.isEmpty)
            const Text('暂未识别到明确食物，请尝试更清晰的图片')
          else
            ...result.detectedItems.map((e) {
              final rawName = e.displayName.isNotEmpty
                  ? e.displayName
                  : (e.className.isNotEmpty ? e.className : e.label);
              final name = _labelZh[rawName] ?? rawName;
              return Card(
                child: ListTile(
                  onTap: () => _showItemDetail(context, e, name),
                  title: Text(name),
                  subtitle: Text('置信度 ${(e.confidence * 100).toStringAsFixed(1)}%'),
                  trailing: Text(
                    e.calories == null
                        ? '热量估算中'
                        : '${e.calories!.toStringAsFixed(1)} 千卡',
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          const Text('AI 建议', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              result.adviceReport.trim().isEmpty ? '暂无建议' : result.adviceReport,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.upload),
            label: const Text('返回继续上传'),
          ),
        ],
      ),
    );
  }

  _CalorieLevel _calorieLevel(double total) {
    if (total < 350) {
      return const _CalorieLevel('轻负担', '适合大多数控量场景', Colors.green);
    }
    if (total < 700) {
      return const _CalorieLevel('一般', '正常一餐范围', Colors.orange);
    }
    return const _CalorieLevel('偏高', '建议下一餐清淡一点', Colors.red);
  }

  void _showItemDetail(BuildContext context, DetectedItem item, String name) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('热量：${item.calories?.toStringAsFixed(1) ?? '-'} 千卡'),
              Text('估算重量：${item.estimatedWeightG?.toStringAsFixed(1) ?? '-'} g'),
              Text('蛋白质：${item.proteinG?.toStringAsFixed(1) ?? '-'} g'),
              Text('脂肪：${item.fatG?.toStringAsFixed(1) ?? '-'} g'),
              Text('碳水：${item.carbsG?.toStringAsFixed(1) ?? '-'} g'),
              const SizedBox(height: 6),
              Text('置信度：${(item.confidence * 100).toStringAsFixed(1)}%'),
              if (item.bbox != null && item.bbox!.isNotEmpty)
                Text('定位框：${item.bbox!.map((e) => e.toStringAsFixed(1)).join(', ')}'),
              const SizedBox(height: 12),
              const Text('结果为估算值，仅供参考。', style: TextStyle(color: Colors.black54)),
            ],
          ),
        );
      },
    );
  }
}

class _CalorieLevel {
  const _CalorieLevel(this.label, this.description, this.color);

  final String label;
  final String description;
  final Color color;
}
