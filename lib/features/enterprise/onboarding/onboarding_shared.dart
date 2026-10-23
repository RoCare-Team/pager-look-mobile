import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data (ports of onboardingConstants.js / enterpriseCompanyTypes.js /
// enterpriseValidators.js / pincodeApi.js / contactInfo.js)
// ─────────────────────────────────────────────────────────────────────────────

/// `GET /enterprise/onboarding` → `{ company, onboarding }`.
final enterpriseOnboardingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchOnboarding());
});

const List<String> onboardingSteps = [
  'Business Basic Info',
  'Documents Verification',
  'Review Final Check',
];

/// value → label (API values for `POST /auth/enterprise/register`).
const Map<String, String> industryOptions = {
  'Technology': 'Technology & IT',
  'Healthcare': 'Healthcare',
  'Finance': 'Finance & Banking',
  'Manufacturing': 'Manufacturing',
  'Retail': 'Retail & E-commerce',
  'Education': 'Education',
  'Consulting': 'Consulting',
  'Other': 'Other',
};

const Map<String, String> companySizeOptions = {
  '1-50': '1–50 employees',
  '50-200': '51–200 employees',
  '200-500': '201–500 employees',
  '500-1000': '501–1000 employees',
  '1000+': '1000+ employees',
};

const Map<String, String> companyTypeOptions = {
  'private_limited': 'Private Limited Company (Pvt. Ltd.)',
  'public_limited': 'Public Limited Company',
  'opc': 'One Person Company (OPC)',
  'llp': 'Limited Liability Partnership (LLP)',
  'partnership': 'Partnership Firm',
  'sole_proprietorship': 'Sole Proprietorship',
  'trust_ngo': 'Trust / NGO / Society',
  'section_8': 'Section 8 Company (Non-profit)',
};

class OnboardingDoc {
  const OnboardingDoc({required this.id, required this.title, required this.description, required this.required});

  final String id;
  final String title;
  final String description;
  final bool required;
}

class RegistrationConfig {
  const RegistrationConfig({required this.label, required this.placeholder, required this.hint, required this.format});

  final String label;
  final String placeholder;
  final String hint;

  /// cin | llpin | udyam | generic
  final String format;
}

class CompanyTypeConfig {
  const CompanyTypeConfig({
    required this.label,
    required this.registration,
    required this.gstRequired,
    required this.documents,
  });

  final String label;
  final RegistrationConfig registration;
  final bool gstRequired;
  final List<OnboardingDoc> documents;
}

const _taxCertificate = OnboardingDoc(
  id: 'taxCertificate',
  title: 'GST Registration Certificate',
  description: 'Valid GST registration certificate or tax identification proof.',
  required: false,
);
const _addressProof = OnboardingDoc(
  id: 'addressProof',
  title: 'Proof of Business Address',
  description: 'Utility bill, lease agreement, or bank statement (last 3 months).',
  required: false,
);
// The only mandatory document — a bank letterhead / cancelled cheque proves the
// business name and account. Everything else speeds up review but is optional.
const _bankLetter = OnboardingDoc(
  id: 'bankLetter',
  title: 'Company Bank Letter / Cancelled Cheque',
  description: 'Bank letterhead or cancelled cheque in the business name.',
  required: true,
);

OnboardingDoc _signatory(String description) =>
    OnboardingDoc(id: 'signatoryId', title: 'Authorized Signatory ID', description: description, required: false);

OnboardingDoc _optional(String id, String title, String description) =>
    OnboardingDoc(id: id, title: title, description: description, required: false);

final Map<String, CompanyTypeConfig> companyTypeConfigs = {
  'private_limited': CompanyTypeConfig(
    label: 'Private Limited Company',
    registration: const RegistrationConfig(
      label: 'Corporate Identification Number (CIN)',
      placeholder: 'e.g. U72900KA2015PTC082988',
      hint: '21-character CIN as per MCA records',
      format: 'cin',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'Certificate of Incorporation', 'MCA-issued certificate of incorporation for your company.'),
      _optional('registration', 'MOA & AOA', 'Memorandum and Articles of Association.'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of a director or authorized signatory.'),
      _bankLetter,
    ],
  ),
  'public_limited': CompanyTypeConfig(
    label: 'Public Limited Company',
    registration: const RegistrationConfig(
      label: 'Corporate Identification Number (CIN)',
      placeholder: 'e.g. L72900KA2015PLC082988',
      hint: '21-character CIN as per MCA records',
      format: 'cin',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'Certificate of Incorporation', 'MCA-issued certificate of incorporation.'),
      _optional('registration', 'MOA & AOA', 'Memorandum and Articles of Association.'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of a director or company secretary.'),
      _bankLetter,
    ],
  ),
  'opc': CompanyTypeConfig(
    label: 'One Person Company',
    registration: const RegistrationConfig(
      label: 'Corporate Identification Number (CIN)',
      placeholder: 'e.g. U72900KA2015OPC082988',
      hint: '21-character CIN for your OPC',
      format: 'cin',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'Certificate of Incorporation (OPC)', 'MCA-issued OPC incorporation certificate.'),
      _optional('registration', 'MOA & AOA', 'Memorandum and Articles of Association.'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of the sole director / nominee.'),
      _bankLetter,
    ],
  ),
  'llp': CompanyTypeConfig(
    label: 'Limited Liability Partnership',
    registration: const RegistrationConfig(
      label: 'LLP Identification Number (LLPIN)',
      placeholder: 'e.g. AAB-1234',
      hint: '7-character LLPIN issued by MCA (e.g. AAA-1234)',
      format: 'llpin',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'LLP Incorporation Certificate', 'Certificate of incorporation issued by MCA for the LLP.'),
      _optional('registration', 'LLP Agreement', 'Signed LLP agreement between all designated partners.'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of a designated partner or authorized signatory.'),
      _bankLetter,
    ],
  ),
  'partnership': CompanyTypeConfig(
    label: 'Partnership Firm',
    registration: const RegistrationConfig(
      label: 'Firm Registration Number',
      placeholder: 'e.g. FIRM/2020/12345 or state registration no.',
      hint: 'State-issued firm registration number (if registered under Indian Partnership Act)',
      format: 'generic',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'Partnership Deed', 'Registered or notarized partnership deed signed by all partners.'),
      _optional('registration', 'Firm Registration Certificate', 'Government-issued firm registration certificate (if registered).'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of a partner or authorized signatory.'),
      _bankLetter,
    ],
  ),
  'sole_proprietorship': CompanyTypeConfig(
    label: 'Sole Proprietorship',
    registration: const RegistrationConfig(
      label: 'Udyam / Business Registration Number',
      placeholder: 'e.g. UDYAM-MH-00-0001234',
      hint: 'Udyam registration or Shop & Establishment licence number',
      format: 'udyam',
    ),
    gstRequired: true,
    documents: [
      _optional('incorporation', 'Udyam Registration Certificate',
          'Udyam MSME registration certificate (or Shop & Establishment licence).'),
      _optional('registration', 'Business Licence / Shop Act Registration',
          'Local business licence or Shop & Establishment registration.'),
      _taxCertificate,
      _addressProof,
      _signatory('Government ID of the sole proprietor (PAN / Aadhaar).'),
      _bankLetter,
    ],
  ),
  'trust_ngo': CompanyTypeConfig(
    label: 'Trust / NGO / Society',
    registration: const RegistrationConfig(
      label: 'Trust / Society Registration Number',
      placeholder: 'e.g. TR/1234/2018 or state society registration no.',
      hint: 'Registration number from the Charity Commissioner or Registrar of Societies',
      format: 'generic',
    ),
    gstRequired: false,
    documents: [
      _optional('incorporation', 'Trust Deed / Society Registration Certificate',
          'Registered trust deed or society incorporation certificate.'),
      _optional('registration', '12A / 80G Certificate (if applicable)', 'Income Tax exemption certificates, if obtained.'),
      _optional('taxCertificate', 'PAN / GST Certificate', 'PAN allotment letter or GST registration (if applicable).'),
      _addressProof,
      _signatory('Government ID of trustee, secretary, or authorized signatory.'),
      _bankLetter,
    ],
  ),
  'section_8': CompanyTypeConfig(
    label: 'Section 8 Company',
    registration: const RegistrationConfig(
      label: 'Corporate Identification Number (CIN)',
      placeholder: 'e.g. U72900KA2015NPL082988',
      hint: '21-character CIN for your Section 8 company',
      format: 'cin',
    ),
    gstRequired: false,
    documents: [
      _optional('incorporation', 'Certificate of Incorporation', 'MCA-issued Section 8 company incorporation certificate.'),
      _optional('registration', 'License under Section 8',
          'Central Government licence issued under Section 8 of Companies Act.'),
      _optional('taxCertificate', 'PAN / GST Certificate', 'PAN allotment or GST registration (if applicable).'),
      _addressProof,
      _signatory('Government ID of a director or authorized signatory.'),
      _bankLetter,
    ],
  ),
};

const String defaultCompanyType = 'private_limited';

CompanyTypeConfig companyTypeConfig(String? companyType) =>
    companyTypeConfigs[companyType] ?? companyTypeConfigs[defaultCompanyType]!;

String companyTypeLabel(String? companyType) =>
    companyTypeOptions[companyType] ?? companyTypeConfig(companyType).label;

List<OnboardingDoc> documentsForCompanyType(String? companyType) => companyTypeConfig(companyType).documents;

String resolveCompanyType(Map<String, dynamic>? company, Map<String, dynamic>? basicInfo) =>
    strOrNull(basicInfo?['companyType']) ?? strOrNull(company?['companyType']) ?? defaultCompanyType;

String registrationLabel(String? companyType) => companyTypeConfig(companyType).registration.label;

/// Human label for a stored onboarding document key (PendingApproval `DOC_LABELS`).
String onboardingDocLabel(String key) => const {
      'incorporation': 'Certificate of Incorporation',
      'registration': 'Registration Document',
      'tax': 'GST Registration Certificate',
      'taxCertificate': 'GST Registration Certificate',
      'addressProof': 'Proof of Business Address',
      'signatoryId': 'Authorized Signatory ID',
      'bankLetter': 'Company Bank Letter / Cancelled Cheque',
    }[key] ??
    key;

// ── Validators / input formatting ──────────────────────────────────────────

final RegExp _cinRe = RegExp(r'^[LU][0-9]{5}[A-Z]{2}[0-9]{4}[A-Z]{3}[0-9]{6}$', caseSensitive: false);
final RegExp _llpinRe = RegExp(r'^[A-Z]{3}-[0-9]{4}$', caseSensitive: false);
final RegExp _udyamRe = RegExp(r'^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$', caseSensitive: false);
final RegExp _genericBrnRe = RegExp(r'^[A-Z0-9][A-Z0-9\-/]{5,24}$', caseSensitive: false);
final RegExp _gstinRe = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

const String gstinHint = '15-character GSTIN (e.g. 27AABCU9603R1ZM)';

bool isValidBRN(String value, String? companyType) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (companyType == null || companyType.isEmpty) {
    return _cinRe.hasMatch(v) || _llpinRe.hasMatch(v) || _udyamRe.hasMatch(v) || _genericBrnRe.hasMatch(v);
  }
  switch (companyTypeConfig(companyType).registration.format) {
    case 'cin':
      return _cinRe.hasMatch(v);
    case 'llpin':
      return _llpinRe.hasMatch(v);
    case 'udyam':
      return _udyamRe.hasMatch(v) || _genericBrnRe.hasMatch(v);
    default:
      return _genericBrnRe.hasMatch(v);
  }
}

bool isValidGSTIN(String value) => _gstinRe.hasMatch(value.trim().toUpperCase());

bool isValidIndianPincode(String value) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(value.replaceAll(RegExp(r'\D'), ''));

/// Web `isValidPhone` on the registration form: at least 10 digits.
bool isValidRegistrationPhone(String value) => value.replaceAll(RegExp(r'\D'), '').length >= 10;

String _take(String s, int n) => s.length > n ? s.substring(0, n) : s;

String formatBRNInput(String value) => _take(value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-/]'), ''), 21);

String formatRegistrationInput(String value, String? companyType) {
  final format = companyTypeConfig(companyType).registration.format;
  if (format == 'llpin') {
    final clean = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length <= 3) return clean;
    return '${clean.substring(0, 3)}-${clean.substring(3, clean.length < 7 ? clean.length : 7)}';
  }
  if (format == 'udyam') {
    return _take(value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), ''), 24);
  }
  return formatBRNInput(value);
}

String formatGSTINInput(String value) => _take(value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), ''), 15);

String formatPincodeInput(String value) => _take(value.replaceAll(RegExp(r'\D'), ''), 6);

/// Applies a web-style `format*Input` function to every keystroke.
class MappingInputFormatter extends TextInputFormatter {
  MappingInputFormatter(this.map);

  final String Function(String value) map;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final next = map(newValue.text);
    if (next == newValue.text) return newValue;
    return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
  }
}

// ── Pincode lookup (lib/pincodeApi.js) ──────────────────────────────────────

class PincodeResult {
  const PincodeResult({
    required this.pincode,
    required this.city,
    required this.locality,
    required this.state,
    required this.country,
  });

  final String pincode;
  final String city;
  final String locality;
  final String state;
  final String country;
}

final Dio _pincodeDio = Dio(
  BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)),
);

/// India postal pincode lookup (free public API, https://api.postalpincode.in/).
/// Returns null when the pincode is unknown; throws on network failure.
Future<PincodeResult?> lookupIndianPincode(String pincode) async {
  final clean = pincode.replaceAll(RegExp(r'\D'), '');
  if (clean.length != 6) return null;

  final res = await _pincodeDio.get<dynamic>(
    'https://api.postalpincode.in/pincode/$clean',
    options: Options(validateStatus: (_) => true),
  );
  final status = res.statusCode ?? 0;
  if (status < 200 || status >= 300) return null;

  dynamic json = res.data;
  if (json is String) {
    try {
      json = jsonDecode(json);
    } catch (_) {
      return null;
    }
  }
  final entry = asMap(asList(json).isEmpty ? null : asList(json).first);
  final offices = asMapList(entry['PostOffice']);
  if (str(entry['Status']) != 'Success' || offices.isEmpty) return null;

  final po = offices.first;
  return PincodeResult(
    pincode: clean,
    city: str(po['District']),
    locality: str(po['Name']),
    state: str(po['State']),
    country: 'India',
  );
}

// ── Support channels (utils/contactInfo.js) ─────────────────────────────────

const String supportEmail = 'info@pagerlook.com';
const String supportPhone = '+918510099972';
const String supportPhoneDisplay = '+91 85100 99972';

String whatsappLink([String? message]) {
  final base = 'https://wa.me/${supportPhone.replaceAll(RegExp(r'\D'), '')}';
  if (message == null || message.isEmpty) return base;
  return '$base?text=${Uri.encodeComponent(message)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal step indicator (web `StepProgress`).
class OnboardingStepper extends StatelessWidget {
  const OnboardingStepper({super.key, required this.currentStep, this.steps = onboardingSteps});

  /// 1-based.
  final int currentStep;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final n = i + 1;
      final done = n < currentStep;
      final active = n == currentStep;
      children.add(
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? AppColors.brand600 : AppColors.surface,
            border: Border.all(color: done || active ? AppColors.brand600 : AppColors.line, width: 2),
          ),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.inkFaint,
                  ),
                ),
        ),
      );
      if (i < steps.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: done ? AppColors.brand600.withValues(alpha: 0.4) : AppColors.line,
            ),
          ),
        );
      }
    }
    final label = currentStep >= 1 && currentStep <= steps.length ? steps[currentStep - 1] : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Row(children: children),
          const SizedBox(height: 10),
          Text(
            'Step $currentStep of ${steps.length} · $label',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand600),
          ),
        ],
      ),
    );
  }
}

/// Body + sticky bottom actions that stay above the keyboard.
class StickyActionLayout extends StatelessWidget {
  const StickyActionLayout({super.key, required this.body, required this.actions});

  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: body),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(flex: i == actions.length - 1 ? 2 : 1, child: actions[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// White section card with a bold title and helper copy.
class OnboardingSection extends StatelessWidget {
  const OnboardingSection({super.key, required this.title, this.subtitle, this.action, required this.children});

  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: title,
      subtitle: subtitle,
      action: action,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Small "✓ Valid …" confirmation line under a field.
class ValidHint extends StatelessWidget {
  const ValidHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: text.isEmpty
            ? null
            : Text(
                '✓ $text',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.success),
              ),
      ),
    );
  }
}

/// Label/value row of the review step (web `ReviewRow`).
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.label, this.value, this.fallback = '—', this.last = false});

  final String label;
  final String? value;
  final String fallback;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final v = (value == null || value!.trim().isEmpty) ? fallback : value!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
            ),
          ),
        ],
      ),
    );
  }
}

/// Port of `components/common/DocumentUploadCard.jsx`.
class DocumentUploadCard extends StatelessWidget {
  const DocumentUploadCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.required,
    this.fileName,
    this.fileUrl,
    this.uploading = false,
    this.error,
    required this.onUpload,
    required this.onRemove,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool required;
  final String? fileName;
  final String? fileUrl;
  final bool uploading;
  final String? error;
  final VoidCallback onUpload;
  final VoidCallback onRemove;

  /// False while another card is uploading.
  final bool enabled;

  bool get _isUploaded => (fileName ?? '').isNotEmpty || (fileUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    final borderColor = hasError
        ? AppColors.danger.withValues(alpha: 0.35)
        : (_isUploaded ? AppColors.success.withValues(alpha: 0.35) : AppColors.line);

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.canvas,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: AppColors.brand600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                          ),
                          StatusBadge(
                            required ? 'required' : 'optional',
                            label: required ? 'REQUIRED' : 'OPTIONAL',
                            tone: required ? Tone.brand : Tone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(description, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isUploaded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.check, size: 18, color: AppColors.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: fileUrl == null ? null : () => openExternalUrl(mediaUrl(fileUrl)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((fileName ?? '').isNotEmpty)
                            Text(
                              fileName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
                            ),
                          if ((fileUrl ?? '').isNotEmpty)
                            Text(
                              fileUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: uploading ? null : onRemove,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Remove', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: uploading || !enabled ? null : onUpload,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: uploading ? AppColors.hairline : AppColors.brand50,
                        shape: BoxShape.circle,
                      ),
                      child: uploading
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Icon(Icons.upload_file_outlined, color: AppColors.brand600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      uploading ? 'Uploading to secure storage...' : 'Tap to upload PDF or Image',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: uploading ? AppColors.inkMuted : AppColors.brand600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('PDF or image only · Max 10MB', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                  ],
                ),
              ),
            ),
          if (hasError)
            Container(
              color: AppColors.dangerBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

/// Port of `components/common/MessageThread.jsx` (company side).
class MessageThread extends StatefulWidget {
  const MessageThread({
    super.key,
    required this.messages,
    required this.onSend,
    this.viewerRole = 'company',
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.onRetry,
    this.title = 'Messages',
    this.subtitle,
    this.placeholder = 'Write a message…',
  });

  final List<Map<String, dynamic>> messages;

  /// Returns true when the message was sent, so the input can be cleared.
  final Future<bool> Function(String text) onSend;
  final String viewerRole;
  final bool isLoading;
  final bool isSending;
  final Object? error;
  final VoidCallback? onRetry;
  final String title;
  final String? subtitle;
  final String placeholder;

  @override
  State<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends State<MessageThread> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    final ok = await widget.onSend(text);
    if (ok && mounted) setState(_controller.clear);
  }

  Widget _bubble(Map<String, dynamic> m) {
    if (asBool(m['isSystem'])) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '${str(m['body'])} · ${formatDate(m['createdAt'])}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.inkFaint),
        ),
      );
    }
    final mine = str(m['authorRole']) == widget.viewerRole;
    final fg = mine ? Colors.white : AppColors.inkStrong;
    final muted = mine ? Colors.white.withValues(alpha: 0.7) : AppColors.inkMuted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? AppColors.brand600 : AppColors.hairline,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  str(m['authorName']).toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: muted),
                ),
              if (str(m['documentKey']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Re: ${str(m['documentKey'])}',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(str(m['body']), style: TextStyle(fontSize: 14, color: fg, height: 1.4)),
              ),
              const SizedBox(height: 4),
              Text(formatDate(m['createdAt']), style: TextStyle(fontSize: 10.5, color: muted)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.isLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Loading…', style: TextStyle(fontSize: 13.5, color: AppColors.inkFaint)),
      );
    } else if (widget.error != null && widget.messages.isEmpty) {
      content = InfoBanner(
        tone: Tone.danger,
        message: errorMessage(widget.error),
        action: widget.onRetry == null
            ? null
            : AppButton(
                label: 'Try again',
                variant: AppButtonVariant.outline,
                compact: true,
                expand: false,
                onPressed: widget.onRetry,
              ),
      );
    } else if (widget.messages.isEmpty) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
        child: const Text(
          'No messages yet. Ask a question and our team will reply here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in widget.messages) ...[_bubble(m), const SizedBox(height: 10)],
        ],
      );
    }

    return AppCard(
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !widget.isSending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: widget.placeholder),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: widget.isSending ? 'Sending…' : 'Send',
                expand: false,
                loading: widget.isSending,
                onPressed: _controller.text.trim().isEmpty ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
