import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileContextSnapshot {
  const ProfileContextSnapshot({
    this.age,
    this.heightCm,
    this.weightKg,
    this.gender,
    this.activityLevel,
  });

  final int? age;
  final int? heightCm;
  final double? weightKg;
  final String? gender;
  final String? activityLevel;

  factory ProfileContextSnapshot.fromJson(Map<String, dynamic> json) {
    return ProfileContextSnapshot(
      age: (json['age'] as num?)?.toInt(),
      heightCm: (json['heightCm'] as num?)?.toInt(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      gender: json['gender']?.toString(),
      activityLevel: json['activityLevel']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'gender': gender,
        'activityLevel': activityLevel,
      };
}

class ProfileContextService {
  ProfileContextService._();

  static final ProfileContextService instance = ProfileContextService._();

  static const _storageKey = 'profile_context_snapshot_v1';

  Future<ProfileContextSnapshot> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const ProfileContextSnapshot();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ProfileContextSnapshot.fromJson(decoded);
      }
      if (decoded is Map) {
        return ProfileContextSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return const ProfileContextSnapshot();
    }

    return const ProfileContextSnapshot();
  }

  Future<void> saveSnapshot(ProfileContextSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> clearSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}