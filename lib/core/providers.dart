import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/admin_api.dart';
import '../data/api/auth_api.dart';
import '../data/api/employee_api.dart';
import '../data/api/enterprise_api.dart';
import '../data/api/public_api.dart';
import 'auth/auth_controller.dart';
import 'network/api_client.dart';
import 'storage/session_store.dart';

/// Overridden in `main()` with the loaded store.
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(sessionStoreProvider)));

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final employeeApiProvider = Provider<EmployeeApi>((ref) => EmployeeApi(ref.watch(apiClientProvider)));
final enterpriseApiProvider = Provider<EnterpriseApi>((ref) => EnterpriseApi(ref.watch(apiClientProvider)));
final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(apiClientProvider)));
final publicApiProvider = Provider<PublicApi>((ref) => PublicApi(ref.watch(apiClientProvider)));

/// The session. Screens read `ref.watch(authProvider)` for user/profile/company
/// and call `ref.read(authProvider).loginEmployee(...)` etc.
final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(
    store: ref.watch(sessionStoreProvider),
    api: ref.watch(apiClientProvider),
    authApi: ref.watch(authApiProvider),
    employeeApi: ref.watch(employeeApiProvider),
  );
});
