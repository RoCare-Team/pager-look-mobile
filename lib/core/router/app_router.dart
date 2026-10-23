import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_aadhaar_requests_screen.dart';
import '../../features/admin/admin_aadhaar_review_screen.dart';
import '../../features/admin/admin_companies_screen.dart';
import '../../features/admin/admin_company_review_screen.dart';
import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/admin/admin_demo_requests_screen.dart';
import '../../features/admin/admin_employee_detail_screen.dart';
import '../../features/admin/admin_employees_screen.dart';
import '../../features/admin/admin_login_screen.dart';
import '../../features/admin/admin_menu_screen.dart';
import '../../features/admin/admin_verifications_screen.dart';
import '../../features/auth/enterprise_login_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/employee/onboarding/employee_join_screen.dart';
import '../../features/employee/onboarding/employee_otp_screen.dart';
import '../../features/employee/onboarding/profile_setup_screen.dart';
import '../../features/employee/portal/activity_screen.dart';
import '../../features/employee/portal/add_experience_screen.dart';
import '../../features/employee/portal/document_vault_screen.dart';
import '../../features/employee/portal/employee_access_consent_screen.dart';
import '../../features/employee/portal/employee_invitations_screen.dart';
import '../../features/employee/portal/employee_score_screen.dart';
import '../../features/employee/portal/job_history_screen.dart';
import '../../features/employee/portal/job_verification_screen.dart';
import '../../features/employee/portal/professional_id_screen.dart';
import '../../features/employee/settings/digilocker_settings_screen.dart';
import '../../features/employee/settings/email_settings_screen.dart';
import '../../features/employee/settings/employee_settings_screen.dart';
import '../../features/employee/settings/privacy_security_screen.dart';
import '../../features/employee/settings/support_screen.dart';
import '../../features/employee/verification/aadhaar_verification_screen.dart';
import '../../features/employee/verification/biometric_liveness_screen.dart';
import '../../features/employee/verification/identity_verification_screen.dart';
import '../../features/enterprise/onboarding/accept_invite_screen.dart';
import '../../features/enterprise/onboarding/application_rejected_screen.dart';
import '../../features/enterprise/onboarding/business_basic_info_screen.dart';
import '../../features/enterprise/onboarding/company_verification_screen.dart';
import '../../features/enterprise/onboarding/pending_approval_screen.dart';
import '../../features/enterprise/onboarding/review_submission_screen.dart';
import '../../features/enterprise/portal/access_requests_screen.dart';
import '../../features/enterprise/portal/audit_logs_screen.dart';
import '../../features/enterprise/portal/company_insights_screen.dart';
import '../../features/enterprise/portal/company_users_screen.dart';
import '../../features/enterprise/portal/dashboard_screen.dart';
import '../../features/enterprise/portal/department_details_screen.dart';
import '../../features/enterprise/portal/employee_profile_screen.dart';
import '../../features/enterprise/portal/employment_verification_screen.dart';
import '../../features/enterprise/portal/enterprise_menu_screen.dart';
import '../../features/enterprise/portal/enterprise_settings_screen.dart';
import '../../features/enterprise/portal/join_requests_screen.dart';
import '../../features/enterprise/portal/qr_onboarding_screen.dart';
import '../../features/enterprise/portal/team_management_screen.dart';
import '../../features/enterprise/portal/workforce_screen.dart';
import '../../features/landing/welcome_screen.dart';
import '../../features/public/demo_request_screen.dart';
import '../../features/public/public_profile_screen.dart';
import '../../features/public/qr_join_screen.dart';
import '../../features/public/qr_scan_screen.dart';
import '../../features/public/verify_employment_screen.dart';
import '../providers.dart';
import 'guards.dart';
import 'portal_shell.dart';
import 'splash_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Tab roots use no transition so switching tabs feels instant.
Page<void> _tab(Widget child) => NoTransitionPage<void>(child: child);

String? _q(GoRouterState s, String key) {
  final v = s.uri.queryParameters[key];
  return (v == null || v.isEmpty) ? null : v;
}

/// Routes mirror the web app's paths (`AppRoutes.jsx`) so email/QR links map
/// 1:1 onto screens. Detail routes are declared before the shells that own
/// their parent path, and open full-screen over the tab bar.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) => resolveRedirect(auth, state.uri),
    errorBuilder: (context, state) => const WelcomeScreen(),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/', builder: (_, __) => const WelcomeScreen()),

      // ── Legacy aliases kept from the web router ─────────────────────────
      GoRoute(path: '/employee/dashboard', redirect: (_, __) => '/employee/score'),
      GoRoute(path: '/employee/access-consent', redirect: (_, __) => '/employee/access-requests'),
      GoRoute(path: '/employee/login', redirect: (_, __) => '/employee/otp'),
      GoRoute(path: '/employee', redirect: (_, __) => '/employee/otp'),
      GoRoute(path: '/enterprise/verification', redirect: (_, __) => '/enterprise/verify'),
      GoRoute(path: '/enterprise/application-rejected', redirect: (_, __) => '/enterprise/rejected'),
      GoRoute(path: '/enterprise/team', redirect: (_, __) => '/company/team'),
      GoRoute(path: '/enterprise/access-requests', redirect: (_, __) => '/company/access-requests'),
      GoRoute(path: '/enterprise/insights', redirect: (_, __) => '/company/insights'),
      GoRoute(path: '/admin/enterprise-approvals', redirect: (_, __) => '/admin/companies'),

      // ── Public ──────────────────────────────────────────────────────────
      GoRoute(path: '/u/:slug', builder: (_, s) => PublicProfileScreen(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/join/:code', builder: (_, s) => QrJoinScreen(code: s.pathParameters['code']!)),
      GoRoute(
        path: '/verify-employment/:token',
        builder: (_, s) => VerifyEmploymentScreen(token: s.pathParameters['token']!),
      ),
      GoRoute(path: '/scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(path: '/demo-request', builder: (_, __) => const DemoRequestScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, s) => ResetPasswordScreen(token: _q(s, 'token') ?? '')),
      GoRoute(path: '/enterprise/accept-invite', builder: (_, s) => AcceptInviteScreen(token: _q(s, 'token') ?? '')),
      GoRoute(path: '/employee/join', builder: (_, s) => EmployeeJoinScreen(token: _q(s, 'token') ?? '')),

      // ── Admin ───────────────────────────────────────────────────────────
      GoRoute(path: '/admin/login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: '/admin/companies/:id', builder: (_, s) => AdminCompanyReviewScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/admin/employees/:id', builder: (_, s) => AdminEmployeeDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
        path: '/admin/aadhaar-requests/:id',
        builder: (_, s) => AdminAadhaarReviewScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/admin/verifications', builder: (_, __) => const AdminVerificationsScreen()),
      GoRoute(path: '/admin/demo-requests', builder: (_, __) => const AdminDemoRequestsScreen()),
      ShellRoute(
        builder: (context, state, child) => PortalShell(tabs: adminTabs, location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/admin/dashboard', pageBuilder: (_, __) => _tab(const AdminDashboardScreen())),
          GoRoute(
            path: '/admin/companies',
            pageBuilder: (_, s) => _tab(AdminCompaniesScreen(initialStatus: _q(s, 'status') ?? 'submitted')),
          ),
          GoRoute(
            path: '/admin/employees',
            pageBuilder: (_, s) => _tab(AdminEmployeesScreen(initialStatus: _q(s, 'status') ?? 'all')),
          ),
          GoRoute(path: '/admin/aadhaar-requests', pageBuilder: (_, __) => _tab(const AdminAadhaarRequestsScreen())),
          GoRoute(path: '/admin/menu', pageBuilder: (_, __) => _tab(const AdminMenuScreen())),
        ],
      ),

      // ── Enterprise: auth & onboarding ───────────────────────────────────
      GoRoute(path: '/enterprise/login', builder: (_, __) => const EnterpriseLoginScreen()),
      GoRoute(path: '/enterprise/register', builder: (_, __) => const BusinessBasicInfoScreen()),
      GoRoute(path: '/enterprise/verify', builder: (_, __) => const CompanyVerificationScreen()),
      GoRoute(path: '/enterprise/review', builder: (_, __) => const ReviewSubmissionScreen()),
      GoRoute(path: '/enterprise/pending-approval', builder: (_, __) => const PendingApprovalScreen()),
      GoRoute(path: '/enterprise/rejected', builder: (_, __) => const ApplicationRejectedScreen()),

      // ── Enterprise: approved portal ─────────────────────────────────────
      GoRoute(
        path: '/company/team/department/:department',
        builder: (_, s) => DepartmentDetailsScreen(department: s.pathParameters['department']!),
      ),
      GoRoute(
        path: '/company/team/:employeeId',
        builder: (_, s) => CompanyEmployeeProfileScreen(employeeId: s.pathParameters['employeeId']!),
      ),
      GoRoute(path: '/company/insights', builder: (_, __) => const CompanyInsightsScreen()),
      GoRoute(path: '/company/audit-logs', builder: (_, __) => const AuditLogsScreen()),
      GoRoute(path: '/enterprise/workforce', builder: (_, __) => const WorkforceScreen()),
      GoRoute(path: '/enterprise/join-requests', builder: (_, __) => const JoinRequestsScreen()),
      GoRoute(path: '/enterprise/qr-onboarding', builder: (_, __) => const QrOnboardingScreen()),
      GoRoute(path: '/enterprise/users', builder: (_, __) => const CompanyUsersScreen()),
      GoRoute(path: '/enterprise/settings', builder: (_, __) => const EnterpriseSettingsScreen()),
      ShellRoute(
        builder: (context, state, child) => PortalShell(tabs: enterpriseTabs, location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/enterprise/dashboard',
            pageBuilder: (_, s) => _tab(EnterpriseDashboardScreen(showVerifiedSuccess: _q(s, 'verified') == 'true')),
          ),
          GoRoute(path: '/company/team', pageBuilder: (_, __) => _tab(const TeamManagementScreen())),
          GoRoute(path: '/company/verification', pageBuilder: (_, __) => _tab(const EmploymentVerificationScreen())),
          GoRoute(
            path: '/company/access-requests',
            pageBuilder: (_, s) => _tab(AccessRequestsScreen(initialStatus: _q(s, 'status') ?? 'all')),
          ),
          GoRoute(path: '/enterprise/menu', pageBuilder: (_, __) => _tab(const EnterpriseMenuScreen())),
        ],
      ),

      // ── Employee: auth & onboarding ─────────────────────────────────────
      GoRoute(path: '/employee/otp', builder: (_, s) => EmployeeOtpScreen(fromJoin: _q(s, 'from') == 'join')),
      GoRoute(path: '/employee/profile-setup', builder: (_, s) => ProfileSetupScreen(initialStep: _q(s, 'step'))),
      GoRoute(path: '/employee/verification', builder: (_, __) => const IdentityVerificationScreen()),
      GoRoute(
        path: '/employee/verification/aadhaar',
        builder: (_, s) => AadhaarVerificationScreen(status: _q(s, 'status'), message: _q(s, 'message')),
      ),
      GoRoute(path: '/employee/verification/biometric', builder: (_, __) => const BiometricLivenessScreen()),

      // ── Employee: portal ────────────────────────────────────────────────
      GoRoute(path: '/employee/job-history/add', builder: (_, __) => const AddExperienceScreen()),
      GoRoute(
        path: '/employee/jobs/:jobId/verify',
        builder: (_, s) => JobVerificationScreen(jobId: s.pathParameters['jobId']!),
      ),
      GoRoute(path: '/employee/professional-id', builder: (_, __) => const ProfessionalIdScreen()),
      GoRoute(path: '/employee/invitations', builder: (_, __) => const EmployeeInvitationsScreen()),
      GoRoute(path: '/employee/access-requests', builder: (_, __) => const EmployeeAccessConsentScreen()),
      GoRoute(path: '/employee/settings/email', builder: (_, __) => const EmailSettingsScreen()),
      GoRoute(path: '/employee/settings/privacy', builder: (_, __) => const PrivacySecurityScreen()),
      GoRoute(
        path: '/employee/settings/digilocker',
        builder: (_, s) => DigiLockerSettingsScreen(status: _q(s, 'status'), message: _q(s, 'message')),
      ),
      GoRoute(path: '/employee/settings/support', builder: (_, __) => const SupportScreen()),
      ShellRoute(
        builder: (context, state, child) => PortalShell(tabs: employeeTabs, location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/employee/score', pageBuilder: (_, __) => _tab(const EmployeeScoreScreen())),
          GoRoute(path: '/employee/job-history', pageBuilder: (_, __) => _tab(const JobHistoryScreen())),
          GoRoute(path: '/employee/activity', pageBuilder: (_, __) => _tab(const ActivityScreen())),
          GoRoute(path: '/employee/vault', pageBuilder: (_, __) => _tab(const DocumentVaultScreen())),
          GoRoute(path: '/employee/settings', pageBuilder: (_, __) => _tab(const EmployeeSettingsScreen())),
        ],
      ),
    ],
  );
});
