import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_models.dart';
import 'auth_service.dart';
import 'profile_context_service.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static String get baseUrl {
    // Prefer explicit runtime override when connecting to a remote host/phone.
    const fromEnv = String.fromEnvironment('NUTRI_API_BASE', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;

    // Web should call backend on the same host users opened the page from.
    if (kIsWeb) {
      return Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: 18080,
        path: '/api/v1',
      ).toString();
    }

    // Android emulator cannot reach host loopback directly; use 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:18080/api/v1';
    }

    return 'http://127.0.0.1:18080/api/v1';
  }

  static const _demoAccessCode = String.fromEnvironment(
    'NUTRI_DEMO_ACCESS_CODE',
    defaultValue: '',
  );

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    headers: {
      if (_demoAccessCode.isNotEmpty)
        'X-Nutri-Access-Code': _demoAccessCode,
    },
  ));

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('响应不是有效 JSON 对象');
  }

  static String describeError(Object error, {String? action}) {
    final prefix = action == null || action.isEmpty ? '请求失败' : '$action失败';

    if (error is StateError) {
      return '$prefix：${error.message.isEmpty ? '请先登录后再试' : error.message}';
    }

    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        if (action == '提交分析') {
          return '提交分析失败：当前网络不可用或服务暂时无法访问，请检查网络后重新提交。';
        }
        if (action == '状态查询') {
          return '状态查询失败：当前网络不可用或服务暂时无法访问，请检查网络后重试。';
        }
        return '$prefix：当前网络不可用或服务暂时无法访问，请检查网络后重试。';
      }

      if (error.type == DioExceptionType.badResponse) {
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) {
          return '$prefix：当前请求无权限（$code）。';
        }
        if (code == 404) {
          return '$prefix：当前功能暂时不可用，请稍后再试。';
        }
        if (code != null && code >= 500) {
          return '$prefix：服务端异常（$code），请稍后重试。';
        }
        return '$prefix：服务返回异常（${code ?? 'unknown'}）。';
      }

      if (error.type == DioExceptionType.cancel) {
        return '$prefix：请求已取消。';
      }

      return '$prefix：网络请求失败，请稍后重试。';
    }

    return '$prefix：$error';
  }

  Future<int> _requireUserId() async {
    await AuthService.instance.ensureLoaded();
    final userId = AuthService.instance.currentUserId;
    if (userId == null || userId <= 0) {
      throw StateError('请先登录账号');
    }
    return userId;
  }

  Future<AuthCodeDispatch> sendLoginCode(String phone) async {
    final resp = await _dio.post('/auth/send-code', data: {'phone': phone});
    return AuthCodeDispatch.fromJson(_asJsonMap(resp.data));
  }

  Future<AuthSession> verifyLoginCode({required String phone, required String code}) async {
    final resp = await _dio.post(
      '/auth/verify-code',
      data: {'phone': phone, 'code': code},
    );
    return AuthSession.fromJson(_asJsonMap(resp.data));
  }

  Future<UserProfile> getProfile() async {
    final userId = await _requireUserId();
    final resp = await _dio.get('/users/$userId/profile');
    return UserProfile.fromJson(_asJsonMap(resp.data));
  }

  Future<UserProfile> updateProfile({
    String? nickname,
    required String healthGoal,
    required int dailyCalorieTarget,
    required List<String> restrictions,
    int? heightCm,
    double? weightKg,
    String? gender,
  }) async {
    final userId = await _requireUserId();
    final resp = await _dio.put(
      '/users/$userId/profile',
      data: {
        'nickname': nickname,
        'healthGoal': healthGoal,
        'dailyCalorieTarget': dailyCalorieTarget,
        'dietaryRestrictions': restrictions,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'gender': gender,
      },
    );
    return UserProfile.fromJson(_asJsonMap(resp.data));
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
    final userId = await _requireUserId();
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
    return _asJsonMap(resp.data);
  }

  Future<String> uploadImage({
    required XFile file,
    required String mealType,
  }) async {
    final userId = await _requireUserId();
    final profileContext = await ProfileContextService.instance.loadSnapshot();
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

    final formData = <String, dynamic>{
      'file': uploadFile,
      'mealType': mealType,
    };
    if (profileContext.age != null) {
      formData['age'] = profileContext.age.toString();
    }
    if (profileContext.heightCm != null) {
      formData['heightCm'] = profileContext.heightCm.toString();
    }
    if (profileContext.weightKg != null) {
      formData['weightKg'] = profileContext.weightKg.toString();
    }
    if (profileContext.gender != null && profileContext.gender!.trim().isNotEmpty) {
      formData['gender'] = profileContext.gender;
    }
    if (profileContext.activityLevel != null &&
        profileContext.activityLevel!.trim().isNotEmpty) {
      formData['activityLevel'] = profileContext.activityLevel;
    }

    final form = FormData.fromMap(formData);
    final resp = await _dio.post(
      '/diet-logs/upload',
      data: form,
      options: Options(
        headers: {'X-User-Id': userId.toString()},
      ),
    );
    final data = _asJsonMap(resp.data);
    return (data['taskId'] ?? '').toString();
  }

  Future<AnalysisResult> getTaskStatus(String taskId) async {
    final resp = await _dio.get('/diet-logs/$taskId/status');
    return AnalysisResult.fromTaskStatus(_asJsonMap(resp.data));
  }

  Future<Uint8List> getTaskImageBytes(String taskId) async {
    final resp = await _dio.get(
      '/diet-logs/$taskId/image',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    if (data is List) {
      return Uint8List.fromList(data.cast<int>());
    }
    throw const FormatException('图片响应格式无效');
  }

  Future<List<HistoryItem>> getHistory({int page = 0, int size = 10}) async {
    final userId = await _requireUserId();
    final resp = await _dio.get('/diet-logs', queryParameters: {
      'userId': userId,
      'page': page,
      'size': size,
    });
    final data = _asJsonMap(resp.data);
    final content = (data['content'] ?? []) as List;
    return content
        .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
