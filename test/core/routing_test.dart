import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/core/auth/auth_controller.dart';
import 'package:veriwork_mobile/core/auth/home_routes.dart';
import 'package:veriwork_mobile/core/network/api_client.dart';
import 'package:veriwork_mobile/core/router/guards.dart';
import 'package:veriwork_mobile/core/storage/session_store.dart';
import 'package:veriwork_mobile/data/api/auth_api.dart';
import 'package:veriwork_mobile/data/api/employee_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('employeeHomeRoute (web: getEmployeeHomeRoute)', () {
    test('no profile → sign in', () => expect(employeeHomeRoute(null), '/employee/otp'));
    test('setup incomplete → profile setup', () {
      expect(employeeHomeRoute({'profileSetupComplete': false}), '/employee/profile-setup');
    });
    test('setup done, Aadhaar pending → verification', () {
      expect(employeeHomeRoute({'profileSetupComplete': true, 'aadhaarVerified': false}), '/employee/verification');
    });
    test('Aadhaar verified without face match → portal (face is optional)', () {
      expect(
        employeeHomeRoute({'profileSetupComplete': true, 'aadhaarVerified': true, 'biometricVerified': false}),
        '/employee/score',
      );
    });
    test('portalUnlocked flag wins', () {
      expect(employeeHomeRoute({'profileSetupComplete': true, 'portalUnlocked': true}), '/employee/score');
    });
  });

  group('enterpriseHomeRoute (web: getEnterpriseHomeRoute)', () {
    test('approved → dashboard', () {
      expect(enterpriseHomeRoute({'approvalStatus': 'approved'}), '/enterprise/dashboard');
    });
    test('submitted/pending → pending approval', () {
      expect(enterpriseHomeRoute({'approvalStatus': 'submitted'}), '/enterprise/pending-approval');
      expect(enterpriseHomeRoute({'approvalStatus': 'pending'}), '/enterprise/pending-approval');
      expect(enterpriseHomeRoute({'approvalStatus': 'changes_requested'}), '/enterprise/pending-approval');
    });
    test('rejected → rejected', () {
      expect(enterpriseHomeRoute({'approvalStatus': 'rejected'}), '/enterprise/rejected');
    });
    test('legacy flags without approvalStatus', () {
      expect(enterpriseHomeRoute({'isVerified': true}), '/enterprise/dashboard');
      expect(enterpriseHomeRoute({'onboardingComplete': true}), '/enterprise/pending-approval');
    });
    test('draft progresses through onboarding steps', () {
      expect(enterpriseHomeRoute({'approvalStatus': 'draft', 'name': 'Acme'}), '/enterprise/verify');
      expect(enterpriseHomeRoute({'approvalStatus': 'draft', 'name': 'Acme', 'brn': 'U123'}), '/enterprise/review');
      expect(enterpriseHomeRoute({'approvalStatus': 'draft'}), '/enterprise/register');
    });
  });

  group('route guards (web: guards.jsx)', () {
    late SessionStore store;
    late AuthController auth;

    Future<void> signIn(Map<String, dynamic> user, {Map<String, dynamic>? profile, Map<String, dynamic>? company}) async {
      await store.setTokens(access: 'A', refresh: 'R');
      await store.setUser(user);
      await store.setProfile(profile);
      await store.setCompany(company);
    }

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      store = SessionStore();
      final api = ApiClient(store);
      auth = AuthController(store: store, api: api, authApi: AuthApi(api), employeeApi: EmployeeApi(api));
      await auth.bootstrap(); // no session stored → no network call
    });

    String? go(String location) => resolveRedirect(auth, Uri.parse(location));

    test('guests can reach public pages and are sent to logins elsewhere', () {
      expect(go('/'), isNull);
      expect(go('/u/asha-k'), isNull);
      expect(go('/join/ABC123'), isNull);
      expect(go('/verify-employment/tok'), isNull);
      expect(go('/enterprise/register'), isNull);
      expect(go('/employee/score'), '/employee/otp');
      expect(go('/company/team'), '/enterprise/login');
      expect(go('/enterprise/review'), '/enterprise/login');
      expect(go('/admin/dashboard'), '/admin/login');
    });

    test('employees are kept out of guest screens and other portals', () async {
      await signIn({'id': 'u1', 'role': 'employee'}, profile: {'profileSetupComplete': true, 'aadhaarVerified': true});
      expect(go('/'), '/employee/score');
      expect(go('/employee/otp'), '/employee/score');
      expect(go('/employee/vault'), isNull);
      expect(go('/company/team'), '/enterprise/login');
      expect(go('/admin/companies'), '/admin/login');
    });

    test('enterprise portal requires an approved company', () async {
      await signIn({'id': 'u2', 'role': 'enterprise_admin'}, company: {'approvalStatus': 'submitted'});
      expect(go('/enterprise/dashboard'), '/enterprise/pending-approval');
      expect(go('/enterprise/pending-approval'), isNull);

      await store.setCompany({'approvalStatus': 'rejected'});
      expect(go('/company/team'), '/enterprise/rejected');

      await store.setCompany({'approvalStatus': 'approved'});
      expect(go('/company/team/emp1'), isNull);
      expect(go('/enterprise/login'), '/enterprise/dashboard');
    });

    test('admins land on the dashboard', () async {
      await signIn({'id': 'u3', 'role': 'platform_admin'});
      expect(go('/admin/login'), '/admin/dashboard');
      expect(go('/admin/employees/123'), isNull);
      expect(go('/'), '/admin/dashboard');
    });
  });
}
