import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'processing_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();

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
      setState(() => _error = '分析失败：$e');
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
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_previewBytes == null)
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(child: Text('请选择或拍摄一张餐食照片')),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_previewBytes!, height: 220, fit: BoxFit.cover),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _pickFromCamera,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('拍照'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _pickFromGallery,
                  icon: const Icon(Icons.image),
                  label: const Text('相册'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_previewBytes != null)
            TextButton.icon(
              onPressed: _loading ? null : _resetImage,
              icon: const Icon(Icons.refresh),
              label: const Text('重新选择图片'),
            ),
          const SizedBox(height: 12),
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
                : (v) {
                    if (v == null) return;
                    setState(() => _mealType = v);
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
    );
  }
}
