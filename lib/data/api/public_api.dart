import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/upload.dart';

/// Port of `veriwork-frontend/src/api/public.js` — unauthenticated endpoints.
class PublicApi {
  PublicApi(this._api);
  final ApiClient _api;

  static String _e(String v) => Uri.encodeComponent(v);

  Future<dynamic> fetchPublicProfile(String slug) => _api.get('/public/profile/${_e(slug)}', auth: false);

  Future<dynamic> requestPublicProfileAccess(String slug, Map<String, dynamic> body) =>
      _api.post('/public/profile/${_e(slug)}/request-access', body: body, auth: false);

  Future<dynamic> fetchEmployeeInvitation(String token) =>
      _api.get('/public/employee-invitation/${_e(token)}', auth: false);

  Future<dynamic> fetchEmploymentVerification(String token) =>
      _api.get('/public/employment-verification/${_e(token)}', auth: false);

  Future<dynamic> submitEmploymentVerification(String token, Map<String, dynamic> body) =>
      _api.post('/public/employment-verification/${_e(token)}', body: body, auth: false);

  Future<dynamic> uploadVerificationDocument(String token, PickedDoc file) async {
    final FormData form = await buildFormData(files: {'document': file});
    return _api.post('/public/employment-verification/${_e(token)}/document', body: form, auth: false);
  }

  Future<dynamic> fetchQrJoinInfo(String code) => _api.get('/public/qr/${_e(code)}', auth: false);

  Future<dynamic> submitQrJoinRequest(String code, Map<String, dynamic> body) =>
      _api.post('/public/qr/${_e(code)}/join', body: body, auth: false);

  Future<dynamic> fetchCompanyInvite(String token) => _api.get('/public/company-invite/${_e(token)}', auth: false);

  Future<dynamic> acceptCompanyInvite(String token, String password) =>
      _api.post('/public/company-invite/${_e(token)}/accept', body: {'password': password}, auth: false);

  /// "Book a demo" — lands in the admin console as a lead.
  Future<dynamic> submitDemoRequest(Map<String, dynamic> body) =>
      _api.post('/public/demo-requests', body: body, auth: false);
}
