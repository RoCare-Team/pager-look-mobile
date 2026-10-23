import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/employment_card.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_sheets.dart';
import 'widgets_a/team_utils.dart';
import 'widgets_a/team_widgets.dart';
import 'widgets_b/sheet_body.dart';
import 'widgets_b/verification_sheets.dart';

/// Port of `pages/enterprise/EmployeeProfilePage.jsx` — a linked employee's
/// profile as the company sees it, gated by the access the employee granted.
class CompanyEmployeeProfileScreen extends ConsumerStatefulWidget {
  const CompanyEmployeeProfileScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<CompanyEmployeeProfileScreen> createState() => _CompanyEmployeeProfileScreenState();
}

/// Web `resolveAccessFlags`.
class _AccessFlags {
  _AccessFlags(Map<String, dynamic> access, Map<String, dynamic> preview, Map<String, dynamic> root) {
    bool t(String k) => access[k] == true;
    fullProfileAccess = t('fullProfileAccess') ||
        t('full_profile_access') ||
        t('fullProfileAccessGranted') ||
        t('hasAllAccess') ||
        preview['fullProfileAccessGranted'] == true ||
        preview['showFullProfileButton'] == true;
    final pendingFull = t('pendingFullProfileAccess') || t('pending_full_profile_access');
    profileAccess = fullProfileAccess || t('profileAccess') || t('profile_access') || t('hasProfileAccess');
    backgroundCheck = fullProfileAccess || t('backgroundCheck') || t('background_check') || t('hasBackgroundCheck');
    verificationData =
        fullProfileAccess || t('verificationData') || t('verification_data') || t('hasVerificationData');
    pendingFullProfileAccess = pendingFull;

    // The backend reports pending state on `lockedSections[]` and `access.pendingRequests[]`.
    final locked = asMapList(root['lockedSections']);
    bool lockedPending(String key) => locked.any((s) => s['key'] == key && s['pending'] == true);
    final pendingTypes = asList(access['pendingRequests'])
        .map((r) => r is Map ? str(r['requestType']) : str(r))
        .toSet();
    final anyFullPending = pendingFull ||
        pendingTypes.contains('full_profile_access') ||
        lockedPending('full_profile');
    pendingProfileAccess = anyFullPending ||
        t('pendingProfileAccess') ||
        t('pending_profile_access') ||
        pendingTypes.contains('profile_access') ||
        lockedPending('profile');
    pendingBackgroundCheck = anyFullPending ||
        t('pendingBackgroundCheck') ||
        t('pending_background_check') ||
        pendingTypes.contains('background_check') ||
        lockedPending('background');
    pendingVerificationData = anyFullPending ||
        t('pendingVerificationData') ||
        t('pending_verification_data') ||
        pendingTypes.contains('verification_data') ||
        lockedPending('verification');
  }

  late final bool fullProfileAccess;
  late final bool profileAccess;
  late final bool backgroundCheck;
  late final bool verificationData;
  late final bool pendingFullProfileAccess;
  late final bool pendingProfileAccess;
  late final bool pendingBackgroundCheck;
  late final bool pendingVerificationData;
}

class _CompanyEmployeeProfileScreenState extends ConsumerState<CompanyEmployeeProfileScreen> {
  String _tab = 'profile';

  String get _id => widget.employeeId;

  void _refreshProfile() {
    ref.invalidate(companyEmployeeProfileProvider(_id));
    ref.invalidate(companyEmployeeDocumentsProvider(_id));
  }

  void _onTabChanged(String next) {
    setState(() => _tab = next);
    ref.invalidate(companyEmployeeProfileProvider(_id));
  }

  Future<void> _openRequest(String requestType, String name) async {
    final ok = await showSendAccessRequestSheet(
      context,
      employeeId: _id,
      employeeName: name,
      defaultRequestType: requestType,
    );
    if (ok) _refreshProfile();
  }

  Future<void> _removeAccess(String name) async {
    final ok = await showRemoveAccessSheet(context, employeeId: _id, employeeName: name);
    if (ok) {
      _refreshProfile();
      ref.invalidate(companyTeamProvider);
    }
  }

  Future<void> _assign(String name, Map<String, dynamic> preview) async {
    final ok = await showAssignEmployeeSheet(
      context,
      employeeId: _id,
      employeeName: name,
      department: strOrNull(preview['department']),
      designation: strOrNull(preview['role']),
    );
    if (ok) _refreshProfile();
  }

  /// Web: opens `VerificationRequestModal` for one employment record.
  Future<void> _verifyJob(Map<String, dynamic> job) async {
    final matched = job['matchedPlatformCompany'] is Map ? asMap(job['matchedPlatformCompany']) : null;
    final result = await showAppSheet<Object?>(
      context,
      builder: (_) => VerificationRequestSheet(
        employeeId: _id,
        jobExperienceId: idOf(job),
        jobTitle: str(job['title']),
        companyName: str(job['company']),
        previousCompanyOnPlatform: asBool(job['previousCompanyOnPlatform']),
        matchedPlatformCompany: matched,
        defaultHrEmail: str(job['hrEmail']),
        defaultManagerEmail: str(job['managerEmail']),
        defaultHrName: str(job['managerName']),
        department: str(job['department']),
        duration: str(job['duration']),
        employmentType: str(job['employmentType']),
      ),
    );
    if (result != null) _refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(companyEmployeeProfileProvider(_id));
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();

    return Scaffold(
      appBar: AppBar(title: const Text('Employee profile')),
      body: profileAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const LoadingView(label: 'Loading profile...'),
        error: (e, _) {
          final notFound =
              (e is ApiException && e.isNotFound) || RegExp('not found', caseSensitive: false).hasMatch(errorMessage(e));
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorView(
                  error: notFound ? ApiException('Employee not found', status: 404) : e,
                  onRetry: notFound ? null : _refreshProfile,
                ),
                TextButton(onPressed: () => context.go('/company/team'), child: const Text('← Back to team')),
              ],
            ),
          );
        },
        data: (raw) => _buildBody(asMap(raw), perms),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data, CompanyPermissions perms) {
    final preview = asMap(data['preview']);
    final access = _AccessFlags(asMap(data['access']), preview, data);
    final name = strOrNull(preview['name']) ?? strOrNull(preview['employeeName']) ?? 'Employee';
    final canRequest = perms.can('access_requests', 'manage');
    final canAssign = perms.can('workforce', 'manage');
    final canVerify = perms.can('verification', 'manage');
    final score = asNum(preview['trustScore']);
    final scoreMaxValue = asNum(preview['trustScoreMax']) ?? scoreMax;
    final (scoreLabel, scoreColor) = trustScoreStyle(score);
    final joined = preview['joinedDate'] ?? preview['joiningDate'] ?? preview['joinedAt'];

    String tabLabel(String label, bool pending) => pending ? '$label • Pending' : label;

    return RefreshIndicator(
      onRefresh: () async {
        _refreshProfile();
        try {
          await ref.read(companyEmployeeProfileProvider(_id).future);
        } catch (_) {
          // Rendered by the error view.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (access.fullProfileAccess) ...[
            AppCard(
              color: AppColors.successBg,
              borderColor: AppColors.success.withValues(alpha: 0.25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, color: AppColors.success, size: 26),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Full profile access granted',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                            SizedBox(height: 2),
                            Text(
                              'Review company-wise employment records below, then verify previous employers',
                              style: TextStyle(fontSize: 12.5, color: AppColors.inkBody),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if ((preview['onboardingStage'] == 'verified' && canAssign) || canRequest) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (preview['onboardingStage'] == 'verified' && canAssign)
                          Expanded(
                            child: AppButton(
                              label: 'Assign Department',
                              compact: true,
                              onPressed: () => _assign(name, preview),
                            ),
                          ),
                        if (preview['onboardingStage'] == 'verified' && canAssign && canRequest)
                          const SizedBox(width: 8),
                        if (canRequest)
                          Expanded(
                            child: AppButton(
                              label: 'Remove Access',
                              compact: true,
                              variant: AppButtonVariant.outline,
                              onPressed: () => _removeAccess(name),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Header ──
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(name: name, imageUrl: employeePhoto(preview), size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.inkStrong)),
                          if (strOrNull(preview['role'] ?? preview['designation']) != null)
                            Text(str(preview['role'] ?? preview['designation']),
                                style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody)),
                          if (strOrNull(preview['department']) != null)
                            Text(str(preview['department']),
                                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                          const SizedBox(height: 8),
                          EmploymentStatusBadge(status: strOrNull(preview['employmentStatus']) ?? 'active'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ScoreRing(
                      value: score ?? 0,
                      max: scoreMaxValue,
                      size: 84,
                      label: score == null ? '—' : scoreLabel,
                      color: scoreColor,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _AccessBadge(granted: access.profileAccess, label: 'Profile'),
                          _AccessBadge(granted: access.backgroundCheck, label: 'Docs'),
                          _AccessBadge(granted: access.verificationData, label: 'Verify'),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                InfoRow(label: 'PagerLook ID', value: strOrNull(preview['veriworkId'] ?? preview['pagerlookId']) ?? '—'),
                InfoRow(label: 'Joined', value: joined == null ? '—' : formatDate(joined)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          FilterChipsBar(
            padding: const EdgeInsets.symmetric(vertical: 8),
            options: {
              'profile': tabLabel('Profile', access.pendingProfileAccess),
              'documents': tabLabel('Background', access.pendingBackgroundCheck),
              'verification': tabLabel('Verification', access.pendingVerificationData),
            },
            selected: _tab,
            onSelected: _onTabChanged,
          ),
          const SizedBox(height: 8),

          if (_tab == 'profile')
            access.profileAccess
                ? _ProfileTab(
                    data: data,
                    canVerify: access.fullProfileAccess,
                    onVerifyJob: canVerify ? _verifyJob : null,
                    showFlowStepper: access.fullProfileAccess,
                  )
                : _LockedSection(
                    pending: access.pendingProfileAccess,
                    message: 'Request profile access to view full details',
                    buttonLabel: 'Request Profile Access',
                    onRequest: canRequest ? () => _openRequest('profile_access', name) : null,
                  ),
          if (_tab == 'documents')
            access.backgroundCheck
                ? _DocumentsTab(employeeId: _id, documentsSection: asMap(data['documentsSection']))
                : _LockedSection(
                    pending: access.pendingBackgroundCheck,
                    message: 'Request background check access to view vault documents',
                    buttonLabel: 'Request Background Check Access',
                    onRequest: canRequest ? () => _openRequest('background_check', name) : null,
                  ),
          if (_tab == 'verification')
            access.verificationData
                ? _VerificationTab(section: asMap(data['verificationSection']), trustScore: score)
                : _LockedSection(
                    pending: access.pendingVerificationData,
                    message: 'Request verification data access to view trust breakdown',
                    buttonLabel: 'Request Verification Data',
                    onRequest: canRequest ? () => _openRequest('verification_data', name) : null,
                  ),

          if (!access.fullProfileAccess && canRequest) ...[
            const SizedBox(height: 20),
            AppButton(
              label: 'Request Access',
              icon: Icons.key_outlined,
              variant: AppButtonVariant.outline,
              onPressed: () => _openRequest('full_profile_access', name),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.granted, required this.label});

  final bool granted;
  final String label;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label,
      label: '$label ${granted ? '✓' : '—'}',
      tone: granted ? Tone.success : Tone.neutral,
    );
  }
}

class _LockedSection extends StatelessWidget {
  const _LockedSection({required this.pending, required this.message, required this.buttonLabel, this.onRequest});

  final bool pending;
  final String message;
  final String buttonLabel;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const Icon(Icons.lock_outline, size: 32, color: AppColors.inkFaint),
            const SizedBox(height: 10),
            if (pending) ...[
              const StatusBadge('pending', label: 'PENDING', tone: Tone.warning),
              const SizedBox(height: 8),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.inkBody)),
            if (onRequest != null) ...[
              const SizedBox(height: 14),
              AppButton(label: buttonLabel, expand: false, onPressed: onRequest),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Profile tab (web EmployeeProfileTab) ─────────────────────────────────

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.data, required this.canVerify, this.onVerifyJob, required this.showFlowStepper});

  final Map<String, dynamic> data;
  final bool canVerify;
  final ValueChanged<Map<String, dynamic>>? onVerifyJob;
  final bool showFlowStepper;

  @override
  Widget build(BuildContext context) {
    final profileSection = data['profileSection'] is Map
        ? asMap(data['profileSection'])
        : asMap(data['basicProfile']);
    final jobs = asMapList(data['employmentHistory'] ?? profileSection['employmentHistory']);
    final verifiedCount = jobs
        .where((j) => asBool(j['isReusable']) || j['status'] == 'verified' || str(j['verificationLevel'], 'none') != 'none')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFlowStepper) ...[
          const AppCard(
            color: AppColors.successBg,
            title: 'Verification workflow',
            child: Column(
              children: [
                _StepRow(n: 1, label: 'Review employment', desc: 'Company-wise history below'),
                _StepRow(n: 2, label: 'Verify previous job', desc: 'Platform or email path'),
                _StepRow(n: 3, label: 'Assign to team', desc: 'After verification'),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (jobs.isEmpty)
          const AppCard(child: EmptyState(icon: Icons.work_outline, title: 'No employment history recorded.'))
        else ...[
          SectionHeader(
            'Employment by company',
            subtitle: 'Complete verification data, documents, and HR feedback — per employer',
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            action: StatusBadge('verified', label: 'Verified $verifiedCount/${jobs.length}', tone: Tone.brand),
          ),
          ...jobs.map(
            (job) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CompanyEmploymentCard(job: job, canVerify: canVerify, onVerify: onVerifyJob),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _PersonalDetailsCard(profile: profileSection),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.n, required this.label, required this.desc});

  final int n;
  final String label;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.brand600, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalDetailsCard extends StatelessWidget {
  const _PersonalDetailsCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final skills = asList(profile['skills']).map((s) => str(s)).where((s) => s.isNotEmpty).toList();
    final fields = <(String, String?)>[
      ('Email', strOrNull(profile['email'])),
      ('Phone', strOrNull(profile['phone']) ?? strOrNull(profile['mobile'])),
      ('Date of birth', strOrNull(profile['dateOfBirth']) != null ? formatDate(profile['dateOfBirth']) : null),
      ('Gender', strOrNull(profile['gender'])),
      ('City', strOrNull(profile['currentCity']) ?? strOrNull(profile['city'])),
      ('Department', strOrNull(profile['department'])),
      ('Current address', strOrNull(profile['currentAddress'])),
      ('Permanent address', strOrNull(profile['permanentAddress'])),
    ].where((f) => f.$2 != null).toList();

    return AppCard(
      title: 'Personal details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fields.isEmpty)
            const Text('No personal details shared.', style: TextStyle(color: AppColors.inkMuted)),
          ...fields.map((f) => InfoRow(label: f.$1, value: f.$2)),
          if (skills.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            const CaptionText('Skills'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skills.map((s) => StatusBadge(s, label: s, tone: Tone.brand)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Background (documents) tab ────────────────────────────────────────────

/// Web `resolveDocumentUrl`.
String? _documentUrl(Map<String, dynamic> doc) {
  final url = doc['url'];
  final file = doc['file'];
  final candidates = <Object?>[
    url is String ? url : null,
    url is Map ? url['url'] : null,
    url is Map ? url['signedUrl'] : null,
    doc['fileUrl'],
    doc['documentUrl'],
    doc['downloadUrl'],
    doc['signedUrl'],
    doc['link'],
    file is String ? file : (file is Map ? file['url'] : null),
    doc['path'],
    doc['storagePath'],
    doc['filePath'],
  ];
  for (final c in candidates) {
    final resolved = mediaUrl(c);
    if (resolved != null) return resolved;
  }
  return null;
}

/// Web `flattenDocuments`.
List<Map<String, dynamic>> _flattenDocuments(Object? data) {
  if (data == null) return const [];
  if (data is List) return asMapList(data);
  final map = asMap(data);
  for (final key in const ['documents', 'items', 'vaultItems']) {
    if (map[key] is List) return asMapList(map[key]);
  }
  return [for (final v in map.values) if (v is List) ...asMapList(v)];
}

List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> docs) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final doc in docs) {
    final key = strOrNull(doc['_id']) ??
        strOrNull(doc['id']) ??
        '${str(doc['originalName'] ?? doc['name']).toLowerCase()}::${str(doc['category'] ?? doc['type']).toLowerCase()}';
    if (seen.add(key)) out.add(doc);
  }
  return out;
}

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.employeeId, required this.documentsSection});

  final String employeeId;
  final Map<String, dynamic> documentsSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only built when background-check access is granted and the tab is open,
    // so documents are fetched exactly when the web fetches them.
    ref.listen<AsyncValue<dynamic>>(companyEmployeeDocumentsProvider(employeeId), (_, next) {
      final e = next.error;
      if (e is ApiException && e.isForbidden) {
        showToast('Document access not granted yet', type: ToastType.error);
        ref.invalidate(companyEmployeeProfileProvider(employeeId));
      }
    });
    final docsAsync = ref.watch(companyEmployeeDocumentsProvider(employeeId));

    if (docsAsync.isLoading && !docsAsync.hasValue) {
      return const LoadingView(label: 'Loading documents...');
    }
    final error = docsAsync.error;
    if (error != null && !(error is ApiException && error.isForbidden)) {
      return InfoBanner(tone: Tone.danger, message: errorMessage(error, 'Failed to load documents'));
    }

    final summary = asMap(documentsSection['summary']);
    final vaultItems = asMapList(documentsSection['vaultItems']);
    final employmentDocuments = asMapList(documentsSection['employmentDocuments']);
    final downloaded = _flattenDocuments(docsAsync.valueOrNull);
    final all = _dedupe([...(downloaded.isNotEmpty ? downloaded : vaultItems), ...employmentDocuments]);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final doc in all) {
      final cat = str(doc['category'] ?? doc['type'], 'other').toLowerCase();
      grouped.putIfAbsent(cat, () => []).add(doc);
    }

    // Web `formatSummaryEntries`.
    final summaryEntries = <(String, String)>[];
    summary.forEach((key, value) {
      if (value == null || value == '') return;
      if (key.toLowerCase() == 'bycategory' && value is Map) {
        asMap(value).forEach((cat, count) {
          if (count != null) summaryEntries.add((cat.replaceAll('_', ' '), str(count)));
        });
        return;
      }
      if (value is Map || value is List) return;
      summaryEntries.add((humanize(key), str(value)));
    });

    if (summaryEntries.isEmpty && grouped.isEmpty) {
      return const AppCard(child: EmptyState(icon: Icons.folder_open_outlined, title: 'No documents uploaded yet'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          tone: Tone.info,
          title: 'Background check flow',
          message: 'Employee uploads documents to vault → you request Background Check access → employee approves → '
              'documents appear here. Status pending means not yet verified; verified means reviewed.',
        ),
        if (summaryEntries.isNotEmpty) ...[
          const SizedBox(height: 14),
          StatGrid(
            children: summaryEntries.map((e) => StatCard(label: titleCase(e.$1), value: e.$2, tone: Tone.neutral)).toList(),
          ),
        ],
        ...grouped.entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(top: 14),
            child: AppCard(
              title: titleCase(entry.key.replaceAll('_', ' ')),
              child: Column(
                children: [
                  for (final doc in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DocumentRow(
                        title: strOrNull(doc['originalName']) ??
                            strOrNull(doc['name']) ??
                            strOrNull(doc['fileName']) ??
                            'Document',
                        status: strOrNull(doc['status']) ?? strOrNull(doc['verificationStatus']),
                        url: _documentUrl(doc),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Verification tab ──────────────────────────────────────────────────────

class _VerificationTab extends StatelessWidget {
  const _VerificationTab({required this.section, this.trustScore});

  final Map<String, dynamic> section;
  final num? trustScore;

  @override
  Widget build(BuildContext context) {
    final factors = asMapList(section['scoreFactors'] ?? section['factors']);
    final status = asMap(section['verificationStatus']);
    final tags = asMapList(section['verificationTags'] ?? pick(section, 'verificationHierarchy.tags'));
    final jobs = asMapList(section['jobs']);
    final score = trustScore ?? asNum(section['trustScore']) ?? 0;
    final ratingRaw = section['scoreRating'];
    final rating = ratingRaw is Map ? str(ratingRaw['label'], '—') : str(ratingRaw, '—');
    final (_, ringColor) = trustScoreStyle(score);

    const checklist = [
      ('profileSetupComplete', 'profile_setup_complete', 'Profile Verified'),
      ('aadhaarVerified', 'aadhaar_verified', 'Aadhaar Verified'),
      ('biometricVerified', 'biometric_verified', 'Biometric Verified'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tags.isNotEmpty) ...[
          AppCard(
            color: AppColors.brand50,
            title: 'Verification hierarchy',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => StatusBadge(str(t['id']), label: '✓ ${str(t['label'])}', tone: Tone.brand))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        AppCard(
          child: Row(
            children: [
              ScoreRing(value: score, max: scoreMax, size: 84, color: ringColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CaptionText('Score rating'),
                    const SizedBox(height: 4),
                    Text(rating,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.brand600)),
                    if (section['verifiedJobsCount'] != null || section['totalJobsCount'] != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Verified jobs: ${asInt(section['verifiedJobsCount'])} / ${asInt(section['totalJobsCount'])}',
                        style: const TextStyle(fontSize: 13, color: AppColors.inkBody),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Score factors',
          child: factors.isEmpty
              ? const Text('No score factors available yet.', style: TextStyle(color: AppColors.inkMuted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: factors.map((f) {
                    final points = asNum(f['points']) ?? 0;
                    final max = asNum(f['max']) ?? 0;
                    final tip = strOrNull(f['tip']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LabeledProgress(label: str(f['label']), value: points, max: max),
                          if (tip != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(tip, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (jobs.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppCard(
            title: 'Verification by company',
            child: Column(
              children: [
                for (var i = 0; i < jobs.length; i++) ...[
                  if (i > 0) const Divider(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(str(jobs[i]['company']),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                            Text(str(jobs[i]['title']),
                                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        'tag',
                        label: strOrNull(pick(jobs[i], 'verificationTag.label')) ?? 'Not verified',
                        tone: Tone.brand,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppCard(
          title: 'Verification status',
          child: Column(
            children: checklist.map((c) {
              final val = status[c.$1] ?? status[c.$2];
              final done = val == true || val == 'verified' || val == 'approved' || val == 'complete';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: done ? AppColors.success : AppColors.inkFaint,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      c.$3,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                        color: done ? AppColors.inkStrong : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
