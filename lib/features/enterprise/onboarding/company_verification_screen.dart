import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/enterprise_api.dart';
import 'onboarding_shared.dart';

/// Step 2 of enterprise onboarding — port of `pages/auth/CompanyVerification.jsx`.
class CompanyVerificationScreen extends ConsumerStatefulWidget {
  const CompanyVerificationScreen({super.key});

  @override
  ConsumerState<CompanyVerificationScreen> createState() => _CompanyVerificationScreenState();
}

class _CompanyVerificationScreenState extends ConsumerState<CompanyVerificationScreen> {
  /// Local copy of `onboarding.documents` (docType/UI id → url).
  Map<String, dynamic>? _documents;
  final Map<String, String?> _uploadErrors = {};
  String? _uploadingId;
  bool _touched = false;

  void _syncFrom(Map<String, dynamic> data) {
    _documents ??= Map<String, dynamic>.from(asMap(pick(data, 'onboarding.documents')));
  }

  Future<void> _upload(String docId) async {
    final file = await pickDocumentWithSheet(context, title: 'Upload document');
    if (file == null || !mounted) return;

    final docType = enterpriseDocType(docId);
    setState(() {
      _uploadingId = docId;
      _uploadErrors[docId] = null;
    });
    try {
      final data = asMap(await ref.read(enterpriseApiProvider).uploadOnboardingDocument(docType, file));
      final url = data['url'];
      if (!mounted) return;
      setState(() {
        final fromServer = data['documents'] is Map ? asMap(data['documents']) : null;
        _documents = {
          ...(fromServer ?? _documents ?? <String, dynamic>{}),
          docId: url,
          docType: url,
        };
      });
      showToast('Document uploaded successfully', type: ToastType.success);
    } catch (e) {
      final message = errorMessage(e, 'Upload failed');
      if (mounted) setState(() => _uploadErrors[docId] = message);
      showToast(message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _uploadingId = null);
    }
  }

  void _remove(String docId) {
    final docType = enterpriseDocType(docId);
    setState(() {
      final next = Map<String, dynamic>.from(_documents ?? const {});
      next.remove(docId);
      next.remove(docType);
      _documents = next;
      _uploadErrors[docId] = null;
    });
  }

  bool _hasDocument(String docId) {
    final v = uploadedEnterpriseDocument(_documents, docId);
    return v != null && str(v).isNotEmpty;
  }

  void _continue(List<OnboardingDoc> docs) {
    setState(() => _touched = true);
    final allRequired = docs.where((d) => d.required).every((d) => _hasDocument(d.id));
    if (!allRequired) {
      showToast('Please upload all required documents', type: ToastType.error);
      return;
    }
    context.go('/enterprise/review');
  }

  IconData _docIcon(String id) {
    if (id == 'addressProof') return Icons.apartment_outlined;
    if (id == 'taxCertificate') return Icons.credit_card;
    return Icons.description_outlined;
  }

  void _back() => context.go('/enterprise/register');

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(enterpriseOnboardingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Verification'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _uploadingId != null ? null : _back,
        ),
      ),
      body: AsyncValueView<Map<String, dynamic>>(
        value: async,
        loadingLabel: 'Loading...',
        onRetry: () => ref.invalidate(enterpriseOnboardingProvider),
        data: (data) {
          _syncFrom(data);
          final companyType = resolveCompanyType(asMap(data['company']), asMap(pick(data, 'onboarding.basicInfo')));
          final docs = documentsForCompanyType(companyType);
          final allRequired = docs.where((d) => d.required).every((d) => _hasDocument(d.id));

          return StickyActionLayout(
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const OnboardingStepper(currentStep: 2),
                const SizedBox(height: 16),
                const Text(
                  'Upload required documents for your business verification.',
                  style: TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45),
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Required Documents',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'Upload mandatory documents for your ',
                          children: [
                            TextSpan(
                              text: companyTypeLabel(companyType),
                              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkBody),
                            ),
                            const TextSpan(text: '. Optional documents speed up verification.'),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.45),
                      ),
                      const SizedBox(height: 16),
                      for (final doc in docs) ...[
                        _card(doc),
                        const SizedBox(height: 12),
                      ],
                      if (_touched && !allRequired)
                        const Text(
                          'Please upload all required documents before continuing.',
                          style: TextStyle(fontSize: 13, color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const InfoBanner(
                  title: 'Verification Timeline',
                  message: 'Our compliance team typically reviews documents within 24–48 business hours. '
                      'You will receive an email once verified.',
                ),
              ],
            ),
            actions: [
              AppButton(
                label: 'Back',
                variant: AppButtonVariant.outline,
                onPressed: _uploadingId != null ? null : _back,
              ),
              AppButton(
                label: 'Continue',
                onPressed: _uploadingId != null ? null : () => _continue(docs),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(OnboardingDoc doc) {
    final value = uploadedEnterpriseDocument(_documents, doc.id);
    String? fileName;
    String? fileUrl;
    if (value is String && value.isNotEmpty) {
      fileName = value.split('/').last;
      fileUrl = value;
    } else if (value != null && str(value).isNotEmpty) {
      fileName = str(value);
    }
    return DocumentUploadCard(
      icon: _docIcon(doc.id),
      title: doc.title,
      description: doc.description,
      required: doc.required,
      fileName: fileName,
      fileUrl: fileUrl,
      uploading: _uploadingId == doc.id,
      enabled: _uploadingId == null,
      error: _uploadErrors[doc.id],
      onUpload: () => _upload(doc.id),
      onRemove: () => _remove(doc.id),
    );
  }
}
