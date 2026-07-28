class UserProfile {
  final int userId;
  final String? phone;
  final String? nickname;
  final String healthGoal;
  final int dailyCalorieTarget;
  final List<String> dietaryRestrictions;
  final int? heightCm;
  final double? weightKg;
  final String? gender;

  UserProfile({
    required this.userId,
    required this.phone,
    required this.nickname,
    required this.healthGoal,
    required this.dailyCalorieTarget,
    required this.dietaryRestrictions,
    required this.heightCm,
    required this.weightKg,
    required this.gender,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: (json['userId'] ?? 1) as int,
      phone: json['phone']?.toString(),
      nickname: json['nickname']?.toString(),
      healthGoal: (json['healthGoal'] ?? 'GENERAL_HEALTH') as String,
      dailyCalorieTarget: (json['dailyCalorieTarget'] ?? 2000) as int,
      dietaryRestrictions: ((json['dietaryRestrictions'] ?? []) as List)
          .map((e) => e.toString())
          .toList(),
      heightCm: (json['heightCm'] as num?)?.toInt(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      gender: json['gender']?.toString(),
    );
  }
}

class AuthCodeDispatch {
  final String phone;
  final String debugCode;
  final int expiresInSeconds;
  final String message;

  AuthCodeDispatch({
    required this.phone,
    required this.debugCode,
    required this.expiresInSeconds,
    required this.message,
  });

  factory AuthCodeDispatch.fromJson(Map<String, dynamic> json) {
    return AuthCodeDispatch(
      phone: (json['phone'] ?? '').toString(),
      debugCode: (json['debugCode'] ?? '').toString(),
      expiresInSeconds: ((json['expiresInSeconds'] ?? 300) as num).toInt(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class AuthSession {
  final int userId;
  final String phone;
  final bool isNewUser;

  AuthSession({
    required this.userId,
    required this.phone,
    required this.isNewUser,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: ((json['userId'] ?? 0) as num).toInt(),
      phone: (json['phone'] ?? '').toString(),
      isNewUser: json['isNewUser'] == true || json['newUser'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'phone': phone,
        'isNewUser': isNewUser,
      };
}

class DetectedItem {
  final int? classId;
  final String className;
  final String displayName;
  final String label;
  final double confidence;
  final double? estimatedWeightG;
  final double? calories;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final List<double>? bbox;
  final String? maskRle;
  final List<int>? maskShape;

  DetectedItem({
    required this.classId,
    required this.className,
    required this.displayName,
    required this.label,
    required this.confidence,
    required this.estimatedWeightG,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.bbox,
    required this.maskRle,
    required this.maskShape,
  });

  factory DetectedItem.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final nutrition = asMap(json['nutrition']);
    final rawBbox = json['bbox'];

    List<double>? parseBbox(dynamic value) {
      if (value is List) {
        return value.map((e) => (e as num).toDouble()).toList();
      }
      return null;
    }

    List<int>? parseMaskShape(dynamic value) {
      if (value is List) {
        final shape = value.map((e) => (e as num).toInt()).toList();
        if (shape.length >= 2) return shape.take(2).toList();
      }
      return null;
    }

    return DetectedItem(
      classId: (json['class_id'] as num?)?.toInt(),
      className: (json['class_name'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      label: (json['label'] ?? json['class_name'] ?? '').toString(),
      confidence: ((json['confidence_score'] ?? json['confidence'] ?? 0.0) as num).toDouble(),
      estimatedWeightG:
          (json['weight_g'] as num?)?.toDouble() ?? (json['estimated_weight_g'] as num?)?.toDouble(),
      calories: (json['calories'] as num?)?.toDouble() ?? (nutrition?['calories_kcal'] as num?)?.toDouble(),
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? (nutrition?['protein_g'] as num?)?.toDouble(),
      fatG: (json['fat_g'] as num?)?.toDouble() ?? (nutrition?['fat_g'] as num?)?.toDouble(),
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? (nutrition?['carbs_g'] as num?)?.toDouble(),
      bbox: parseBbox(rawBbox),
      maskRle: json['mask_rle']?.toString(),
      maskShape: parseMaskShape(json['mask_shape']),
    );
  }
}

class AnalysisResult {
  final String taskId;
  final String status;
  final String? errorMessage;
  final String adviceReport;
  final List<DetectedItem> detectedItems;
  final double totalCalories;
  final List<double>? kcalRange;
  final String? confidenceLevel;
  final String? workflowMode;
  final List<String> workflowTrace;
  final String? segmentationPreviewPngBase64;

  AnalysisResult({
    required this.taskId,
    required this.status,
    required this.errorMessage,
    required this.adviceReport,
    required this.detectedItems,
    required this.totalCalories,
    required this.kcalRange,
    required this.confidenceLevel,
    required this.workflowMode,
    required this.workflowTrace,
    required this.segmentationPreviewPngBase64,
  });

  factory AnalysisResult.fromTaskStatus(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    final analysis = asMap(json['analysisResult']);
    final seg = asMap(analysis['segmentationResult']);
    final rawItems = (seg['detected_instances'] ?? seg['detected_items'] ?? []) as List;
    final items = rawItems
        .map((e) => DetectedItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final total = items.fold<double>(
      0,
      (sum, e) => sum + (e.calories ?? 0),
    );

    List<double>? parseKcalRange(dynamic value) {
      if (value is List && value.length == 2) {
        return value.map((e) => (e as num).toDouble()).toList();
      }
      return null;
    }

    List<String> parseStringList(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return const [];
    }

    final status = (json['status'] ?? 'PENDING').toString();
    final errorMessage = (json['errorMessage']
        ?? analysis['errorMessage']
        ?? analysis['error']
        ?? seg['error'])
        ?.toString();

    return AnalysisResult(
      taskId: (json['taskId'] ?? analysis['taskId'] ?? '').toString(),
      status: status,
      errorMessage: status == 'COMPLETED' ? null : errorMessage,
      adviceReport: (analysis['adviceReport'] ?? '暂无建议').toString(),
      detectedItems: items,
      totalCalories: ((analysis['totalCalories'] as num?)?.toDouble()) ?? total,
      kcalRange: parseKcalRange(analysis['kcalRange']),
      confidenceLevel: analysis['confidenceLevel']?.toString(),
      workflowMode: analysis['workflowMode']?.toString(),
      workflowTrace: parseStringList(analysis['workflowTrace']),
      segmentationPreviewPngBase64: seg['segmentation_preview_png_base64']?.toString(),
    );
  }
}

class HistoryItem {
  final String taskId;
  final String mealType;
  final String status;
  final String loggedAt;
  final int detectedItemsCount;
  final String? adviceReport;

  HistoryItem({
    required this.taskId,
    required this.mealType,
    required this.status,
    required this.loggedAt,
    required this.detectedItemsCount,
    this.adviceReport,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      taskId: (json['taskId'] ?? '').toString(),
      mealType: (json['mealType'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      loggedAt: (json['loggedAt'] ?? '').toString(),
      detectedItemsCount: (json['detectedItemsCount'] ?? 0) as int,
      adviceReport: json['adviceReport']?.toString(),
    );
  }
}
