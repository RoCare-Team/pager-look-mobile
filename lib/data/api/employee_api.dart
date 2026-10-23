import '../../core/network/api_client.dart';
import '../../core/network/upload.dart';

/// Port of `veriwork-frontend/src/api/employee.js` (incl. DigiLocker).
class EmployeeApi {
  EmployeeApi(this._api);
  final ApiClient _api;

  Future<dynamic> fetchProfile() => _api.get('/employee/profile');

  Future<dynamic> updateProfile(Map<String, dynamic> body) => _api.patch('/employee/profile', body: body);

  Future<dynamic> fetchCompanySuggestions(String q) =>
      _api.get('/employee/suggestions/companies', query: {'q': q});

  Future<dynamic> fetchRoleSuggestions(String q) => _api.get('/employee/suggestions/roles', query: {'q': q});

  /// Web: `uploadEmployeeProfilePhoto` — field `photo`, returns `{ url | photoUrl }`.
  Future<dynamic> uploadProfilePhoto(PickedDoc photo) async =>
      _api.post('/employee/profile/photo', body: await buildFormData(files: {'photo': photo}));

  Future<dynamic> fetchScore() => _api.get('/employee/score');

  Future<dynamic> fetchVerificationStatus() => _api.get('/employee/verification/status');

  Future<dynamic> fetchAadhaarSubmission() => _api.get('/employee/verification/aadhaar');

  /// Manual Aadhaar KYC — card images + typed details go to the admin queue.
  Future<dynamic> submitAadhaar({
    required String aadhaarNumber,
    required String nameOnAadhaar,
    String dobOnAadhaar = '',
    String genderOnAadhaar = '',
    String addressOnAadhaar = '',
    required PickedDoc frontImage,
    required PickedDoc backImage,
  }) async {
    final form = await buildFormData(
      fields: {
        'aadhaarNumber': aadhaarNumber,
        'nameOnAadhaar': nameOnAadhaar,
        'dobOnAadhaar': dobOnAadhaar,
        'genderOnAadhaar': genderOnAadhaar,
        'addressOnAadhaar': addressOnAadhaar,
        'consent': 'true',
      },
      files: {'frontImage': frontImage, 'backImage': backImage},
    );
    return _api.post('/employee/verification/aadhaar', body: form);
  }

  /// Aadhaar mismatch → copy Aadhaar name/DOB/gender onto the profile.
  /// Returns `{ submission, profile }`.
  Future<dynamic> applyAadhaarDetails() => _api.post('/employee/verification/aadhaar/use-aadhaar-details');

  /// `selfie` is matched against the approved Aadhaar photo; `poses` are the
  /// left/right frames proving the head moved.
  Future<dynamic> verifyBiometric(PickedDoc? selfie, [List<PickedDoc> poses = const []]) async {
    final form = await buildFormData(files: {'selfie': selfie, 'poses': poses});
    return _api.post('/employee/verification/biometric', body: form);
  }

  Future<dynamic> fetchJobs() => _api.get('/employee/jobs');

  Future<dynamic> createJob(Map<String, dynamic> body) => _api.post('/employee/jobs', body: body);

  Future<dynamic> uploadJobDocument(String jobId, PickedDoc file, {String? documentType}) async {
    final form = await buildFormData(
      fields: {if (documentType != null && documentType.isNotEmpty) 'documentType': documentType},
      files: {'document': file},
    );
    return _api.post('/employee/jobs/$jobId/documents', body: form);
  }

  Future<dynamic> fetchActivity([String filter = 'all']) =>
      _api.get('/employee/activity', query: {if (filter != 'all') 'filter': filter});

  Future<dynamic> updateActivity(String id, String status) =>
      _api.patch('/employee/activity/$id', body: {'status': status});

  Future<dynamic> fetchVault() => _api.get('/employee/vault');

  Future<dynamic> uploadVaultDocument({
    required String category,
    required String name,
    PickedDoc? file,
    String? size,
  }) async {
    final form = await buildFormData(
      fields: {'category': category, 'name': name, if (size != null && size.isNotEmpty) 'size': size},
      files: {'document': file},
    );
    return _api.post('/employee/vault', body: form);
  }

  Future<dynamic> fetchSettings() => _api.get('/employee/settings');

  Future<dynamic> updateSettings(Map<String, dynamic> body) => _api.patch('/employee/settings', body: body);

  Future<dynamic> fetchProfessionalId() => _api.get('/employee/professional-id');

  Future<dynamic> fetchInvitations() => _api.get('/employee/invitations');

  Future<dynamic> acceptInvitation(String id) => _api.post('/employee/invitations/$id/accept');

  Future<dynamic> rejectInvitation(String id) => _api.post('/employee/invitations/$id/reject');

  Future<dynamic> fetchAccessRequests() => _api.get('/employee/access-requests');

  Future<dynamic> approveAccessRequest(String id) => _api.post('/employee/access-request/$id/approve');

  Future<dynamic> rejectAccessRequest(String id) => _api.post('/employee/access-request/$id/reject');

  Future<dynamic> fetchEndorsements() => _api.get('/employee/endorsements');

  Future<dynamic> createEndorsement(Map<String, dynamic> body) => _api.post('/employee/endorse', body: body);

  Future<dynamic> fetchJobVerification(String jobId) => _api.get('/employee/jobs/$jobId/verification');

  Future<dynamic> createJobVerificationRequest(String jobId, Map<String, dynamic> body) =>
      _api.post('/employee/jobs/$jobId/verification-request', body: body);

  /// Nudge an unanswered request — optionally with corrected HR emails.
  Future<dynamic> resendJobVerificationRequest(String requestId, Map<String, dynamic> body) =>
      _api.post('/employee/verification-requests/$requestId/resend', body: body);

  Future<dynamic> fetchVerificationRequests() => _api.get('/employee/verification/requests');

  Future<dynamic> approveVerificationConsent(String id) =>
      _api.post('/employee/verification-requests/$id/approve-consent');

  Future<dynamic> rejectVerificationConsent(String id, [Map<String, dynamic>? body]) =>
      _api.post('/employee/verification-requests/$id/reject-consent', body: body);

  Future<dynamic> fetchVerificationTags() => _api.get('/employee/verification/tags');

  Future<dynamic> fetchSmtpSettings() => _api.get('/employee/settings/smtp');

  Future<dynamic> updateSmtpSettings(Map<String, dynamic> body) => _api.put('/employee/settings/smtp', body: body);

  Future<dynamic> sendSmtpTest([Map<String, dynamic> body = const {}]) =>
      _api.post('/employee/settings/smtp/test', body: body);

  // ── DigiLocker ──────────────────────────────────────────────────────────
  Future<dynamic> fetchDigiLockerConnection() => _api.get('/digilocker/connection');

  /// Returns `{ authorizationUrl }`. purpose `aadhaar` runs e-Aadhaar KYC on
  /// return; `settings` only links the account. `client: mobile` makes the
  /// callback return through the app's `pagerlook://` deep link, not the web.
  Future<dynamic> startDigiLockerConnect([String purpose = 'aadhaar']) =>
      _api.post('/digilocker/connect', body: {'purpose': purpose, 'client': 'mobile'});

  Future<dynamic> disconnectDigiLocker() => _api.delete('/digilocker/connection');
}
