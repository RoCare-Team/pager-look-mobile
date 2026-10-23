import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../utils/json.dart';

/// Company-scoped permissions of the signed-in company user — port of the
/// web's `usePermissions`. Levels: none < view < manage (manage satisfies view).
///
/// Modules: dashboard, team, workforce, join_requests, access_requests,
/// verification, qr_onboarding, company_users, settings.
class CompanyPermissions {
  const CompanyPermissions({
    this.companyRole,
    this.roleLabel = '',
    this.permissions = const {},
    this.assignableRoles = const [],
  });

  factory CompanyPermissions.fromJson(Object? data) {
    final root = asMap(data);
    final payload = root['data'] is Map ? asMap(root['data']) : root;
    return CompanyPermissions(
      companyRole: strOrNull(payload['companyRole']),
      roleLabel: str(payload['roleLabel']),
      permissions: asMap(payload['permissions']).map((k, v) => MapEntry(k, str(v, 'none'))),
      assignableRoles: asList(payload['assignableRoles']),
    );
  }

  final String? companyRole;
  final String roleLabel;
  final Map<String, String> permissions;
  final List<dynamic> assignableRoles;

  /// False until a permission map has loaded. While unknown, keep navigation
  /// visible (the backend guards every route) but hide power-granting actions.
  bool get ready => permissions.isNotEmpty;

  static const _rank = {'none': 0, 'view': 1, 'manage': 2};

  bool can(String module, [String level = 'view']) {
    final actual = permissions[module] ?? 'none';
    return (_rank[actual] ?? 0) >= (_rank[level] ?? 0);
  }

  /// Navigation visibility: everything while unknown, filtered once known.
  bool canSee(String module) => !ready || can(module, 'view');
}

final companyPermissionsProvider = FutureProvider.autoDispose<CompanyPermissions>((ref) async {
  // Re-fetch whenever the signed-in user changes.
  final userId = ref.watch(authProvider.select((a) => a.userId));
  if (userId.isEmpty) return const CompanyPermissions();
  final data = await ref.watch(enterpriseApiProvider).fetchMyPermissions();
  // Cache a successful load for the session; failures retry on next read.
  ref.keepAlive();
  return CompanyPermissions.fromJson(data);
});
