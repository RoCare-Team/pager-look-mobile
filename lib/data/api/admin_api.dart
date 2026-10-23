import '../../core/network/api_client.dart';

/// Port of `veriwork-frontend/src/api/admin.js` (live API only — the web's
/// offline "dev admin" mock is a browser-only dev aid and is not ported).
///
/// Responses are returned raw; the admin screens normalise them the same way
/// the web's `adminCompanyUtils` / `adminEmployeeUtils` do.
class AdminApi {
  AdminApi(this._api);
  final ApiClient _api;

  Future<dynamic> fetchDashboard() => _api.get('/admin/dashboard');

  /// status: submitted | approved | rejected | null (all).
  Future<dynamic> fetchCompanies([String? status]) =>
      _api.get('/admin/companies', query: {if (status != null && status != 'all') 'status': status});

  Future<dynamic> fetchCompany(String id) => _api.get('/admin/companies/$id');

  Future<dynamic> reviewCompany(String id, String status, [String? reason]) => _api.patch(
        '/admin/companies/$id/review',
        body: {'status': status, if (reason != null && reason.isNotEmpty) 'reason': reason},
      );

  /// Approve or reject a single uploaded document.
  Future<dynamic> reviewCompanyDocument(String id, {required String documentKey, required String status, String? reason}) =>
      _api.patch(
        '/admin/companies/$id/documents/review',
        body: {
          'documentKey': documentKey,
          'status': status,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

  Future<dynamic> fetchCompanyMessages(String id) => _api.get('/admin/companies/$id/messages');

  Future<dynamic> postCompanyMessage(String id, String body) =>
      _api.post('/admin/companies/$id/messages', body: {'body': body});

  Future<dynamic> fetchEmployees({String status = 'all', String q = ''}) => _api.get(
        '/admin/employees',
        query: {if (status != 'all') 'status': status, if (q.trim().isNotEmpty) 'q': q.trim()},
      );

  Future<dynamic> fetchEmployee(String id) => _api.get('/admin/employees/$id');

  /// Reversible deactivate/restore.
  Future<dynamic> setEmployeeStatus(String id, bool isActive) =>
      _api.patch('/admin/employees/$id/status', body: {'isActive': isActive});

  /// Permanent purge. [confirm] must be the employee's name or PagerLook ID.
  Future<dynamic> deleteEmployee(String id, String confirm) =>
      _api.delete('/admin/employees/$id', body: {'confirm': confirm});

  Future<dynamic> fetchAadhaarRequests({String status = 'pending', String q = ''}) => _api.get(
        '/admin/aadhaar-requests',
        query: {'status': status, if (q.trim().isNotEmpty) 'q': q.trim()},
      );

  Future<dynamic> fetchAadhaarRequest(String id) => _api.get('/admin/aadhaar-requests/$id');

  Future<dynamic> reviewAadhaarRequest(String id, {required String status, String? reason, String? notes}) =>
      _api.patch(
        '/admin/aadhaar-requests/$id/review',
        body: {
          'status': status,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );

  Future<dynamic> fetchVerificationRequests({String status = 'all', String q = ''}) => _api.get(
        '/admin/verification-requests',
        query: {'status': status, if (q.trim().isNotEmpty) 'q': q.trim()},
      );

  Future<dynamic> resendVerificationRequest(String id, {List<dynamic>? hrContacts, String? hrName}) => _api.post(
        '/admin/verification-requests/$id/resend',
        body: {
          if (hrContacts != null && hrContacts.isNotEmpty) 'hrContacts': hrContacts,
          if (hrName != null && hrName.isNotEmpty) 'hrName': hrName,
        },
      );

  Future<dynamic> fetchDemoRequests({String status = 'all', String q = ''}) => _api.get(
        '/admin/demo-requests',
        query: {'status': status, if (q.isNotEmpty) 'q': q},
      );

  Future<dynamic> updateDemoRequest(String id, Map<String, dynamic> body) =>
      _api.patch('/admin/demo-requests/$id', body: body);
}
