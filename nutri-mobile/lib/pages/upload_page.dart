import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../utils/navigation_utils.dart';
import '../widgets/app_chrome.dart';
import 'processing_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;
  Uint8List? _previewBytes;
  bool _loading = false;
  String _mealType = 'LUNCH';
  String? _error;

  Future<void> _setPicked(XFile file) async {
    final bytes = await file.readAsBytes();
    setState(() {
      _selectedImage = file;
      _previewBytes = bytes;
      _error = null;
    });
  }

  Future<void> _pickFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    await _setPicked(file);
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    await _setPicked(file);
  }

  void _resetImage() {
    setState(() {
      _selectedImage = null;
      _previewBytes = null;
      _error = null;
    });
  }

  Future<void> _analyse() async {
    if (_selectedImage == null) {
      setState(() => _error = '请先选择图片');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final taskId = await ApiService.instance.uploadImage(
        file: _selectedImage!,
        mealType: _mealType,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始分析，通常 10-20 秒可查看热量结果。')),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessingPage(
            taskId: taskId,
            imageBytes: _previewBytes,
          ),
        ),
      ).then((_) {
        if (!mounted) return;
        setState(() {
          _selectedImage = null;
          _previewBytes = null;
          _error = null;
        });
      });
    } catch (e) {
      setState(() => _error = ApiService.describeError(e, action: '提交分析'));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传餐食图片'),
        leading: const SafeBackButton(),
      ),
      body: AppSoftBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const AppHeroCard(
              icon: Icons.camera_alt_rounded,
              title: '上传一张清晰餐图',
              subtitle: '尽量拍完整餐盘，减少遮挡和过曝，识别结果会更稳定。',
              footer: AppHintStrip(
                icon: Icons.photo_outlined,
                text: '拍照和相册都可以，选好餐次后再开始分析。',
              ),
            ),
            const SizedBox(height: 18),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(
                    title: '餐图预览',
                    subtitle: '确认图片内容清晰，再提交识别。',
                  ),
                  const SizedBox(height: 16),
                  if (_previewBytes == null)
                    Container(
                      height: 240,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3EA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF0D2BD)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, size: 42, color: Color(0xFFB86A3D)),
                          SizedBox(height: 10),
                          Text('请选择或拍摄一张餐食照片'),
                        ],
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(_previewBytes!, height: 240, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _pickFromCamera,
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('拍照'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _pickFromGallery,
                          icon: const Icon(Icons.image_rounded),
                          label: const Text('相册'),
                        ),
                      ),
                    ],
                  ),
                  if (_previewBytes != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loading ? null : _resetImage,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新选择图片'),
                    ),
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
                    title: '提交分析',
                    subtitle: '选择餐次后开始估算热量与生成建议。',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _mealType,
                    decoration: const InputDecoration(labelText: '餐次'),
                    items: const [
                      DropdownMenuItem(value: 'BREAKFAST', child: Text('早餐')),
                      DropdownMenuItem(value: 'LUNCH', child: Text('午餐')),
                      DropdownMenuItem(value: 'DINNER', child: Text('晚餐')),
                      DropdownMenuItem(value: 'SNACK', child: Text('加餐')),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _mealType = value);
                          },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _analyse,
                    child: Text(_loading ? '分析中，请稍候...' : '开始分析'),
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
