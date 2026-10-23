/// Ports of the web's admin helpers:
/// `utils/adminCompanyUtils.js`, `utils/adminEmployeeUtils.js`,
/// `utils/hrContacts.js` and the bits of `utils/enterpriseCompanyTypes.js` /
/// `utils/enterpriseValidators.js` the admin console reads.
library;

import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';

/// Family key for the admin list screens that filter by status + search.
typedef AdminListQuery = ({String status, String q});

/// First non-empty string among [values] (JS `a || b || c`).
String? _first(Iterable<Object?> values) {
  for (final v in values) {
    final s = strOrNull(v);
    if (s != null) return s;
  }
  return null;
}

/// First value that is a map (JS `a || b || {}` over objects).
Map<String, dynamic> _firstMap(Iterable<Object?> values) {
  for (final v in values) {
    if (v is Map) return asMap(v);
  }
  return <String, dynamic>{};
}

// ── Companies ───────────────────────────────────────────────────────────────

/// Row of the admin companies list (web: `normalizeAdminListItem`).
class AdminCompanyListItem {
  const AdminCompanyListItem({
    required this.id,
    required this.name,
    required this.industry,
    required this.contact,
    required this.phone,
    required this.adminEmail,
    required this.workEmail,
    required this.status,
    required this.submittedAt,
    required this.raw,
  });

  final String id;
  final String name;
  final String industry;
  final String contact;
  final String phone;
  final String adminEmail;
  final String workEmail;
  final String status;
  final Object? submittedAt;
  final Map<String, dynamic> raw;

  factory AdminCompanyListItem.fromJson(Object? json) {
    final item = asMap(json);
    final company = item['company'] is Map ? asMap(item['company']) : item;
    final admin = asMap(item['admin']);
    final onboarding = asMap(item['onboarding']);

    return AdminCompanyListItem(
      id: _first([item['id'], item['_id'], item['companyId']]) ?? '',
      name: _first([company['name'], company['companyLegalName'], company['companyName']]) ?? '—',
      industry: _first([company['industry']]) ?? '—',
      contact: _first([company['contactName']]) ?? '—',
      phone: _first([company['phone']]) ?? '',
      adminEmail: _first([admin['email'], item['email']]) ?? '—',
      workEmail: _first([company['workEmail']]) ?? '',
      status: _first([onboarding['status'], item['approvalStatus'], company['approvalStatus']]) ?? 'draft',
      submittedAt: _first([
            onboarding['submittedAt'],
            item['submittedAt'],
            company['submittedAt'],
            item['createdAt'],
          ]),
      raw: item,
    );
  }
}

/// Web: `normalizeCompanyList`.
List<AdminCompanyListItem> normalizeCompanyList(Object? data) =>
    listFrom(data, const ['companies', 'items', 'list']).map(AdminCompanyListItem.fromJson).toList();

/// Web: `normalizeAdminCompanyDetail` (+ the `documentReviews` lookup the review page does).
class AdminCompanyDetail {
  const AdminCompanyDetail({
    required this.id,
    required this.company,
    required this.admin,
    required this.onboarding,
    required this.status,
    required this.rejectionReason,
    required this.documents,
    required this.documentReviews,
    required this.submittedAt,
  });

  final String id;
  final Map<String, dynamic> company;
  final Map<String, dynamic> admin;
  final Map<String, dynamic> onboarding;
  final String status;
  final String? rejectionReason;

  /// documentKey → stored file URL.
  final Map<String, dynamic> documents;

  /// documentKey → `{ status, reason }`.
  final Map<String, dynamic> documentReviews;
  final Object? submittedAt;

  factory AdminCompanyDetail.fromJson(Object? json) {
    final app = asMap(json);
    final company = app['company'] is Map ? asMap(app['company']) : app;
    final admin = asMap(app['admin']);
    final onboarding = asMap(app['onboarding']);

    return AdminCompanyDetail(
      id: _first([app['id'], app['_id'], app['companyId']]) ?? '',
      company: company,
      admin: admin,
      onboarding: onboarding,
      status: _first([onboarding['status'], app['approvalStatus'], company['approvalStatus']]) ?? 'draft',
      rejectionReason: _first([onboarding['rejectionReason'], app['rejectionReason'], company['rejectionReason']]),
      documents: _firstMap([onboarding['documents'], app['documents'], company['documents']]),
      documentReviews: _firstMap([onboarding['documentReviews'], app['documentReviews']]),
      submittedAt: _first([onboarding['submittedAt'], app['submittedAt'], company['submittedAt']]),
    );
  }
}

/// Tone for a company onboarding status (web `STATUS_STYLES`).
Tone companyStatusTone(String status) => switch (status) {
      'approved' => Tone.success,
      'rejected' => Tone.danger,
      'submitted' || 'pending' => Tone.warning,
      _ => Tone.neutral,
    };

// ── Company types (web: enterpriseCompanyTypes.js) ─────────────────────────

class CompanyDocDef {
  const CompanyDocDef(this.id, this.title);
  final String id;
  final String title;
}

class _CompanyTypeConfig {
  const _CompanyTypeConfig({
    required this.label,
    required this.registrationLabel,
    required this.incorporationTitle,
    required this.registrationTitle,
    this.taxTitle = 'GST Registration Certificate',
  });

  final String label;
  final String registrationLabel;
  final String incorporationTitle;
  final String registrationTitle;
  final String taxTitle;

  List<CompanyDocDef> get documents => [
        CompanyDocDef('incorporation', incorporationTitle),
        CompanyDocDef('registration', registrationTitle),
        CompanyDocDef('taxCertificate', taxTitle),
        const CompanyDocDef('addressProof', 'Proof of Business Address'),
        const CompanyDocDef('signatoryId', 'Authorized Signatory ID'),
        const CompanyDocDef('bankLetter', 'Company Bank Letter / Cancelled Cheque'),
      ];
}

const _cin = 'Corporate Identification Number (CIN)';

const Map<String, String> _companyTypeOptionLabels = {
  'private_limited': 'Private Limited Company (Pvt. Ltd.)',
  'public_limited': 'Public Limited Company',
  'opc': 'One Person Company (OPC)',
  'llp': 'Limited Liability Partnership (LLP)',
  'partnership': 'Partnership Firm',
  'sole_proprietorship': 'Sole Proprietorship',
  'trust_ngo': 'Trust / NGO / Society',
  'section_8': 'Section 8 Company (Non-profit)',
};

const Map<String, _CompanyTypeConfig> _companyTypeConfig = {
  'private_limited': _CompanyTypeConfig(
    label: 'Private Limited Company',
    registrationLabel: _cin,
    incorporationTitle: 'Certificate of Incorporation',
    registrationTitle: 'MOA & AOA',
  ),
  'public_limited': _CompanyTypeConfig(
    label: 'Public Limited Company',
    registrationLabel: _cin,
    incorporationTitle: 'Certificate of Incorporation',
    registrationTitle: 'MOA & AOA',
  ),
  'opc': _CompanyTypeConfig(
    label: 'One Person Company',
    registrationLabel: _cin,
    incorporationTitle: 'Certificate of Incorporation (OPC)',
    registrationTitle: 'MOA & AOA',
  ),
  'llp': _CompanyTypeConfig(
    label: 'Limited Liability Partnership',
    registrationLabel: 'LLP Identification Number (LLPIN)',
    incorporationTitle: 'LLP Incorporation Certificate',
    registrationTitle: 'LLP Agreement',
  ),
  'partnership': _CompanyTypeConfig(
    label: 'Partnership Firm',
    registrationLabel: 'Firm Registration Number',
    incorporationTitle: 'Partnership Deed',
    registrationTitle: 'Firm Registration Certificate',
  ),
  'sole_proprietorship': _CompanyTypeConfig(
    label: 'Sole Proprietorship',
    registrationLabel: 'Udyam / Business Registration Number',
    incorporationTitle: 'Udyam Registration Certificate',
    registrationTitle: 'Business Licence / Shop Act Registration',
  ),
  'trust_ngo': _CompanyTypeConfig(
    label: 'Trust / NGO / Society',
    registrationLabel: 'Trust / Society Registration Number',
    incorporationTitle: 'Trust Deed / Society Registration Certificate',
    registrationTitle: '12A / 80G Certificate (if applicable)',
    taxTitle: 'PAN / GST Certificate',
  ),
  'section_8': _CompanyTypeConfig(
    label: 'Section 8 Company',
    registrationLabel: _cin,
    incorporationTitle: 'Certificate of Incorporation',
    registrationTitle: 'License under Section 8',
    taxTitle: 'PAN / GST Certificate',
  ),
};

_CompanyTypeConfig _configFor(String companyType) =>
    _companyTypeConfig[companyType] ?? _companyTypeConfig['private_limited']!;

String getCompanyTypeLabel(String companyType) =>
    _companyTypeOptionLabels[companyType] ?? _configFor(companyType).label;

List<CompanyDocDef> getDocumentsForCompanyType(String companyType) => _configFor(companyType).documents;

String getRegistrationLabel(String companyType) => _configFor(companyType).registrationLabel;

/// Labels for stored document keys outside the type's list (web `DOC_LABELS`).
const Map<String, String> companyDocLabels = {
  'incorporation': 'Certificate of Incorporation',
  'registration': 'Business Registration / MOA',
  'tax': 'GST / Tax Certificate',
  'taxCertificate': 'GST / Tax Certificate',
  'addressProof': 'Proof of Business Address',
  'signatoryId': 'Authorized Signatory ID',
  'bankLetter': 'Bank Letter / Cancelled Cheque',
};

// ── Employees ───────────────────────────────────────────────────────────────

/// Web: `normalizeAdminEmployee`.
class AdminEmployee {
  const AdminEmployee({
    required this.id,
    required this.userId,
    required this.profileId,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.company,
    required this.veriworkId,
    required this.publicSlug,
    required this.initials,
    required this.photoUrl,
    required this.profileSetupComplete,
    required this.aadhaarVerified,
    required this.biometricVerified,
    required this.isVerified,
    required this.employeeScore,
    required this.currentCity,
    required this.linkedCompanies,
    required this.linkedCompanyLabel,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.dateOfBirth,
    required this.gender,
    required this.totalExperience,
    required this.currentAddress,
    required this.permanentAddress,
    required this.education,
    required this.skills,
    required this.endorsements,
    required this.digilockerUsed,
    required this.publicProfileEnabled,
    required this.authProvider,
    required this.aadhaarKyc,
  });

  final String id;
  final String userId;
  final String? profileId;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String company;
  final String veriworkId;
  final String publicSlug;
  final String initials;
  final String? photoUrl;
  final bool profileSetupComplete;
  final bool aadhaarVerified;
  final bool biometricVerified;
  final bool isVerified;
  final num employeeScore;
  final String currentCity;
  final List<String> linkedCompanies;
  final String linkedCompanyLabel;
  final bool isActive;
  final Object? createdAt;
  final Object? updatedAt;
  final String dateOfBirth;
  final String gender;
  final String totalExperience;
  final String currentAddress;
  final String permanentAddress;
  final Map<String, dynamic>? education;
  final List<dynamic> skills;
  final num endorsements;
  final bool digilockerUsed;
  final bool publicProfileEnabled;
  final String authProvider;

  /// Detail response only; null until the employee submits.
  final Map<String, dynamic>? aadhaarKyc;

  static AdminEmployee? fromJson(Object? json) {
    if (json is! Map) return null;
    final item = asMap(json);
    final linked = asList(item['linkedCompanies']).map((c) => str(c)).where((c) => c.isNotEmpty).toList();

    return AdminEmployee(
      id: _first([item['id'], item['userId']]) ?? '',
      userId: _first([item['userId'], item['id']]) ?? '',
      profileId: strOrNull(item['profileId']),
      name: _first([item['name']]) ?? 'New User',
      email: _first([item['email']]) ?? '—',
      phone: _first([item['phone']]) ?? '—',
      role: _first([item['role']]) ?? 'Professional',
      company: _first([item['company']]) ?? 'Not set',
      veriworkId: _first([item['veriworkId']]) ?? '—',
      publicSlug: _first([item['publicSlug']]) ?? '',
      initials: _first([item['initials']]) ?? '?',
      photoUrl: strOrNull(item['photoUrl']),
      profileSetupComplete: asBool(item['profileSetupComplete']),
      aadhaarVerified: asBool(item['aadhaarVerified']),
      biometricVerified: asBool(item['biometricVerified']),
      isVerified: asBool(item['isVerified']),
      employeeScore: asNum(item['employeeScore']) ?? 300,
      currentCity: _first([item['currentCity']]) ?? '—',
      linkedCompanies: linked,
      linkedCompanyLabel: linked.isNotEmpty ? linked.join(', ') : '—',
      isActive: item['isActive'] != false,
      createdAt: item['createdAt'],
      updatedAt: item['updatedAt'],
      dateOfBirth: str(item['dateOfBirth']),
      gender: str(item['gender']),
      totalExperience: str(item['totalExperience']),
      currentAddress: str(item['currentAddress']),
      permanentAddress: str(item['permanentAddress']),
      education: item['education'] is Map ? asMap(item['education']) : null,
      skills: asList(item['skills']),
      endorsements: asNum(item['endorsements']) ?? 0,
      digilockerUsed: asBool(item['digilockerUsed']),
      publicProfileEnabled: item['publicProfileEnabled'] != false,
      authProvider: _first([item['authProvider']]) ?? 'phone',
      aadhaarKyc: item['aadhaarKyc'] is Map ? asMap(item['aadhaarKyc']) : null,
    );
  }
}

/// Web: `normalizeAdminEmployeeList`.
List<AdminEmployee> normalizeAdminEmployeeList(Object? data) {
  if (data is! List) return const [];
  return data.map(AdminEmployee.fromJson).whereType<AdminEmployee>().toList();
}

// ── HR contacts (web: utils/hrContacts.js) ─────────────────────────────────

/// Trimmed, non-empty, case-insensitively deduped emails (order preserved).
List<String> cleanContacts(Iterable<String> contacts) {
  final seen = <String>{};
  final out = <String>[];
  for (final value in contacts) {
    final email = value.trim();
    if (email.isEmpty) continue;
    final key = email.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(email);
  }
  return out;
}

/// True when a stored file path looks like an image we can render in-app.
bool isImagePath(String? path) {
  final p = (path ?? '').toLowerCase().split('?').first;
  return p.startsWith('data:image') ||
      p.endsWith('.jpg') ||
      p.endsWith('.jpeg') ||
      p.endsWith('.png') ||
      p.endsWith('.webp') ||
      p.endsWith('.gif') ||
      p.endsWith('.heic');
}
