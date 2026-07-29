import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';
import '../widgets/status_banner.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    this.imageBytes,
    required this.result,
  });

  final Uint8List? imageBytes;
  final AnalysisResult result;

  static const int _defaultVisibleItemCount = 5;
  static const int _defaultOverlayItemCount = 5;
  static const double _adviceConfidenceThreshold = 0.65;

  static const Map<String, String> _labelZh = {
    'background': '背景',
    'candy': '糖果',
    'egg tart': '蛋挞',
    'french fries': '炸薯条',
    'chocolate': '巧克力',
    'biscuit': '饼干',
    'popcorn': '爆米花',
    'pudding': '布丁',
    'ice cream': '冰淇淋',
    'cheese butter': '奶酪黄油',
    'cake': '蛋糕',
    'wine': '葡萄酒',
    'milkshake': '奶昔',
    'coffee': '咖啡',
    'juice': '果汁',
    'milk': '牛奶',
    'tea': '茶',
    'almond': '杏仁',
    'red beans': '红豆',
    'cashew': '腰果',
    'dried cranberries': '蔓越莓干',
    'soy': '黄豆',
    'walnut': '核桃',
    'peanut': '花生',
    'egg': '鸡蛋',
    'apple': '苹果',
    'date': '枣',
    'apricot': '杏子',
    'avocado': '牛油果',
    'banana': '香蕉',
    'strawberry': '草莓',
    'cherry': '樱桃',
    'blueberry': '蓝莓',
    'raspberry': '树莓',
    'mango': '芒果',
    'olives': '橄榄',
    'peach': '桃子',
    'lemon': '柠檬',
    'pear': '梨',
    'fig': '无花果',
    'pineapple': '菠萝',
    'grape': '葡萄',
    'kiwi': '猕猴桃',
    'melon': '甜瓜',
    'orange': '橙子',
    'watermelon': '西瓜',
    'steak': '牛排',
    'pork': '猪肉',
    'chicken duck': '鸡鸭肉',
    'sausage': '香肠',
    'fried meat': '炸肉',
    'lamb': '羊肉',
    'sauce': '酱料',
    'crab': '螃蟹',
    'fish': '鱼',
    'shellfish': '贝类',
    'shrimp': '虾',
    'soup': '汤',
    'bread': '面包',
    'corn': '玉米',
    'hamburg': '汉堡',
    'pizza': '披萨',
    'hanamaki baozi': '花卷包子',
    'wonton dumplings': '馄饨饺子',
    'pasta': '意面',
    'noodles': '面条',
    'rice': '米饭',
    'pie': '馅饼',
    'tofu': '豆腐',
    'eggplant': '茄子',
    'potato': '土豆',
    'garlic': '大蒜',
    'cauliflower': '菜花',
    'tomato': '番茄',
    'kelp': '海带',
    'seaweed': '海苔',
    'spring onion': '葱',
    'rape': '油菜',
    'ginger': '姜',
    'okra': '秋葵',
    'lettuce': '生菜',
    'pumpkin': '南瓜',
    'cucumber': '黄瓜',
    'white radish': '白萝卜',
    'carrot': '胡萝卜',
    'asparagus': '芦笋',
    'bamboo shoots': '竹笋',
    'broccoli': '西兰花',
    'celery stick': '芹菜',
    'cilantro mint': '香菜薄荷',
    'snow peas': '荷兰豆',
    'cabbage': '卷心菜',
    'bean sprouts': '豆芽',
    'onion': '洋葱',
    'pepper': '辣椒',
    'green beans': '四季豆',
    'french beans': '菜豆',
    'king oyster mushroom': '杏鲍菇',
    'shiitake': '香菇',
    'enoki mushroom': '金针菇',
    'oyster mushroom': '平菇',
    'white button mushroom': '白蘑菇',
    'salad': '沙拉',
    'other ingredients': '其他配料',
  };

  @override
  Widget build(BuildContext context) {
    final adviceSections = _splitAdviceSections(result.adviceReport);
    final level = _calorieLevel(result.totalCalories);
    final allGroups = _sortedGroups(result.detectedItems);
    final visibleGroups = allGroups.take(_defaultVisibleItemCount).toList();
    final overlayGroups = allGroups.take(_defaultOverlayItemCount).toList();
    final hiddenGroups = allGroups.skip(_defaultVisibleItemCount).toList();
    Uint8List? segPreview;
    final rawPreview = result.segmentationPreviewPngBase64;
    if (rawPreview != null && rawPreview.isNotEmpty) {
      try {
        segPreview = base64Decode(rawPreview);
      } catch (_) {
        segPreview = null;
      }
    }
    final headerPreviewBytes = imageBytes ?? segPreview;
    // Keep the square preview as the mask-space reference image. The canvas will
    // render the original image inside the same square space so masks stay aligned
    // without showing the baked-in red preview as the default background.
    final interactiveBaseImage = segPreview ?? imageBytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分析结果'),
        leading: const SafeBackButton(),
      ),
      body: AppSoftBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (headerPreviewBytes != null)
                    _ResultImagePreview(imageBytes: headerPreviewBytes)
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
                  if (result.kcalRange != null) ...[
                    const SizedBox(height: 6),
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
                ],
              ),
            ),
          if (interactiveBaseImage != null && _hasInteractiveRegions(result.detectedItems)) ...[
            const SizedBox(height: 12),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(
                    title: '可点击分割区域',
                    subtitle: '保留轻量轮廓交互，你可以点击区域查看更细的食物明细。',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.auto_awesome_outlined, size: 16, color: Colors.teal.shade700),
                        label: const Text('轻量轮廓模式'),
                        side: BorderSide(color: Colors.teal.shade100),
                        backgroundColor: Colors.teal.shade50,
                        labelStyle: TextStyle(
                          color: Colors.teal.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.pan_tool_alt_outlined, size: 16, color: Colors.orange.shade700),
                        label: const Text('点击查看详情'),
                        side: BorderSide(color: Colors.orange.shade100),
                        backgroundColor: Colors.orange.shade50,
                        labelStyle: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InteractiveSegmentationCanvas(
                    overlayImageBytes: interactiveBaseImage,
                    originalImageBytes: imageBytes,
                    groups: overlayGroups,
                    onGroupTap: (group) => _showGroupDetail(context, group),
                  ),
                ],
              ),
            ),
          ] else if (segPreview != null) ...[
            const SizedBox(height: 12),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(
                    title: '分割预览图',
                    subtitle: '当交互分割不可用时，仍保留一张静态分割参考图。',
                  ),
                  const SizedBox(height: 8),
                  _ResultImagePreview(imageBytes: segPreview),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const AppSurfaceCard(
            color: Color(0xFFFFF6EF),
            child: Text(
              '提示：热量与营养为估算值，由识别面积与类别营养先验联合计算，仅供饮食管理参考。',
              style: TextStyle(height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          const Text('食物类型摘要', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (result.detectedItems.isEmpty)
            const Text('暂未识别到明确食物，请尝试更清晰的图片')
          else ...[
            Text(
                  '已合并为 ${allGroups.length} 类，共 ${result.detectedItems.length} 个区域；画布仅展示热量最高的 $_defaultOverlayItemCount 类主轮廓，其余类别可在下方摘要查看。',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            ..._buildVisibleGroups(context, visibleGroups),
            if (hiddenGroups.isNotEmpty) ...[
              Card(
                color: Colors.orange.shade50,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text('其余 ${hiddenGroups.length} 类已折叠'),
                  subtitle: Text('合计约 ${hiddenGroups.fold<double>(0, (s, g) => s + g.totalCalories).toStringAsFixed(1)} 千卡'),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4),
                title: Text('查看更多 ${hiddenGroups.length} 类'),
                children: hiddenGroups
                    .map(
                      (group) => Card(
                        child: ListTile(
                          onTap: () => _showGroupDetail(context, group),
                          title: Text(group.displayName),
                          subtitle: Text(_groupSubtitle(group)),
                          trailing: Text(
                            '${group.totalCalories.toStringAsFixed(1)} 千卡',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '当前类别数未超过 $_defaultVisibleItemCount 类，因此没有额外折叠项。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ],
          ],
          if (allGroups.any((group) => group.isLowConfidence)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF0D3AD)),
              ),
              child: const Text(
                '低于 65% 的类别仅作为待确认线索，不用于生成点名食物的具体建议。',
                style: TextStyle(
                  color: Color(0xFF80552C),
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeading(
                  title: '饮食建议',
                  subtitle: '会结合这餐识别结果、你的目标和近期饮食情况整理建议。',
                ),
                if (adviceSections.basis != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F1E7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8D6C2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '这次建议主要参考',
                          style: TextStyle(
                            color: Colors.brown.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          adviceSections.basis!,
                          style: TextStyle(
                            color: Colors.brown.shade700,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    adviceSections.body,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => backOrGo(context, fallbackRoute: RoutePaths.upload),
            icon: const Icon(Icons.upload),
            label: const Text('返回继续上传'),
          ),
        ],
      ),
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

  List<_FoodGroup> _sortedGroups(List<DetectedItem> items) {
    final grouped = <String, List<_SegmentInstance>>{};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final groupKey = _groupKey(item);
      final shape = item.maskShape;
      final maskBytes = _decodeMaskRle(item.maskRle, shape);
      final width = shape != null && shape.length >= 2 ? shape[1] : 0;
      final height = shape != null && shape.length >= 2 ? shape[0] : 0;
      grouped.putIfAbsent(groupKey, () => []).add(
            _SegmentInstance(
              index: i,
              item: item,
              maskBytes: maskBytes,
              maskWidth: width,
              maskHeight: height,
            ),
          );
    }

    final groups = grouped.entries.map((entry) {
      final instances = entry.value;
      final displayName = instances.isNotEmpty ? _itemZhName(instances.first.item) : '未知食物';
      return _FoodGroup(key: entry.key, displayName: displayName, instances: instances);
    }).toList();

    groups.sort((a, b) {
      final caloriesCompare = b.totalCalories.compareTo(a.totalCalories);
      if (caloriesCompare != 0) return caloriesCompare;
      return b.averageConfidence.compareTo(a.averageConfidence);
    });
    return groups;
  }

  List<Widget> _buildVisibleGroups(BuildContext context, List<_FoodGroup> visibleGroups) {
    return visibleGroups
        .map((group) {
          return Card(
            child: ListTile(
              onTap: () => _showGroupDetail(context, group),
              title: Text(group.displayName),
              subtitle: Text(_groupSubtitle(group)),
              trailing: Text('${group.totalCalories.toStringAsFixed(1)} 千卡'),
            ),
          );
        })
        .toList();
  }

  String _groupSubtitle(_FoodGroup group) {
    final base =
        '${group.instanceCount} 个区域 · 置信度 ${(group.averageConfidence * 100).toStringAsFixed(1)}%';
    return group.isLowConfidence ? '$base · 待确认，不用于具体建议' : base;
  }

  String _groupKey(DetectedItem item) {
    final classId = item.classId?.toString() ?? 'unknown';
    final name = item.className.trim().isNotEmpty ? item.className.trim() : item.displayName.trim();
    return '$classId|${name.toLowerCase()}';
  }

  Uint8List? _decodeMaskRle(String? rle, List<int>? shape) {
    if (rle == null || rle.trim().isEmpty || shape == null || shape.length < 2) {
      return null;
    }
    final height = shape[0];
    final width = shape[1];
    if (height <= 0 || width <= 0) {
      return null;
    }
    final output = Uint8List(width * height);
    final counts = rle
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    var currentValue = 0;
    var outputIndex = 0;
    for (final count in counts) {
      for (var i = 0; i < count && outputIndex < output.length; i++) {
        if (currentValue == 1) {
          output[outputIndex] = 1;
        }
        outputIndex++;
      }
      currentValue = 1 - currentValue;
    }
    return output;
  }

  String _itemZhName(DetectedItem item) {
    final candidates = <String>[
      item.displayName,
      item.className,
      item.label,
    ];
    for (final raw in candidates) {
      final normalized = raw.trim();
      if (normalized.isEmpty) continue;
      final mapped = _labelZh[normalized.toLowerCase()];
      if (mapped != null) return mapped;
      if (_looksChinese(normalized)) return normalized;
    }
    return '未知食物';
  }

  bool _looksChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  bool _hasInteractiveRegions(List<DetectedItem> items) {
    return items.any((item) =>
        (item.maskRle != null && item.maskRle!.trim().isNotEmpty) &&
        item.maskShape != null &&
        item.maskShape!.length >= 2);
  }

  void _showGroupDetail(BuildContext context, _FoodGroup group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (sheetContext, controller) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: ListView(
                controller: controller,
                children: [
                  Text(
                    group.displayName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('区域数量：${group.instanceCount}'),
                  Text('总热量：${group.totalCalories.toStringAsFixed(1)} 千卡'),
                  Text('蛋白质：${group.totalProtein.toStringAsFixed(1)} g'),
                  Text('脂肪：${group.totalFat.toStringAsFixed(1)} g'),
                  Text('碳水：${group.totalCarbs.toStringAsFixed(1)} g'),
                  if (group.isLowConfidence) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '这个类别的平均置信度低于 65%，仅供核对，不用于点名建议。',
                      style: TextStyle(
                        color: Color(0xFF80552C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('包含区域', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...group.instances.map(
                    (instance) => Card(
                      child: ListTile(
                        title: Text('区域 ${instance.index + 1}'),
                        subtitle: Text('置信度 ${(instance.item.confidence * 100).toStringAsFixed(1)}%'),
                        trailing: Text('${(instance.item.calories ?? 0).toStringAsFixed(1)} 千卡'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

_AdviceSections _splitAdviceSections(String rawAdvice) {
  final trimmed = rawAdvice.trim();
  if (trimmed.isEmpty) {
    return const _AdviceSections(body: '暂无建议');
  }

  final blocks = trimmed
      .split(RegExp(r'\r?\n\s*\r?\n'))
      .map((block) => block.trim())
      .where((block) => block.isNotEmpty)
      .toList();
  if (blocks.isEmpty) {
    return const _AdviceSections(body: '暂无建议');
  }

  final firstBlock = blocks.first;
  if (!firstBlock.startsWith('个性化参考依据')) {
    return _AdviceSections(body: trimmed);
  }

  final basisLines = firstBlock
      .split(RegExp(r'\r?\n'))
      .skip(1)
      .map((line) => line.replaceFirst(RegExp(r'^[-•]\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final body = blocks.skip(1).join('\n\n').trim();
  return _AdviceSections(
    basis: basisLines.isEmpty ? null : basisLines.join('\n'),
    body: body.isEmpty ? '暂无建议' : body,
  );
}

class _CalorieLevel {
  const _CalorieLevel(this.label, this.description, this.color);

  final String label;
  final String description;
  final Color color;
}

class _AdviceSections {
  const _AdviceSections({
    required this.body,
    this.basis,
  });

  final String? basis;
  final String body;
}

class _FoodGroup {
  _FoodGroup({
    required this.key,
    required this.displayName,
    required this.instances,
  });

  final String key;
  final String displayName;
  final List<_SegmentInstance> instances;

  double get totalCalories => instances.fold<double>(0, (sum, e) => sum + (e.item.calories ?? 0));
  double get totalProtein => instances.fold<double>(0, (sum, e) => sum + (e.item.proteinG ?? 0));
  double get totalFat => instances.fold<double>(0, (sum, e) => sum + (e.item.fatG ?? 0));
  double get totalCarbs => instances.fold<double>(0, (sum, e) => sum + (e.item.carbsG ?? 0));
  double get averageConfidence => instances.isEmpty
      ? 0
      : instances.fold<double>(0, (sum, e) => sum + e.item.confidence) / instances.length;
  bool get isLowConfidence => averageConfidence < ResultPage._adviceConfidenceThreshold;
  int get instanceCount => instances.length;
}

class _SegmentInstance {
  _SegmentInstance({
    required this.index,
    required this.item,
    required this.maskBytes,
    required this.maskWidth,
    required this.maskHeight,
  });

  final int index;
  final DetectedItem item;
  final Uint8List? maskBytes;
  final int maskWidth;
  final int maskHeight;

  bool containsPoint(double x, double y, Rect imageRect) {
    final data = maskBytes;
    if (data == null || maskWidth <= 0 || maskHeight <= 0 || imageRect.width <= 0 || imageRect.height <= 0) {
      return false;
    }
    if (!imageRect.contains(Offset(x, y))) {
      return false;
    }
    final px = (((x - imageRect.left) / imageRect.width) * maskWidth).floor().clamp(0, maskWidth - 1);
    final py = (((y - imageRect.top) / imageRect.height) * maskHeight).floor().clamp(0, maskHeight - 1);
    final index = py * maskWidth + px;
    return index >= 0 && index < data.length && data[index] != 0;
  }
}

Future<ui.Image?> _decodeUiImageBytes(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

class _ResultImagePreview extends StatefulWidget {
  const _ResultImagePreview({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_ResultImagePreview> createState() => _ResultImagePreviewState();
}

class _ResultImagePreviewState extends State<_ResultImagePreview> {
  late final Future<ui.Image?> _decodedImageFuture;

  @override
  void initState() {
    super.initState();
    _decodedImageFuture = _decodeUiImageBytes(widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _decodedImageFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final image = snapshot.data;
        if (image == null) {
          return Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(child: Text('图片预览不可用')),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final aspectRatio = image.width / image.height;
            final height = math.min(320.0, constraints.maxWidth / aspectRatio);
            final width = height * aspectRatio;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DecodedCanvasImages {
  const _DecodedCanvasImages({required this.overlayImage, required this.originalImage});

  final ui.Image? overlayImage;
  final ui.Image? originalImage;
}

class _InteractiveSegmentationCanvas extends StatefulWidget {
  const _InteractiveSegmentationCanvas({
    required this.overlayImageBytes,
    required this.groups,
    this.originalImageBytes,
    this.onGroupTap,
  });

  final Uint8List overlayImageBytes;
  final Uint8List? originalImageBytes;
  final List<_FoodGroup> groups;
  final ValueChanged<_FoodGroup>? onGroupTap;

  @override
  State<_InteractiveSegmentationCanvas> createState() => _InteractiveSegmentationCanvasState();
}

class _InteractiveSegmentationCanvasState extends State<_InteractiveSegmentationCanvas> {
  late final Future<_DecodedCanvasImages> _decodedImagesFuture;
  late final List<_SegmentOverlayGroup> _overlayGroups;
  _SegmentOverlayGroup? _selectedGroup;
  bool _showOriginalPreview = false;

  @override
  void initState() {
    super.initState();
    _decodedImagesFuture = _decodeCanvasImages();
    _overlayGroups = _buildOverlayGroups(widget.groups);
  }

  Future<_DecodedCanvasImages> _decodeCanvasImages() async {
    final overlayImage = await _decodeUiImageBytes(widget.overlayImageBytes);
    ui.Image? originalImage;
    if (widget.originalImageBytes != null) {
      originalImage = identical(widget.originalImageBytes, widget.overlayImageBytes)
          ? overlayImage
          : await _decodeUiImageBytes(widget.originalImageBytes!);
    }
    return _DecodedCanvasImages(overlayImage: overlayImage, originalImage: originalImage);
  }

  List<_SegmentOverlayGroup> _buildOverlayGroups(List<_FoodGroup> groups) {
    final overlays = <_SegmentOverlayGroup>[];
    for (final group in groups) {
      final overlay = _mergeGroupMask(group);
      if (overlay != null) {
        overlays.add(overlay);
      }
    }
    return overlays;
  }

  _SegmentOverlayGroup? _mergeGroupMask(_FoodGroup group) {
    final candidates = group.instances
        .where((instance) => instance.maskBytes != null && instance.maskWidth > 0 && instance.maskHeight > 0)
        .toList();
    if (candidates.isEmpty) {
      return null;
    }

    final width = candidates.first.maskWidth;
    final height = candidates.first.maskHeight;
    final merged = Uint8List(width * height);
    var areaPixels = 0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;

    for (final instance in candidates) {
      if (instance.maskWidth != width || instance.maskHeight != height) {
        continue;
      }
      final mask = instance.maskBytes!;
      for (var index = 0; index < merged.length; index++) {
        if (mask[index] == 0 || merged[index] != 0) {
          continue;
        }
        merged[index] = 1;
        areaPixels++;
        final y = index ~/ width;
        final x = index % width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (areaPixels == 0) {
      return null;
    }

    final compacted = _compactMaskForDisplay(merged, width, height);
    final compactedMask = compacted.mask;
    final compactedArea = compacted.areaPixels;
    if (compactedArea == 0) {
      return null;
    }

    return _SegmentOverlayGroup(
      group: group,
      maskBytes: compactedMask,
      maskWidth: width,
      maskHeight: height,
      areaPixels: compactedArea,
      badgeAnchor: Offset((compacted.minX + compacted.maxX + 1) / 2, compacted.minY.toDouble()),
    );
  }

  _MaskDisplayCompaction _compactMaskForDisplay(Uint8List mask, int width, int height) {
    final componentIdByPixel = Int32List(mask.length);
    final componentAreas = <int>[];
    final componentPixels = <List<int>>[];
    var componentId = 0;

    Iterable<int> neighbors(int index) sync* {
      final x = index % width;
      final y = index ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) {
            continue;
          }
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
            continue;
          }
          yield ny * width + nx;
        }
      }
    }

    for (var index = 0; index < mask.length; index++) {
      if (mask[index] == 0 || componentIdByPixel[index] != 0) {
        continue;
      }

      componentId++;
      final queue = <int>[index];
      final pixels = <int>[];
      componentIdByPixel[index] = componentId;

      for (var cursor = 0; cursor < queue.length; cursor++) {
        final current = queue[cursor];
        pixels.add(current);
        for (final next in neighbors(current)) {
          if (mask[next] == 0 || componentIdByPixel[next] != 0) {
            continue;
          }
          componentIdByPixel[next] = componentId;
          queue.add(next);
        }
      }

      componentAreas.add(pixels.length);
      componentPixels.add(pixels);
    }

    if (componentAreas.isEmpty) {
      return _MaskDisplayCompaction.empty();
    }

    final sortedComponentIndices = List<int>.generate(componentAreas.length, (index) => index)
      ..sort((a, b) => componentAreas[b].compareTo(componentAreas[a]));
    final largestArea = componentAreas[sortedComponentIndices.first];
    final totalArea = componentAreas.fold<int>(0, (sum, area) => sum + area);
    final dominantAreaThreshold = math.max(180, (largestArea * 0.14).round());
    final supportAreaThreshold = math.max(96, (largestArea * 0.06).round());
    final maxComponentsToKeep = largestArea >= 2200 ? 3 : 2;
    final compacted = Uint8List(mask.length);
    var areaPixels = 0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    var keptComponents = 0;

    for (final idx in sortedComponentIndices) {
      final area = componentAreas[idx];
      final keepAsDominant = area >= dominantAreaThreshold;
      final keepAsSupport = keptComponents < maxComponentsToKeep &&
          area >= supportAreaThreshold &&
          areaPixels < (totalArea * 0.9).round();
      if (!keepAsDominant && !keepAsSupport) {
        continue;
      }

      for (final pixel in componentPixels[idx]) {
        compacted[pixel] = 1;
        areaPixels++;
        final y = pixel ~/ width;
        final x = pixel % width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }

      keptComponents++;
      if (keptComponents >= maxComponentsToKeep && areaPixels >= (totalArea * 0.82).round()) {
        break;
      }
    }

    if (areaPixels == 0) {
      return _MaskDisplayCompaction.empty();
    }

    return _MaskDisplayCompaction(
      mask: compacted,
      areaPixels: areaPixels,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
    );
  }

  void _handleTap(TapUpDetails details, Rect imageRect) {
    final local = details.localPosition;
    _SegmentOverlayGroup? hit;
    for (final overlay in _overlayGroups.reversed) {
      if (overlay.containsPoint(local.dx, local.dy, imageRect)) {
        hit = overlay;
        break;
      }
    }
    setState(() {
      _selectedGroup = hit;
    });
    if (hit != null) {
      widget.onGroupTap?.call(hit.group);
    }
  }

  void _setOriginalPreviewVisible(bool visible) {
    if (widget.originalImageBytes == null || _showOriginalPreview == visible) {
      return;
    }
    setState(() {
      _showOriginalPreview = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DecodedCanvasImages>(
      future: _decodedImagesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final images = snapshot.data!;
        final maskSpaceImage = images.overlayImage;
        final displayBaseImage = images.originalImage ?? maskSpaceImage;
        if (displayBaseImage == null || _overlayGroups.isEmpty) {
          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(child: Text('分割区域不可用')),
          );
        }

        final aspectRatio = _overlayGroups.isNotEmpty && _overlayGroups.first.maskHeight > 0
            ? _overlayGroups.first.maskWidth / _overlayGroups.first.maskHeight
            : displayBaseImage.width / displayBaseImage.height;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageRect = Offset.zero & constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _showOriginalPreview ? null : (details) => _handleTap(details, imageRect),
                    onLongPressStart: widget.originalImageBytes == null ? null : (_) => _setOriginalPreviewVisible(true),
                    onLongPressEnd: widget.originalImageBytes == null ? null : (_) => _setOriginalPreviewVisible(false),
                    onLongPressUp: widget.originalImageBytes == null ? null : () => _setOriginalPreviewVisible(false),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        painter: _SegmentationOverlayPainter(
                          image: displayBaseImage,
                          overlays: _overlayGroups,
                          selectedOverlay: _selectedGroup,
                          showOverlay: !_showOriginalPreview,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showOriginalPreview
                  ? '松开后恢复轮廓视图'
                  : _selectedGroup == null
                      ? '默认显示原图和轻量轮廓，点击区域查看详情，长按查看纯原图'
                      : '点击其他轮廓切换分类，长按查看纯原图',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            if (_selectedGroup != null) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedGroup!.group.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text('已合并区域：${_selectedGroup!.group.instanceCount} 个'),
                      Text('平均置信度 ${( _selectedGroup!.group.averageConfidence * 100).toStringAsFixed(1)}%'),
                      Text('热量：${_selectedGroup!.group.totalCalories.toStringAsFixed(1)} 千卡'),
                      Text('蛋白质：${_selectedGroup!.group.totalProtein.toStringAsFixed(1)} g'),
                      Text('脂肪：${_selectedGroup!.group.totalFat.toStringAsFixed(1)} g'),
                      Text('碳水：${_selectedGroup!.group.totalCarbs.toStringAsFixed(1)} g'),
                      if (_selectedGroup!.group.isLowConfidence) ...[
                        const SizedBox(height: 6),
                        const Text(
                          '待确认类别，不用于具体饮食建议。',
                          style: TextStyle(
                            color: Color(0xFF80552C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SegmentOverlayGroup {
  const _SegmentOverlayGroup({
    required this.group,
    required this.maskBytes,
    required this.maskWidth,
    required this.maskHeight,
    required this.areaPixels,
    required this.badgeAnchor,
  });

  final _FoodGroup group;
  final Uint8List maskBytes;
  final int maskWidth;
  final int maskHeight;
  final int areaPixels;
  final Offset badgeAnchor;

  bool containsPoint(double x, double y, Rect imageRect) {
    if (maskWidth <= 0 || maskHeight <= 0 || imageRect.width <= 0 || imageRect.height <= 0) {
      return false;
    }
    if (!imageRect.contains(Offset(x, y))) {
      return false;
    }
    final px = (((x - imageRect.left) / imageRect.width) * maskWidth).floor().clamp(0, maskWidth - 1);
    final py = (((y - imageRect.top) / imageRect.height) * maskHeight).floor().clamp(0, maskHeight - 1);
    final index = py * maskWidth + px;
    return index >= 0 && index < maskBytes.length && maskBytes[index] != 0;
  }
}

class _MaskDisplayCompaction {
  const _MaskDisplayCompaction({
    required this.mask,
    required this.areaPixels,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  _MaskDisplayCompaction.empty()
      : mask = Uint8List(0),
        areaPixels = 0,
        minX = 0,
        minY = 0,
        maxX = 0,
        maxY = 0;

  final Uint8List mask;
  final int areaPixels;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
}

class _SegmentationOverlayPainter extends CustomPainter {
  _SegmentationOverlayPainter({
    required this.image,
    required this.overlays,
    required this.selectedOverlay,
    required this.showOverlay,
  });

  final ui.Image image;
  final List<_SegmentOverlayGroup> overlays;
  final _SegmentOverlayGroup? selectedOverlay;
  final bool showOverlay;

  static const List<Color> _palette = [
    Color(0xFFF6B26B),
    Color(0xFFC8A2FF),
    Color(0xFF8FD3C1),
    Color(0xFFF9D976),
    Color(0xFFA7C7FF),
    Color(0xFFF4A6A6),
    Color(0xFFB7E4C7),
    Color(0xFFFFD6A5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final imageRect = rect;
    canvas.drawRect(rect, Paint()..color = Colors.black);
    paintImage(
      canvas: canvas,
      rect: rect,
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!showOverlay) {
      return;
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.round;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];
      final isSelected = overlay == selectedOverlay;
      final accentColor = _palette[i % _palette.length];
      final accentLineColor = Color.lerp(Colors.black, accentColor, 0.78)!;
      final borderPath = _buildMaskBorderPath(imageRect, overlay.maskBytes, overlay.maskWidth, overlay.maskHeight);
      fillPaint.color = accentColor.withAlpha(isSelected ? 84 : 54);
      glowPaint
        ..color = accentColor.withAlpha(isSelected ? 104 : 0)
        ..strokeWidth = isSelected ? 8.0 : 0.0
        ..maskFilter = isSelected ? const ui.MaskFilter.blur(ui.BlurStyle.normal, 4.0) : null;
      outlinePaint
        ..color = Colors.white.withAlpha(isSelected ? 252 : 242)
        ..strokeWidth = isSelected ? 5.4 : 4.0;
      accentPaint
        ..color = accentColor.withAlpha(isSelected ? 248 : 224)
        ..strokeWidth = isSelected ? 2.6 : 1.8;

      canvas.drawPath(borderPath, fillPaint);
      if (isSelected) {
        canvas.drawPath(borderPath, glowPaint);
      }
      canvas.drawPath(borderPath, outlinePaint);
      canvas.drawPath(borderPath, accentPaint);

      final x = imageRect.left + overlay.badgeAnchor.dx / overlay.maskWidth * imageRect.width;
      final y = imageRect.top + overlay.badgeAnchor.dy / overlay.maskHeight * imageRect.height;

      final badgeFillColor = Colors.white.withAlpha(isSelected ? 250 : 242);
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (x - 18).clamp(imageRect.left, imageRect.right - 36),
          (y - 2).clamp(imageRect.top, imageRect.bottom - 26),
          36,
          26,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        badgeRect.shift(const Offset(0, 1.5)),
        Paint()..color = Colors.black.withAlpha(isSelected ? 48 : 30),
      );
      canvas.drawRRect(badgeRect, Paint()..color = badgeFillColor);
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = accentColor.withAlpha(isSelected ? 244 : 228)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.6 : 1.3,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: accentLineColor.withAlpha(isSelected ? 255 : 246),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 36);
      tp.paint(canvas, Offset(badgeRect.left + (36 - tp.width) / 2, badgeRect.top + 4));
    }
  }

  Path _buildMaskBorderPath(Rect imageRect, Uint8List mask, int maskWidth, int maskHeight) {
    final path = Path();
    if (maskWidth <= 0 || maskHeight <= 0) {
      return path;
    }

    final reduced = _reduceMask(mask, maskWidth, maskHeight);
    final reducedMask = reduced.mask;
    final reducedWidth = reduced.width;
    final reducedHeight = reduced.height;
    final loops = _extractBoundaryLoops(reducedMask, reducedWidth, reducedHeight);
    if (loops.isEmpty) {
      return path;
    }

    final loopEntries = loops
        .where((loop) => loop.length >= 3)
        .map(
          (loop) => (
            loop: loop,
            signedArea: _signedGridLoopArea(loop),
          ),
        )
        .where((entry) => entry.signedArea != 0)
        .toList()
      ..sort((a, b) => b.signedArea.abs().compareTo(a.signedArea.abs()));
    if (loopEntries.isEmpty) {
      return path;
    }

    final outerLoopSign = loopEntries.first.signedArea > 0 ? 1 : -1;
    final cellWidth = imageRect.width / reducedWidth;
    final cellHeight = imageRect.height / reducedHeight;

    for (final entry in loopEntries) {
      final loopSign = entry.signedArea > 0 ? 1 : -1;
      if (loopSign != outerLoopSign) {
        continue;
      }
      final loop = entry.loop;
      final points = loop
          .map(
            (point) => Offset(
              imageRect.left + point.x * cellWidth,
              imageRect.top + point.y * cellHeight,
            ),
          )
          .toList();
      final smoothPoints = _smoothClosedPoints(points, iterations: 1);
      _appendSmoothClosedPath(path, smoothPoints);
    }

    return path;
  }

  double _signedGridLoopArea(List<_GridPoint> loop) {
    if (loop.length < 3) {
      return 0;
    }

    var area = 0.0;
    for (var i = 0; i < loop.length; i++) {
      final current = loop[i];
      final next = loop[(i + 1) % loop.length];
      area += (current.x * next.y) - (next.x * current.y);
    }
    return area / 2.0;
  }

  _ReducedMask _reduceMask(Uint8List mask, int width, int height) {
    final sampleStep = math.max(1, math.max(width, height) ~/ 140);
    if (sampleStep == 1) {
      return _ReducedMask(mask: mask, width: width, height: height);
    }

    final reducedWidth = (width / sampleStep).ceil();
    final reducedHeight = (height / sampleStep).ceil();
    final reducedMask = Uint8List(reducedWidth * reducedHeight);

    for (var row = 0; row < reducedHeight; row++) {
      final startY = row * sampleStep;
      final endY = math.min(height, startY + sampleStep);
      for (var col = 0; col < reducedWidth; col++) {
        final startX = col * sampleStep;
        final endX = math.min(width, startX + sampleStep);
        var filled = false;
        for (var y = startY; y < endY && !filled; y++) {
          final rowOffset = y * width;
          for (var x = startX; x < endX; x++) {
            if (mask[rowOffset + x] != 0) {
              filled = true;
              break;
            }
          }
        }
        reducedMask[row * reducedWidth + col] = filled ? 1 : 0;
      }
    }

    return _ReducedMask(mask: reducedMask, width: reducedWidth, height: reducedHeight);
  }

  List<List<_GridPoint>> _extractBoundaryLoops(Uint8List mask, int width, int height) {
    bool isFilled(int row, int col) {
      if (row < 0 || row >= height || col < 0 || col >= width) {
        return false;
      }
      return mask[row * width + col] != 0;
    }

    final outgoing = <_GridPoint, List<_GridPoint>>{};

    void addEdge(_GridPoint start, _GridPoint end) {
      outgoing.putIfAbsent(start, () => <_GridPoint>[]).add(end);
    }

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        if (!isFilled(row, col)) {
          continue;
        }
        if (!isFilled(row - 1, col)) {
          addEdge(_GridPoint(col, row), _GridPoint(col + 1, row));
        }
        if (!isFilled(row, col + 1)) {
          addEdge(_GridPoint(col + 1, row), _GridPoint(col + 1, row + 1));
        }
        if (!isFilled(row + 1, col)) {
          addEdge(_GridPoint(col + 1, row + 1), _GridPoint(col, row + 1));
        }
        if (!isFilled(row, col - 1)) {
          addEdge(_GridPoint(col, row + 1), _GridPoint(col, row));
        }
      }
    }

    final loops = <List<_GridPoint>>[];
    while (outgoing.isNotEmpty) {
      final start = outgoing.keys.first;
      final loop = <_GridPoint>[start];
      var current = start;
      var guard = 0;

      while (guard < 200000) {
        guard++;
        final nextCandidates = outgoing[current];
        if (nextCandidates == null || nextCandidates.isEmpty) {
          break;
        }
        final next = nextCandidates.removeLast();
        if (nextCandidates.isEmpty) {
          outgoing.remove(current);
        }
        if (next == start) {
          loops.add(loop);
          break;
        }
        loop.add(next);
        current = next;
      }
    }

    return loops;
  }

  List<Offset> _smoothClosedPoints(List<Offset> points, {int iterations = 2}) {
    var current = List<Offset>.from(points);
    for (var iteration = 0; iteration < iterations; iteration++) {
      if (current.length < 3) {
        break;
      }
      final next = <Offset>[];
      for (var i = 0; i < current.length; i++) {
        final p0 = current[i];
        final p1 = current[(i + 1) % current.length];
        next.add(Offset(0.75 * p0.dx + 0.25 * p1.dx, 0.75 * p0.dy + 0.25 * p1.dy));
        next.add(Offset(0.25 * p0.dx + 0.75 * p1.dx, 0.25 * p0.dy + 0.75 * p1.dy));
      }
      current = next;
    }
    return current;
  }

  void _appendSmoothClosedPath(Path path, List<Offset> points) {
    if (points.length < 3) {
      return;
    }

    Offset midpoint(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

    final start = midpoint(points.last, points.first);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final end = midpoint(current, next);
      path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
    }
    path.close();
  }

  @override
  bool shouldRepaint(covariant _SegmentationOverlayPainter oldDelegate) {
    return oldDelegate.selectedOverlay != selectedOverlay ||
        oldDelegate.overlays != overlays ||
        oldDelegate.image != image ||
        oldDelegate.showOverlay != showOverlay;
  }
}

class _ReducedMask {
  const _ReducedMask({required this.mask, required this.width, required this.height});

  final Uint8List mask;
  final int width;
  final int height;
}

class _GridPoint {
  const _GridPoint(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _GridPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}
