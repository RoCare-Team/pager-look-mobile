import '../../core/network/api_client.dart';
import '../../core/network/upload.dart';

/// Port of `veriwork-frontend/src/api/enterprise.js` — both the
/// `/enterprise/*` (onboarding, QR, join requests) and `/company/*` (portal) APIs.
class EnterpriseApi {
  EnterpriseApi(this._api);
  final ApiClient _api;

  // ── Onboarding & application ────────────────────────────────────────────
  Future<dynamic> fetchOnboarding() => _api.get('/enterprise/onboarding');

  Future<dynamic> updateBasicInfo(Map<String, dynamic> body) =>
      _api.patch('/enterprise/onboarding/basic-info', body: body);

  Future<dynamic> updateRegistration(Map<String, dynamic> body) =>
      _api.patch('/enterprise/onboarding/registration', body: body);

  /// [docType] is the backend key — see [enterpriseDocTypes]. Returns `{ url, documents }`.
  Future<dynamic> uploadOnboardingDocument(String docType, PickedDoc file) async => _api.post(
        '/enterprise/onboarding/documents/$docType',
        body: await buildFormData(files: {'document': file}),
      );

  Future<dynamic> submitOnboarding([bool certified = true]) =>
      _api.post('/enterprise/onboarding/submit', body: {'certified': certified});

  Future<dynamic> fetchApplicationStatus() => _api.get('/enterprise/application/status');

  Future<dynamic> resubmitApplication() => _api.post('/enterprise/application/resubmit', body: <String, dynamic>{});

  Future<dynamic> fetchApplicationMessages() => _api.get('/enterprise/application/messages');

  Future<dynamic> postApplicationMessage(String body) =>
      _api.post('/enterprise/application/messages', body: {'body': body});

  // ── Enterprise portal ───────────────────────────────────────────────────
  Future<dynamic> fetchDashboard() => _api.get('/enterprise/dashboard');

  Future<dynamic> fetchWorkforce() => _api.get('/enterprise/workforce');

  Future<dynamic> fetchJoinRequests() => _api.get('/enterprise/join-requests');

  Future<dynamic> updateJoinRequest(String id, String status) =>
      _api.patch('/enterprise/join-requests/$id', body: {'status': status});

  Future<dynamic> fetchQrOnboarding() => _api.get('/enterprise/qr-onboarding');

  Future<dynamic> createQrOnboarding(Map<String, dynamic> body) => _api.post('/enterprise/qr-onboarding', body: body);

  Future<dynamic> setQrOnboardingActive(String id, bool isActive) =>
      _api.patch('/enterprise/qr-onboarding/$id/active', body: {'isActive': isActive});

  Future<dynamic> deleteQrOnboarding(String id) => _api.delete('/enterprise/qr-onboarding/$id');

  // ── Company: team & employees ───────────────────────────────────────────
  Future<dynamic> fetchTeam() => _api.get('/company/team');

  Future<dynamic> fetchWorkspace() => _api.get('/company/workspace');

  /// The backend route is `GET /company/team/:department` (companyRoutes.js).
  /// The web calls `/company/team/department/:dept`, which the backend does
  /// not serve (404) — the mobile app uses the real route.
  Future<dynamic> fetchTeamDepartment(String department) =>
      _api.get('/company/team/${Uri.encodeComponent(department)}');

  Future<dynamic> inviteEmployee(Map<String, dynamic> body) => _api.post('/company/invite-employee', body: body);

  Future<dynamic> searchCompanyEmployees(String q) => _api.get('/company/employees/search', query: {'q': q});

  Future<dynamic> fetchPendingInvitations() => _api.get('/company/invitations/pending');

  Future<dynamic> fetchEmployeeProfile(String employeeId) => _api.get('/company/employees/$employeeId/profile');

  Future<dynamic> fetchEmployeeDocuments(String employeeId) => _api.get('/company/employees/$employeeId/documents');

  Future<dynamic> fetchEmployeeAccessStatus(String employeeId) =>
      _api.get('/company/employees/$employeeId/access-status');

  Future<dynamic> revokeEmployeeAccess(String employeeId, [Map<String, dynamic> body = const {}]) =>
      _api.post('/company/employees/$employeeId/revoke-access', body: body);

  Future<dynamic> assignEmployeeOnboarding(String employeeId, Map<String, dynamic> body) =>
      _api.patch('/company/employees/$employeeId/onboarding', body: body);

  Future<dynamic> fetchEmployeeJobVerificationRecord(String employeeId, String jobId) =>
      _api.get('/company/employees/$employeeId/jobs/$jobId/verification-record');

  // ── Company: access requests ────────────────────────────────────────────
  /// `status` uses the UI vocabulary; `accepted` is sent as `approved` (web parity).
  Future<dynamic> fetchAccessRequests({String status = 'all', int page = 1, int limit = 20}) => _api.get(
        '/company/access-requests',
        query: {
          'page': '$page',
          'limit': '$limit',
          if (status != 'all') 'status': status == 'accepted' ? 'approved' : status,
        },
      );

  Future<dynamic> createAccessRequest(Map<String, dynamic> body) => _api.post('/company/access-request', body: body);

  Future<dynamic> fetchAccessRequestTypes() => _api.get('/company/access-request-types');

  Future<dynamic> fetchInsights() => _api.get('/company/insights');

  // ── Company: employment verification ────────────────────────────────────
  Future<dynamic> createVerificationRequest(Map<String, dynamic> body) =>
      _api.post('/company/verification-request', body: body);

  Future<dynamic> searchPlatformCompanies(String q) =>
      _api.get('/company/platform-companies/search', query: {'q': q});

  Future<dynamic> fetchVerificationOutgoing() => _api.get('/company/verification-requests/outgoing');

  Future<dynamic> fetchVerificationIncoming() => _api.get('/company/verification-requests/incoming');

  Future<dynamic> approveVerificationRequest(String id, [Map<String, dynamic> body = const {}]) =>
      _api.post('/company/verification-requests/$id/approve', body: body);

  Future<dynamic> rejectVerificationRequest(String id, [Map<String, dynamic> body = const {}]) =>
      _api.post('/company/verification-requests/$id/reject', body: body);

  Future<dynamic> completeEmailVerification(String id, Map<String, dynamic> body) =>
      _api.post('/company/verification-requests/$id/complete-email', body: body);

  Future<dynamic> resendVerificationEmail(String id) =>
      _api.post('/company/verification-requests/$id/resend-email', body: <String, dynamic>{});

  Future<dynamic> reviewHrResponse(String id, Map<String, dynamic> body) =>
      _api.post('/company/verification-requests/$id/review-hr-response', body: body);

  Future<dynamic> confirmDocumentVerification(String id, [Map<String, dynamic> body = const {}]) =>
      _api.post('/company/verification-requests/$id/confirm-document-verification', body: body);

  // ── Company: audit, roles, users, settings ──────────────────────────────
  Future<dynamic> fetchAuditLogs({String action = '', int page = 1, int limit = 20}) => _api.get(
        '/company/audit-logs',
        query: {'page': '$page', 'limit': '$limit', if (action.isNotEmpty) 'action': action},
      );

  /// `{ companyRole, roleLabel, permissions: {module: none|view|manage}, assignableRoles }`.
  Future<dynamic> fetchMyPermissions() => _api.get('/company/me/permissions');

  Future<dynamic> fetchRoles() => _api.get('/company/roles');

  Future<dynamic> createCompanyRole(Map<String, dynamic> body) => _api.post('/company/roles', body: body);

  Future<dynamic> updateCompanyRole(String roleId, Map<String, dynamic> body) =>
      _api.patch('/company/roles/$roleId', body: body);

  Future<dynamic> deleteCompanyRole(String roleId) => _api.delete('/company/roles/$roleId');

  Future<dynamic> fetchCompanyUsers() => _api.get('/company/users');

  Future<dynamic> createCompanyUser(Map<String, dynamic> body) => _api.post('/company/users', body: body);

  Future<dynamic> resetCompanyUserPassword(String userId, String password) =>
      _api.post('/company/users/$userId/password', body: {'password': password});

  Future<dynamic> inviteCompanyUser(Map<String, dynamic> body) => _api.post('/company/users/invite', body: body);

  Future<dynamic> revokeCompanyUserInvite(String inviteId) =>
      _api.post('/company/users/invites/$inviteId/revoke', body: <String, dynamic>{});

  /// body is `{ companyRole }` for a preset, or `{ companyRoleId }` for a custom role.
  Future<dynamic> updateCompanyUserRole(String userId, Map<String, dynamic> body) =>
      _api.patch('/company/users/$userId/role', body: body);

  Future<dynamic> removeCompanyUser(String userId) => _api.delete('/company/users/$userId');

  Future<dynamic> fetchSmtpSettings() => _api.get('/company/settings/smtp');

  Future<dynamic> updateSmtpSettings(Map<String, dynamic> body) => _api.put('/company/settings/smtp', body: body);

  Future<dynamic> sendSmtpTest([Map<String, dynamic> body = const {}]) =>
      _api.post('/company/settings/smtp/test', body: body);
}

/// UI document id → backend docType (web: `ENTERPRISE_DOC_TYPES`).
const Map<String, String> enterpriseDocTypes = {
  'incorporation': 'incorporation',
  'registration': 'registration',
  'taxCertificate': 'tax',
  'addressProof': 'addressProof',
  'signatoryId': 'signatoryId',
  'bankLetter': 'bankLetter',
};

String enterpriseDocType(String docId) => enterpriseDocTypes[docId] ?? docId;

/// Read an uploaded document out of the onboarding `documents` map — the UI id
/// and stored key differ for `taxCertificate`/`tax` (web: `getUploadedDocument`).
dynamic uploadedEnterpriseDocument(Map? documents, String docId) {
  if (documents == null) return null;
  return documents[docId] ?? documents[enterpriseDocType(docId)];
}
