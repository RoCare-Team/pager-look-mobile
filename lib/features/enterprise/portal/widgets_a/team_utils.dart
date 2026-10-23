import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json.dart';

/// Ports of `utils/enterpriseTeamUtils.js` and `utils/dashboardUtils.js`
/// (normalisers only — no sample data).

const int scoreMax = 1000;

// ── Employee helpers ──────────────────────────────────────────────────────

/// Web `resolveEmployeeId`.
String resolveEmployeeId(Map<String, dynamic>? emp) {
  if (emp == null) return '';
  for (final key in const ['employeeId', 'id', 'userId', 'employeeUserId', '_id']) {
    final v = strOrNull(emp[key]);
    if (v != null) return v;
  }
  return '';
}

String employeeName(Map<String, dynamic>? emp) =>
    strOrNull(emp?['employeeName']) ?? strOrNull(emp?['name']) ?? 'Employee';

String employeeRole(Map<String, dynamic>? emp) =>
    strOrNull(emp?['role']) ?? strOrNull(emp?['designation']) ?? '—';

String? employeePhoto(Map<String, dynamic>? emp) =>
    strOrNull(emp?['photoUrl']) ?? strOrNull(emp?['profilePhoto']) ?? strOrNull(emp?['avatar']);

/// Router path for an employee's profile (web `getEmployeeProfilePath`).
String? employeeProfilePath(Map<String, dynamic>? emp) {
  final id = resolveEmployeeId(emp);
  if (id.isEmpty) return null;
  return '/company/team/${Uri.encodeComponent(id)}';
}

/// Web `extractTeamDepartments`.
List<Map<String, dynamic>> extractTeamDepartments(Object? data) {
  if (data == null) return const [];
  if (data is List) return asMapList(data);
  return asMapList(asMap(data)['departments']);
}

/// Web `extractTeamEmployees`.
List<Map<String, dynamic>> extractTeamEmployees(Object? data) {
  if (data == null) return const [];
  final map = asMap(data);
  final top = asMapList(map['employees']);
  if (top.isNotEmpty) return top;
  final departments = data is List ? asMapList(data) : asMapList(map['departments']);
  return [
    for (final dept in departments)
      for (final emp in asMapList(dept['employees']))
        {...emp, 'department': strOrNull(emp['department']) ?? dept['name']},
  ];
}

/// Web `extractDepartmentEmployees`.
List<Map<String, dynamic>> extractDepartmentEmployees(Object? data) {
  if (data == null) return const [];
  if (data is List) return asMapList(data);
  final map = asMap(data);
  if (map['employees'] is List) return asMapList(map['employees']);
  if (map['members'] is List) return asMapList(map['members']);
  final dept = asMap(map['department']);
  if (dept['employees'] is List) return asMapList(dept['employees']);
  return const [];
}

enum AccessButton { requestAccess, pending, removeAccess }

/// Web `resolveEmployeeAccessButton`.
AccessButton resolveEmployeeAccessButton(Map<String, dynamic>? emp) {
  if (emp == null) return AccessButton.requestAccess;
  switch (str(emp['accessButton'])) {
    case 'pending':
      return AccessButton.pending;
    case 'remove_access':
      return AccessButton.removeAccess;
    case 'request_access':
      return AccessButton.requestAccess;
  }
  final access = asMap(emp['access']);
  bool t(String k) => access[k] == true;
  if (t('fullProfileAccess') || t('full_profile_access') || t('hasAllAccess')) return AccessButton.removeAccess;
  if (t('hasAnyAccess') ||
      t('profileAccess') ||
      t('profile_access') ||
      t('backgroundCheck') ||
      t('background_check') ||
      t('verificationData') ||
      t('verification_data')) {
    return AccessButton.removeAccess;
  }
  if (t('pendingFullProfileAccess') || t('pending_full_profile_access') || t('pendingFullProfile')) {
    return AccessButton.pending;
  }
  return AccessButton.requestAccess;
}

/// Web `getOnboardingStageStyle` labels.
String onboardingStageLabel(String? stage) => switch (stage) {
      'pending_verification' => 'Pending verification',
      'verified' => 'Ready to assign',
      'active' => 'Active',
      _ => 'New',
    };

/// Web `getEmploymentStatusStyle`.
(String, Tone) employmentStatusStyle(String? status) => switch (status) {
      'active' => ('Active', Tone.success),
      'on_leave' => ('On Leave', Tone.warning),
      'probation' => ('Probation', Tone.info),
      'terminated' => ('Terminated', Tone.danger),
      _ => ((status == null || status.isEmpty) ? 'Unknown' : status, Tone.neutral),
    };

/// Web `getTrustScoreStyle` (High ≥ 700, Medium ≥ 450, Low).
(String, Color) trustScoreStyle(Object? score) {
  final n = asNum(score) ?? 0;
  if (n >= 700) return ('High', AppColors.success);
  if (n >= 450) return ('Medium', AppColors.warning);
  return ('Low', AppColors.danger);
}

/// Web `getScoreRating` (the six PagerLook trust bands).
(String, Color) scoreRating(Object? score) {
  final n = asNum(score) ?? 0;
  if (n >= 951) return ('Elite Trust', const Color(0xFF7C3AED));
  if (n >= 851) return ('Excellent', AppColors.success);
  if (n >= 751) return ('Good', AppColors.brand600);
  if (n >= 601) return ('Fair', AppColors.warning);
  if (n >= 451) return ('Needs Improvement', const Color(0xFFEA580C));
  return ('High Risk', AppColors.danger);
}

/// Web `formatRequestType`.
String formatRequestType(Object? type) {
  final t = str(type);
  const labels = {
    'profile_access': 'Profile Access',
    'background_check': 'Background Check',
    'verification_data': 'Verification Data',
    'full_profile_access': 'Get Full Profile Access',
  };
  if (labels.containsKey(t)) return labels[t]!;
  if (t.isEmpty) return '—';
  return t
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Web `getAccessRequestStatusStyle`.
(String, Tone) accessRequestStatusStyle(String? status) => switch (status) {
      'accepted' => ('Accepted', Tone.success),
      'approved' => ('Approved', Tone.success),
      'pending' => ('Pending', Tone.warning),
      'rejected' => ('Rejected', Tone.danger),
      _ => ((status == null || status.isEmpty) ? 'Unknown' : status, Tone.neutral),
    };

// ── Dashboard helpers ─────────────────────────────────────────────────────

List<Map<String, dynamic>> normalizeJoinRequests(Object? data) {
  if (data is List) return asMapList(data);
  final map = asMap(data);
  if (map['requests'] is List) return asMapList(map['requests']);
  if (map['joinRequests'] is List) return asMapList(map['joinRequests']);
  return const [];
}

List<Map<String, dynamic>> normalizePendingInvitations(Object? data) {
  if (data is List) return asMapList(data);
  final map = asMap(data);
  if (map['invitations'] is List) return asMapList(map['invitations']);
  return const [];
}

bool _isPendingJoinRequest(Map<String, dynamic> r) {
  final s = str(r['status'], 'pending').toLowerCase();
  return s == 'pending' || s == 'submitted' || s == 'new';
}

class DashboardPendingItem {
  const DashboardPendingItem({
    required this.isInvitation,
    required this.id,
    required this.name,
    this.role = '',
    this.email = '',
    this.department = '',
    this.invitedAt,
    this.score,
  });

  final bool isInvitation;
  final String id;
  final String name;
  final String role;
  final String email;
  final String department;
  final Object? invitedAt;
  final num? score;
}

/// Web `buildDashboardPendingItems`.
List<DashboardPendingItem> buildDashboardPendingItems(
  List<Map<String, dynamic>> joinRequests,
  List<Map<String, dynamic>> invitations, [
  int limit = 4,
]) {
  final items = <DashboardPendingItem>[];
  for (final r in joinRequests.where(_isPendingJoinRequest)) {
    final name = strOrNull(r['name']) ?? strOrNull(r['employeeName']) ?? 'Candidate';
    final dept = strOrNull(r['department']);
    items.add(DashboardPendingItem(
      isInvitation: false,
      id: strOrNull(r['_id']) ?? strOrNull(r['id']) ?? name,
      name: name,
      role: '${strOrNull(r['role']) ?? strOrNull(r['designation']) ?? '—'}${dept != null ? ' • $dept' : ''}',
      score: asNum(r['employeeScore']) ?? asNum(r['trustScore']),
    ));
  }
  for (final inv in invitations) {
    final email = strOrNull(inv['employeeEmail']) ?? strOrNull(inv['email']) ?? '—';
    final name = strOrNull(inv['employeeName']) ?? email;
    items.add(DashboardPendingItem(
      isInvitation: true,
      id: strOrNull(inv['invitationId']) ?? strOrNull(inv['id']) ?? email,
      name: name,
      email: email,
      department: strOrNull(inv['department']) ?? '—',
      invitedAt: inv['invitedAt'] ?? inv['createdAt'],
    ));
  }
  return items.take(limit).toList();
}

class DashboardStats {
  const DashboardStats({
    required this.totalCandidates,
    required this.approvedEmployees,
    required this.pendingRequests,
    required this.pendingJoinRequests,
    required this.pendingInvitations,
    required this.avgVeriScore,
  });

  final int totalCandidates;
  final int approvedEmployees;
  final int pendingRequests;
  final int pendingJoinRequests;
  final int pendingInvitations;
  final int avgVeriScore;
}

int _pickFirstInt(Map<String, dynamic> obj, List<String> keys) {
  for (final k in keys) {
    final v = obj[k];
    if (v != null && v != '') return asNum(v)?.round() ?? 0;
  }
  return 0;
}

/// Web `resolveDashboardStats`.
DashboardStats resolveDashboardStats(
  Object? dashboard, {
  Object? teamData,
  List<Map<String, dynamic>> joinRequests = const [],
  List<Map<String, dynamic>> pendingInvitations = const [],
}) {
  final d = asMap(dashboard);
  final raw = d['stats'] is Map ? asMap(d['stats']) : (d['metrics'] is Map ? asMap(d['metrics']) : d);

  // computeTeamTotals
  final departments = extractTeamDepartments(teamData);
  final linked = departments
      .where((dep) => asInt(dep['employeeCount']) > 0 || asList(dep['employees']).isNotEmpty)
      .toList();
  final employees = extractTeamEmployees(teamData);
  final totalLinked = linked.fold<int>(
    0,
    (sum, dep) => sum + (dep['employeeCount'] != null ? asInt(dep['employeeCount']) : asList(dep['employees']).length),
  );
  final scores = employees
      .map((e) => asNum(e['trustScore'] ?? e['employeeScore']))
      .whereType<num>()
      .where((n) => n > 0)
      .toList();
  final deptScores = linked.map((dep) => asNum(dep['averageTrustScore'])).whereType<num>().where((n) => n > 0).toList();
  var avgTrust = 0;
  if (scores.isNotEmpty) {
    avgTrust = (scores.fold<num>(0, (a, b) => a + b) / scores.length).round();
  } else if (deptScores.isNotEmpty) {
    avgTrust = (deptScores.fold<num>(0, (a, b) => a + b) / deptScores.length).round();
  }
  final activeCount = employees.where((e) => str(e['employmentStatus'], 'active') == 'active').length;

  final pendingJoin = joinRequests.where(_isPendingJoinRequest).length;
  final pendingInvite = pendingInvitations.length;

  int or(int a, int b) => a != 0 ? a : b;

  return DashboardStats(
    totalCandidates: or(
      _pickFirstInt(raw, const ['totalCandidates', 'totalEmployees', 'linkedEmployees', 'totalLinked', 'workforceCount']),
      totalLinked,
    ),
    approvedEmployees: or(
      _pickFirstInt(raw, const ['approvedEmployees', 'approved', 'verifiedEmployees', 'activeEmployees']),
      activeCount,
    ),
    pendingRequests: or(
      _pickFirstInt(raw, const ['pendingRequests', 'pendingJoinRequests', 'joinRequestsPending']),
      pendingJoin + pendingInvite,
    ),
    pendingJoinRequests: pendingJoin,
    pendingInvitations: pendingInvite,
    avgVeriScore: or(
      _pickFirstInt(raw, const ['avgVeriScore', 'averageTrustScore', 'avgTrustScore', 'averageVeriScore']),
      avgTrust,
    ),
  );
}

/// label → count. Web `buildDepartmentDistribution`.
Map<String, num> buildDepartmentDistribution(Object? teamData) {
  final out = <String, num>{};
  for (final d in extractTeamDepartments(teamData)) {
    final count = d['employeeCount'] != null ? asInt(d['employeeCount']) : asList(d['employees']).length;
    if (asInt(d['employeeCount']) > 0 || asList(d['employees']).isNotEmpty) {
      out[str(d['name'], 'Unassigned')] = count;
    }
  }
  return out;
}

/// Web `buildDepartmentTrustBars` — department → average trust score.
Map<String, num> buildDepartmentTrustBars(Object? teamData) {
  final out = <String, num>{};
  for (final d in extractTeamDepartments(teamData)) {
    final hasEmployees = asInt(d['employeeCount']) > 0 || asList(d['employees']).isNotEmpty;
    if (hasEmployees && d['averageTrustScore'] != null) {
      out[str(d['name'], 'Unassigned')] = asNum(d['averageTrustScore']) ?? 0;
    }
  }
  return out;
}

/// Web `buildTrustScoreDistribution` — range → count.
Map<String, num> buildTrustScoreDistribution(Object? teamData) {
  final buckets = <String, num>{'700+': 0, '450-699': 0, '0-449': 0};
  for (final emp in extractTeamEmployees(teamData)) {
    final score = asNum(emp['trustScore'] ?? emp['employeeScore']);
    if (score == null) continue;
    if (score >= 700) {
      buckets['700+'] = buckets['700+']! + 1;
    } else if (score >= 450) {
      buckets['450-699'] = buckets['450-699']! + 1;
    } else if (score >= 0) {
      buckets['0-449'] = buckets['0-449']! + 1;
    }
  }
  return buckets;
}

/// `[{department|range|label, count}]` from the insights API → label → count.
Map<String, num> chartMapFrom(Object? list, {List<String> labelKeys = const ['department', 'range', 'label']}) {
  final out = <String, num>{};
  for (final item in asMapList(list)) {
    String? label;
    for (final k in labelKeys) {
      label = strOrNull(item[k]);
      if (label != null) break;
    }
    out[label ?? '—'] = asNum(item['count']) ?? 0;
  }
  return out;
}

// ── Employee onboarding trend ─────────────────────────────────────────────

class TrendSeries {
  const TrendSeries({required this.id, required this.label, required this.values, required this.color});
  final String id;
  final String label;
  final List<num> values;
  final Color color;
}

class OnboardingTrend {
  const OnboardingTrend({required this.labels, required this.series, required this.title, required this.subtitle});
  final List<String> labels;
  final List<TrendSeries> series;
  final String title;
  final String subtitle;

  bool get hasData => labels.isNotEmpty && series.any((s) => s.values.any((v) => v > 0));
}

const _seriesColors = {
  'new': AppColors.brand600,
  'pending': AppColors.warning,
  'approved': AppColors.success,
};
const _fallbackColors = [AppColors.brand600, AppColors.warning, AppColors.success, AppColors.danger];

Color _seriesColor(String id, int i) => _seriesColors[id] ?? _fallbackColors[i % _fallbackColors.length];

List<num>? _seriesValues(Map<String, dynamic> source, List<String> keys) {
  for (final k in keys) {
    final v = asList(source[k]);
    if (v.isNotEmpty) return v.map((n) => asNum(n) ?? 0).toList();
  }
  return null;
}

OnboardingTrend? _apiOnboardingTrend(Object? dashboard, Object? insights) {
  final candidates = [
    pick(dashboard, 'employeeOnboardingTrend'),
    pick(dashboard, 'onboardingTrend'),
    pick(dashboard, 'stats.employeeOnboardingTrend'),
    pick(insights, 'employeeOnboardingTrend'),
    pick(insights, 'verificationAnalytics.dailyOnboarding'),
    pick(insights, 'verificationAnalytics.onboardingTrend'),
  ];
  for (final c in candidates) {
    if (c is! Map) continue;
    final raw = asMap(c);
    final rawLabels = asList(raw['labels']);
    final rawSeries = asMapList(raw['series']);
    if (rawLabels.isNotEmpty && rawSeries.length >= 2) {
      final labels = rawLabels.map((l) => str(l)).toList();
      final series = <TrendSeries>[];
      for (var i = 0; i < rawSeries.length; i++) {
        final s = rawSeries[i];
        final id = strOrNull(s['id']) ?? strOrNull(s['key']) ?? 'series-$i';
        final values = asList(s['values'] ?? s['data']).map((v) => asNum(v) ?? 0).toList();
        if (values.length != labels.length) continue;
        series.add(TrendSeries(
          id: id,
          label: strOrNull(s['label']) ?? strOrNull(s['name']) ?? 'Series ${i + 1}',
          values: values,
          color: _seriesColor(id, i),
        ));
      }
      if (series.length >= 2 && series.any((s) => s.values.any((v) => v > 0))) {
        return OnboardingTrend(
          labels: labels,
          series: series,
          title: strOrNull(raw['title']) ?? 'Employee Activity',
          subtitle: strOrNull(raw['subtitle']) ?? 'Daily new, pending and approved employees',
        );
      }
    }
    final labels = asList(raw['labels']).isNotEmpty ? asList(raw['labels']) : asList(raw['days']);
    if (labels.isNotEmpty) {
      final newVals = _seriesValues(raw, const ['new', 'joined', 'received']);
      final pendingVals = _seriesValues(raw, const ['pending', 'awaiting']);
      final approvedVals = _seriesValues(raw, const ['approved', 'accepted', 'verified']);
      if (newVals != null || pendingVals != null || approvedVals != null) {
        final zeros = List<num>.filled(labels.length, 0);
        final series = [
          TrendSeries(id: 'new', label: 'New', values: newVals ?? zeros, color: _seriesColor('new', 0)),
          TrendSeries(id: 'pending', label: 'Pending', values: pendingVals ?? zeros, color: _seriesColor('pending', 1)),
          TrendSeries(id: 'approved', label: 'Approved', values: approvedVals ?? zeros, color: _seriesColor('approved', 2)),
        ].where((s) => s.values.any((v) => v > 0)).toList();
        if (series.isNotEmpty) {
          return OnboardingTrend(
            labels: labels.map((l) => str(l)).toList(),
            series: series,
            title: 'Employee Activity',
            subtitle: 'Daily new, pending and approved employees',
          );
        }
      }
    }
  }
  return null;
}

bool _isApprovedStatus(Object? s) => const ['approved', 'active', 'verified', 'accepted'].contains(str(s).toLowerCase());
bool _isRejectedStatus(Object? s) =>
    const ['rejected', 'declined', 'expired', 'cancelled', 'canceled'].contains(str(s).toLowerCase());

/// Web `buildEmployeeOnboardingTrend` — API series when present, otherwise
/// the last 7 days computed from real join requests / invitations / team.
OnboardingTrend buildEmployeeOnboardingTrend({
  List<Map<String, dynamic>> joinRequests = const [],
  List<Map<String, dynamic>> invitations = const [],
  Object? teamData,
  Object? dashboard,
  Object? insights,
}) {
  final fromApi = _apiOnboardingTrend(dashboard, insights);
  if (fromApi != null) return fromApi;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  String key(DateTime d) => DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
  final index = {for (var i = 0; i < days.length; i++) key(days[i]): i};
  final newCounts = List<num>.filled(7, 0);
  final approved = List<num>.filled(7, 0);
  final rejected = List<num>.filled(7, 0);

  void bump(DateTime? date, List<num> target) {
    if (date == null) return;
    final i = index[key(date)];
    if (i != null) target[i] = target[i] + 1;
  }

  for (final req in joinRequests) {
    final created = asDate(req['createdAt'] ?? req['submittedAt'] ?? req['requestedAt']);
    final action = asDate(req['approvedAt'] ?? req['reviewedAt'] ?? req['updatedAt'] ?? req['respondedAt']);
    bump(created, newCounts);
    if (_isApprovedStatus(req['status']) && action != null) {
      bump(action, approved);
    } else if (_isRejectedStatus(req['status']) && action != null) {
      bump(action, rejected);
    }
  }
  for (final inv in invitations) {
    final invited = asDate(inv['invitedAt'] ?? inv['createdAt']);
    final action = asDate(inv['acceptedAt'] ?? inv['updatedAt'] ?? inv['respondedAt']);
    bump(invited, newCounts);
    if (_isApprovedStatus(inv['status']) && action != null) {
      bump(action, approved);
    } else if (_isRejectedStatus(inv['status']) && action != null) {
      bump(action, rejected);
    }
  }
  for (final emp in extractTeamEmployees(teamData)) {
    final joined = asDate(emp['joinedAt'] ?? emp['linkedAt'] ?? emp['createdAt']);
    final status = strOrNull(emp['employmentStatus']) ?? strOrNull(emp['status']) ?? 'active';
    if (joined != null && _isApprovedStatus(status)) bump(joined, approved);
  }

  num running = 0;
  final pending = <num>[];
  for (var i = 0; i < 7; i++) {
    running += newCounts[i] - approved[i] - rejected[i];
    if (running < 0) running = 0;
    pending.add(running);
  }

  return OnboardingTrend(
    labels: days.map((d) => DateFormat('EEE').format(d)).toList(),
    series: [
      TrendSeries(id: 'new', label: 'New', values: newCounts, color: _seriesColor('new', 0)),
      TrendSeries(id: 'pending', label: 'Pending', values: pending, color: _seriesColor('pending', 1)),
      TrendSeries(id: 'approved', label: 'Approved', values: approved, color: _seriesColor('approved', 2)),
    ],
    title: 'Employee Activity',
    subtitle: 'Daily new, pending and approved employees',
  );
}

/// `Invited 3 days ago · Engineering`.
String invitationSubtitle(Object? invitedAt, String? department) {
  final rel = formatRelativeInviteDate(invitedAt);
  return (department == null || department.isEmpty) ? rel : '$rel · $department';
}
