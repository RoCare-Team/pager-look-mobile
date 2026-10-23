import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';

/// Read providers shared by the dashboard / team / profile / access screens.
/// Each mirrors one `useQuery` key from the web (`enterpriseKeys.*`).

final enterpriseDashboardProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchDashboard(),
);

final companyTeamProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchTeam(),
);

final companyPendingInvitationsProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchPendingInvitations(),
);

final dashboardJoinRequestsProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchJoinRequests(),
);

final companyInsightsProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchInsights(),
);

final teamDepartmentProvider = FutureProvider.autoDispose.family<dynamic, String>(
  (ref, department) => ref.watch(enterpriseApiProvider).fetchTeamDepartment(department),
);

final companyEmployeeProfileProvider = FutureProvider.autoDispose.family<dynamic, String>(
  (ref, employeeId) => ref.watch(enterpriseApiProvider).fetchEmployeeProfile(employeeId),
);

final companyEmployeeDocumentsProvider = FutureProvider.autoDispose.family<dynamic, String>(
  (ref, employeeId) => ref.watch(enterpriseApiProvider).fetchEmployeeDocuments(employeeId),
);

final accessRequestTypesProvider = FutureProvider.autoDispose<dynamic>(
  (ref) => ref.watch(enterpriseApiProvider).fetchAccessRequestTypes(),
);

typedef AccessRequestsQuery = ({String status, int page});

final companyAccessRequestsProvider = FutureProvider.autoDispose.family<dynamic, AccessRequestsQuery>(
  (ref, q) => ref.watch(enterpriseApiProvider).fetchAccessRequests(status: q.status, page: q.page, limit: 20),
);

/// Everything that changes when access/assignment changes for an employee.
void invalidateTeamData(WidgetRef ref, {String? employeeId, String? department}) {
  ref.invalidate(companyTeamProvider);
  ref.invalidate(companyPendingInvitationsProvider);
  if (department != null) ref.invalidate(teamDepartmentProvider(department));
  if (employeeId != null) {
    ref.invalidate(companyEmployeeProfileProvider(employeeId));
    ref.invalidate(companyEmployeeDocumentsProvider(employeeId));
  }
}
