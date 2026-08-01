import 'package:shared_preferences/shared_preferences.dart';

class AccessCodeService {
  AccessCodeService._();

  static final AccessCodeService instance = AccessCodeService._();
  static const _storageKey = 'nutri_access_code_v1';
  static const _compiledFallback = String.fromEnvironment(
    'NUTRI_DEMO_ACCESS_CODE',
    defaultValue: '',
  );

  bool _loaded = false;
  String _accessCode = '';

  String get accessCode => _accessCode;
  bool get hasAccessCode => _accessCode.isNotEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _accessCode = (prefs.getString(_storageKey) ?? _compiledFallback).trim();
    _loaded = true;
  }

  Future<void> save(String accessCode) async {
    final normalized = accessCode.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, normalized);
    _accessCode = normalized;
    _loaded = true;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _accessCode = '';
    _loaded = true;
  }
}
