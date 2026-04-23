import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_models.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const int userId = 1;

  static String get baseUrl {
    // Prefer explicit runtime override when connecting to a remote host/phone.
    const fromEnv = String.fromEnvironment('NUTRI_API_BASE', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;

    // Web should call backend on the same host users opened the page from.
    if (kIsWeb) {
      return Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: 8080,
        path: '/api/v1',
      ).toString();
    }

    // Android emulator cannot reach host loopback directly; use 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1';
    }

    return 'http://127.0.0.1:8080/api/v1';
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
  ));

  Future<UserProfile> getProfile() async {
    final resp = await _dio.get('/users/$userId/profile');
    return UserProfile.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<UserProfile> updateProfile({
    required String healthGoal,
    required int dailyCalorieTarget,
    required List<String> restrictions,
  }) async {
    final resp = await _dio.put(
      '/users/$userId/profile',
      data: {
        'healthGoal': healthGoal,
        'dailyCalorieTarget': dailyCalorieTarget,
        'dietaryRestrictions': restrictions,
      },
    );
    return UserProfile.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> parseGoalByAssistant({
    required String rawText,
    int? age,
    int? heightCm,
    double? weightKg,
    String? gender,
    String? activityLevel,
    bool applyToProfile = false,
  }) async {
    final resp = await _dio.post(
      '/users/$userId/profile/assistant-parse',
      data: {
        'rawText': rawText,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'gender': gender,
        'activityLevel': activityLevel,
        'applyToProfile': applyToProfile,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<String> uploadImage({
    required XFile file,
    required String mealType,
  }) async {
    final MultipartFile uploadFile;
    if (kIsWeb) {
      uploadFile = MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: file.name,
      );
    } else {
      uploadFile = await MultipartFile.fromFile(
        file.path,
        filename: file.name,
      );
    }

    final form = FormData.fromMap({
      'file': uploadFile,
      'mealType': mealType,
    });
    final resp = await _dio.post(
      '/diet-logs/upload',
      data: form,
      options: Options(
        headers: {'X-User-Id': userId.toString()},
      ),
    );
    return (resp.data['taskId'] ?? '').toString();
  }

  Future<AnalysisResult> getTaskStatus(String taskId) async {
    final resp = await _dio.get('/diet-logs/$taskId/status');
    return AnalysisResult.fromTaskStatus(resp.data as Map<String, dynamic>);
  }

  Future<List<HistoryItem>> getHistory({int page = 0, int size = 10}) async {
    final resp = await _dio.get('/diet-logs', queryParameters: {
      'userId': userId,
      'page': page,
      'size': size,
    });
    final content = (resp.data['content'] ?? []) as List;
    return content
        .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
