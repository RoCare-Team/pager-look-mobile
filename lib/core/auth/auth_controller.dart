import 'package:flutter/foundation.dart';

import '../../data/api/auth_api.dart';
import '../../data/api/employee_api.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/session_store.dart';
import '../utils/json.dart';
import 'home_routes.dart';

/// Session state for the whole app — the mobile counterpart of the web's
/// `AuthContext`. It is a [ChangeNotifier] so GoRouter re-runs its guards
/// whenever the session changes.
class AuthController extends ChangeNotifier {
  AuthController({
    required SessionStore store,
    required ApiClient api,
    required AuthApi authApi,
    required EmployeeApi employeeApi,
  })  : _store = store,
        _authApi = authApi,
        _employeeApi = employeeApi {
    api.onSessionExpired = _handleSessionExpired;
  }

  final SessionStore _store;
  final AuthApi _authApi;
  final EmployeeApi _employeeApi;

  bool _booting = true;
  bool get booting => _booting;

  /// Set when the refresh token was rejected, so the UI can explain the logout.
  bool sessionExpired = false;

  Map<String, dynamic>? get user => _store.user;
  Map<String, dynamic>? get profile => _store.profile;
  Map<String, dynamic>? get company => _store.company;

  String? get role => strOrNull(user?['role']);
  bool get isEmployee => role == 'employee';
  bool get isEnterprise => role == 'enterprise_admin';
  bool get isAdmin => const ['platform_admin', 'super_admin', 'admin'].contains(role);

  bool get hasToken => (_store.accessToken ?? '').isNotEmpty;
  bool get isAuthenticated => user != null && hasToken && (isEmployee || isEnterprise || isAdmin);

  String get userId => str(user?['id'] ?? user?['_id']);

  /// Where a signed-in user belongs, or `/` for guests.
  String get homeRoute {
    if (!isAuthenticated) return '/';
    if (isEmployee) return employeeHomeRoute(profile);
    if (isEnterprise) return enterpriseHomeRoute(company);
    return '/admin/dashboard';
  }

  /// Restore the stored session; for employees refresh the profile, as the web does.
  Future<void> bootstrap() async {
    await _store.load();
    if (isAuthenticated && isEmployee) {
      try {
        final fresh = await _employeeApi.fetchProfile();
        await _store.setProfile(asMap(fresh));
      } on ApiException catch (e) {
        // Offline: keep the cached session. Anything else means the session is unusable.
        if (!e.isNetwork) await _store.clear();
      } catch (_) {
        await _store.clear();
      }
    } else if (!isAuthenticated && hasToken) {
      await _store.clear();
    }
    _booting = false;
    notifyListeners();
  }

  /// Response of OTP verify / Google login.
  Future<void> loginEmployee(Map<String, dynamic> data) async {
    await _store.setTokens(access: strOrNull(data['accessToken']), refresh: strOrNull(data['refreshToken']));
    await _store.setUser(asMap(data['user']));
    await _store.setProfile(data['profile'] == null ? null : asMap(data['profile']));
    await _store.setCompany(null);
    sessionExpired = false;
    notifyListeners();
  }

  /// Response of enterprise login / register / company-invite accept.
  Future<void> loginEnterprise(Map<String, dynamic> data) async {
    await _store.setTokens(access: strOrNull(data['accessToken']), refresh: strOrNull(data['refreshToken']));
    if (data['user'] != null) await _store.setUser(asMap(data['user']));
    if (data['company'] != null) await _store.setCompany(asMap(data['company']));
    await _store.setProfile(null);
    sessionExpired = false;
    notifyListeners();
  }

  Future<void> loginAdmin(Map<String, dynamic> data) async {
    await _store.setTokens(
      access: strOrNull(data['accessToken'] ?? data['token']),
      refresh: strOrNull(data['refreshToken']),
    );
    final adminUser = asMap(data['user']);
    adminUser['role'] = strOrNull(adminUser['role']) ?? 'platform_admin';
    await _store.setUser(adminUser);
    await _store.setProfile(null);
    await _store.setCompany(null);
    sessionExpired = false;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic>? next) async {
    await _store.setProfile(next);
    notifyListeners();
  }

  /// Merge fields into the stored company (e.g. a new `approvalStatus`).
  Future<void> updateCompany(Map<String, dynamic>? next, {bool merge = false}) async {
    final value = merge && next != null ? {...?company, ...next} : next;
    await _store.setCompany(value);
    notifyListeners();
  }

  /// Re-fetch the employee profile and store it; returns the fresh profile.
  Future<Map<String, dynamic>> refreshEmployeeProfile() async {
    final fresh = asMap(await _employeeApi.fetchProfile());
    await updateProfile(fresh);
    return fresh;
  }

  Future<void> logout() async {
    final refreshToken = _store.refreshToken;
    try {
      if (refreshToken != null) await _authApi.logout(refreshToken);
    } catch (_) {
      // Logging out locally must never fail because the network did.
    }
    await _store.clear();
    notifyListeners();
  }

  // ── Invitation carried from an invite link into signup (web: invitationSession) ──
  Map<String, String> get invitation => asMap(_store.invitation).map((k, v) => MapEntry(k, str(v)));

  bool get hasInvitation => (invitation['token'] ?? '').isNotEmpty;

  /// Keys: token, email, companyName, name, phone, department, designation.
  Future<void> setInvitation(Map<String, String> details) async {
    final merged = {...invitation};
    details.forEach((k, v) {
      if (v.isNotEmpty) merged[k] = v;
    });
    await _store.setInvitation(merged);
  }

  Future<void> clearInvitation() => _store.setInvitation(null);

  void _handleSessionExpired() {
    sessionExpired = true;
    notifyListeners();
  }
}
