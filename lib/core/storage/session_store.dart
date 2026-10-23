import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session in the platform keystore (iOS Keychain / Android
/// EncryptedSharedPreferences) — the mobile counterpart of the web's
/// `authStorage.js`. Values are cached in memory so the HTTP layer can read
/// tokens synchronously.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'veriwork_access_token';
  static const _refreshKey = 'veriwork_refresh_token';
  static const _userKey = 'veriwork_user';
  static const _profileKey = 'veriwork_profile';
  static const _companyKey = 'veriwork_company';
  static const _invitationKey = 'veriwork_invitation';

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? company;
  Map<String, dynamic>? invitation;

  Future<void> load() async {
    try {
      final all = await _storage.readAll();
      accessToken = all[_accessKey];
      refreshToken = all[_refreshKey];
      user = _decode(all[_userKey]);
      profile = _decode(all[_profileKey]);
      company = _decode(all[_companyKey]);
      invitation = _decode(all[_invitationKey]);
    } catch (_) {
      // A corrupted keystore (e.g. after an OS restore) must not brick the app.
      await clear();
    }
  }

  Future<void> setTokens({String? access, String? refresh}) async {
    if (access != null && access.isNotEmpty) {
      accessToken = access;
      await _storage.write(key: _accessKey, value: access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      refreshToken = refresh;
      await _storage.write(key: _refreshKey, value: refresh);
    }
  }

  Future<void> setUser(Map<String, dynamic>? value) => _writeJson(_userKey, value, (v) => user = v);
  Future<void> setProfile(Map<String, dynamic>? value) => _writeJson(_profileKey, value, (v) => profile = v);
  Future<void> setCompany(Map<String, dynamic>? value) => _writeJson(_companyKey, value, (v) => company = v);
  Future<void> setInvitation(Map<String, dynamic>? value) => _writeJson(_invitationKey, value, (v) => invitation = v);

  /// Clears the session. The pending invitation survives a logout on purpose —
  /// the web keeps it in sessionStorage across the OTP sign-in for the same reason.
  Future<void> clear({bool keepInvitation = true}) async {
    accessToken = null;
    refreshToken = null;
    user = null;
    profile = null;
    company = null;
    for (final key in [_accessKey, _refreshKey, _userKey, _profileKey, _companyKey]) {
      await _storage.delete(key: key);
    }
    if (!keepInvitation) await setInvitation(null);
  }

  Future<void> _writeJson(
    String key,
    Map<String, dynamic>? value,
    void Function(Map<String, dynamic>?) assign,
  ) async {
    assign(value);
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: jsonEncode(value));
    }
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
