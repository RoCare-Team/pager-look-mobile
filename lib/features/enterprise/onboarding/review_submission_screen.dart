import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/enterprise_api.dart';
import 'onboarding_shared.dart';

/// Step 3 of enterprise onboarding — port of `pages/auth/ReviewSubmission.jsx`.
class ReviewSubmissionScreen extends ConsumerStatefulWidget {
  const ReviewSubmissionScreen({super.key});

  @override
  ConsumerState<ReviewSubmissionScreen> createState() => _ReviewSubmissionScreenState();
}

class _ReviewSubmissionScreenState extends ConsumerState<ReviewSubmissionScreen> {
  bool _certified = false;
  bool _submitting = false;

  Future<void> _submit(Map<String, dynamic> company) async {
    if (!_certified) {
      showToast('Please certify that all information is accurate', type: ToastType.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = asMap(await ref.read(enterpriseApiProvider).submitOnboarding(true));
      await ref.read(authProvider).updateCompany(
        {
          ...company,
          'onboardingComplete': data.containsKey('onboardingComplete') && data['onboardingComplete'] != null
              ? asBool(data['onboardingComplete'])
              : true,
          'isVerified': false,
          'approvalStatus': strOrNull(data['approvalStatus']) ?? 'submitted',
        },
        merge: true,
      );
      ref.invalidate(enterpriseOnboardingProvider);
      showToast('Application submitted — awaiting admin approval', type: ToastType.success);
      if (!mounted) return;
      context.go('/enterprise/pending-approval');
    } catch (e) {
      showErrorToast(e, 'Submission failed');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() => context.go('/enterprise/verify');

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(enterpriseOnboardingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Final Check'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _submitting ? null : _back,
        ),
      ),
      body: AsyncValueView<Map<String, dynamic>>(
        value: async,
        loadingLabel: 'Loading review...',
        onRetry: () => ref.invalidate(enterpriseOnboardingProvider),
        data: (data) => BusyOverlay(
          busy: _submitting,
          label: 'Submitting for review...',
          child: _content(data),
        ),
      ),
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final company = asMap(data['company']);
    final onboarding = asMap(data['onboarding']);
    final basicInfo = onboarding['basicInfo'] is Map
        ? asMap(onboarding['basicInfo'])
        : <String, dynamic>{
            'companyName': company['name'],
            'industry': company['industry'],
            'companySize': company['companySize'],
            'workEmail': company['workEmail'],
            'contactName': company['contactName'],
            'phone': company['phone'],
            'country': company['country'],
            'city': company['city'],
          };
    final registration = onboarding['registration'] is Map
        ? asMap(onboarding['registration'])
        : <String, dynamic>{'brn': company['brn'], 'taxId': company['taxId']};
    final documents = asMap(onboarding['documents']);
    final companyType = resolveCompanyType(company, basicInfo);
    final docs = documentsForCompanyType(companyType);
    final config = companyTypeConfig(companyType);

    bool has(String id) => str(uploadedEnterpriseDocument(documents, id)).isNotEmpty;
    final uploadedCount = docs.where((d) => has(d.id)).length;
    final requiredCount = docs.where((d) => d.required).length;
    final requiredUploaded = docs.where((d) => d.required && has(d.id)).length;
    final allRequired = requiredUploaded == requiredCount;

    final city = str(basicInfo['city']);
    final country = str(basicInfo['country']);
    final location = city.isNotEmpty && country.isNotEmpty ? '$city, $country' : country;
    final workEmail = str(basicInfo['workEmail']);

    Widget editButton(String path) => TextButton(
          onPressed: _submitting ? null : () => context.go(path),
          style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Edit', style: TextStyle(fontSize: 12.5)),
        );

    final summaryTone = allRequired ? Tone.success : Tone.warning;

    return StickyActionLayout(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const OnboardingStepper(currentStep: 3),
          const SizedBox(height: 16),
          const Text(
            'Review your details before submitting for compliance verification.',
            style: TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: summaryTone.bg,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: summaryTone.fg.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: summaryTone.fg.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Text(
                    '$requiredUploaded/$requiredCount',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: summaryTone.fg),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        allRequired ? 'All required documents uploaded' : 'Some required documents are missing',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: summaryTone.fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$uploadedCount of ${docs.length} documents uploaded total',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Company Information',
            action: editButton('/enterprise/register'),
            child: Column(
              children: [
                ReviewRow(label: 'Company Name', value: str(basicInfo['companyName'])),
                ReviewRow(label: 'Company Type', value: companyTypeLabel(companyType)),
                ReviewRow(label: registrationLabel(companyType), value: str(registration['brn'])),
                ReviewRow(
                  label: config.gstRequired ? 'GSTIN' : 'GSTIN (if applicable)',
                  value: strOrNull(registration['taxId']) ?? (config.gstRequired ? '—' : 'Not provided'),
                ),
                ReviewRow(label: 'Industry', value: str(basicInfo['industry'])),
                ReviewRow(label: 'Company Size', value: str(basicInfo['companySize'])),
                ReviewRow(label: 'Work Email', value: workEmail),
                ReviewRow(label: 'Contact Person', value: str(basicInfo['contactName'])),
                ReviewRow(label: 'Phone', value: str(basicInfo['phone'])),
                ReviewRow(label: 'Location', value: location, last: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Uploaded Documents',
            action: editButton('/enterprise/verify'),
            child: Column(
              children: [
                for (final doc in docs) ...[
                  _documentRow(doc, uploadedEnterpriseDocument(documents, doc.id)),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoBanner(
            title: 'What happens next?',
            message: 'After submission, our compliance team will review your application within 24–48 business '
                "hours. You'll receive an email at ${workEmail.isEmpty ? 'your work email' : workEmail} once your "
                'account is verified and activated.',
          ),
          const SizedBox(height: 16),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: _certified ? AppColors.brand100 : AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              value: _certified,
              onChanged: _submitting ? null : (v) => setState(() => _certified = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              title: const Text(
                'I certify that all information and documents provided are authentic and accurate. I understand '
                'that falsifying records will lead to immediate account suspension and legal action.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkBody),
              ),
            ),
          ),
        ],
      ),
      actions: [
        AppButton(label: 'Back', variant: AppButtonVariant.outline, onPressed: _submitting ? null : _back),
        AppButton(
          label: 'Submit for Review',
          loading: _submitting,
          onPressed: !_certified || _submitting ? null : () => _submit(company),
        ),
      ],
    );
  }

  Widget _documentRow(OnboardingDoc doc, dynamic uploaded) {
    final hasFile = str(uploaded).isNotEmpty;
    final fileLabel = uploaded is String ? uploaded.split('/').last : str(uploaded);
    final String status;
    final Tone tone;
    if (hasFile) {
      status = 'Uploaded';
      tone = Tone.success;
    } else if (doc.required) {
      status = 'Missing';
      tone = Tone.danger;
    } else {
      status = 'Skipped';
      tone = Tone.neutral;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
                if (hasFile)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      fileLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(status, label: status.toUpperCase(), tone: tone),
        ],
      ),
    );
  }
}
