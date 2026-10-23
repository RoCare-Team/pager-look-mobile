import '../../core/network/api_client.dart';

/// Port of `veriwork-frontend/src/api/auth.js`.
class AuthApi {
  AuthApi(this._api);
  final ApiClient _api;

  /// Returns `{ phone, otpLength, resendInSeconds, expiresInMinutes, message }`.
  Future<dynamic> sendEmployeeOtp(String phone) =>
      _api.post('/auth/employee/otp/send', body: {'phone': phone}, auth: false);

  /// Returns `{ accessToken, refreshToken, user, profile, isNewUser, homeRoute }`.
  Future<dynamic> verifyEmployeeOtp(String phone, String code) =>
      _api.post('/auth/employee/otp/verify', body: {'phone': phone, 'code': code}, auth: false);

  Future<dynamic> loginEmployeeGoogle(String idToken) =>
      _api.post('/auth/employee/google', body: {'idToken': idToken}, auth: false);

  /// Returns `{ accessToken, refreshToken, user, company, homeRoute }`.
  Future<dynamic> loginEnterprise(String email, String password) =>
      _api.post('/auth/enterprise/login', body: {'email': email, 'password': password}, auth: false);

  Future<dynamic> loginAdmin(String email, String password) =>
      _api.post('/auth/admin/login', body: {'email': email, 'password': password}, auth: false);

  /// Body built with [buildEnterpriseRegisterPayload].
  Future<dynamic> registerEnterprise(Map<String, dynamic> payload) =>
      _api.post('/auth/enterprise/register', body: payload, auth: false);

  Future<dynamic> changePassword(String currentPassword, String newPassword) => _api.post(
        '/auth/change-password',
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );

  Future<dynamic> requestPasswordReset(String email) =>
      _api.post('/auth/forgot-password', body: {'email': email}, auth: false);

  Future<dynamic> resetPassword(String token, String newPassword) => _api.post(
        '/auth/reset-password',
        body: {'token': token, 'newPassword': newPassword},
        auth: false,
      );

  Future<dynamic> logout(String? refreshToken) => _api.post(
        '/auth/logout',
        body: refreshToken != null ? {'refreshToken': refreshToken} : <String, dynamic>{},
        auth: false,
      );
}

/// `+<cc><digits>` — same as the web's `normalizePhone`.
String normalizePhone(String countryCode, String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  var cc = countryCode.replaceAll(RegExp(r'\D'), '');
  if (cc.isEmpty) cc = '91';
  return '+$cc$digits';
}

/// Same as the web's `normalizeRegisterPhone`.
String normalizeRegisterPhone(String phone) {
  final trimmed = phone.trim();
  if (trimmed.startsWith('+')) return trimmed.replaceAll(RegExp(r'\s'), '');
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '+91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
  return trimmed;
}

/// Payload for `POST /auth/enterprise/register` — mirrors `buildEnterpriseRegisterPayload`.
Map<String, dynamic> buildEnterpriseRegisterPayload({
  required String email,
  required String password,
  required String confirmPassword,
  required String companyLegalName,
  String? companyType,
  required String industry,
  required String companySize,
  required String workEmail,
  required String contactName,
  required String phone,
  required String country,
  String? city,
  String? state,
  String? pincode,
  String? locality,
  String? brn,
  String? taxId,
}) {
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  return {
    'email': email.trim(),
    'password': password,
    'confirmPassword': confirmPassword,
    'companyLegalName': companyLegalName.trim(),
    if (clean(companyType) != null) 'companyType': companyType,
    'industry': industry,
    'companySize': companySize,
    'workEmail': workEmail.trim(),
    'contactName': contactName.trim(),
    'phone': normalizeRegisterPhone(phone),
    'country': country.trim(),
    'city': city?.trim() ?? '',
    if (clean(state) != null) 'state': state!.trim(),
    if (clean(pincode) != null) 'pincode': pincode!.replaceAll(RegExp(r'\D'), ''),
    if (clean(locality) != null) 'locality': locality!.trim(),
    if (clean(brn) != null) 'brn': brn!.trim().toUpperCase(),
    if (clean(taxId) != null) 'taxId': taxId!.trim().toUpperCase(),
  };
}
