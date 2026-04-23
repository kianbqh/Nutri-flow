class UserProfile {
  final int userId;
  final String healthGoal;
  final int dailyCalorieTarget;
  final List<String> dietaryRestrictions;

  UserProfile({
    required this.userId,
    required this.healthGoal,
    required this.dailyCalorieTarget,
    required this.dietaryRestrictions,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: (json['userId'] ?? 1) as int,
      healthGoal: (json['healthGoal'] ?? 'GENERAL_HEALTH') as String,
      dailyCalorieTarget: (json['dailyCalorieTarget'] ?? 2000) as int,
      dietaryRestrictions: ((json['dietaryRestrictions'] ?? []) as List)
          .map((e) => e.toString())
          .toList(),
    );
  }
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
  });

  factory DetectedItem.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as Map<String, dynamic>?;
    final rawBbox = json['bbox'];

    List<double>? parseBbox(dynamic value) {
      if (value is List) {
        return value.map((e) => (e as num).toDouble()).toList();
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
    );
  }
}

class AnalysisResult {
  final String status;
  final String? errorMessage;
  final String adviceReport;
  final List<DetectedItem> detectedItems;
  final double totalCalories;
  final List<double>? kcalRange;
  final String? confidenceLevel;
  final String? workflowMode;
  final List<String> workflowTrace;

  AnalysisResult({
    required this.status,
    required this.errorMessage,
    required this.adviceReport,
    required this.detectedItems,
    required this.totalCalories,
    required this.kcalRange,
    required this.confidenceLevel,
    required this.workflowMode,
    required this.workflowTrace,
  });

  factory AnalysisResult.fromTaskStatus(Map<String, dynamic> json) {
    final analysis = (json['analysisResult'] ?? {}) as Map<String, dynamic>;
    final seg = (analysis['segmentationResult'] ?? {}) as Map<String, dynamic>;
    final items = ((seg['detected_items'] ?? []) as List)
        .map((e) => DetectedItem.fromJson(e as Map<String, dynamic>))
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

    return AnalysisResult(
      status: (json['status'] ?? 'PENDING').toString(),
      errorMessage: (json['errorMessage']
          ?? analysis['errorMessage']
          ?? analysis['error']
          ?? seg['error'])
          ?.toString(),
      adviceReport: (analysis['adviceReport'] ?? '暂无建议').toString(),
      detectedItems: items,
      totalCalories: ((analysis['totalCalories'] as num?)?.toDouble()) ?? total,
      kcalRange: parseKcalRange(analysis['kcalRange']),
      confidenceLevel: analysis['confidenceLevel']?.toString(),
      workflowMode: analysis['workflowMode']?.toString(),
      workflowTrace: parseStringList(analysis['workflowTrace']),
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
