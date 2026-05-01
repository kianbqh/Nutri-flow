import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _sessionKey = 'auth_session_v1';

  AuthSession? _session;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _session = AuthSession.fromJson(decoded);
        } else if (decoded is Map) {
          _session = AuthSession.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        _session = null;
      }
    }
    _loaded = true;
  }

  bool get isSignedIn => _session != null;

  AuthSession? get currentSession => _session;

  int? get currentUserId => _session?.userId;

  String? get currentPhone => _session?.phone;

  Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    _session = session;
    _loaded = true;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _session = null;
    _loaded = true;
  }
}