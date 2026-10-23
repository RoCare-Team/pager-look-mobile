import '../auth/auth_controller.dart';
import '../auth/home_routes.dart';

/// Route guards — a direct port of the web's `routes/guards.jsx`.
/// Returns the location to redirect to, or null to allow.
String? resolveRedirect(AuthController auth, Uri uri) {
  final path = uri.path;

  if (auth.booting) return path == '/splash' ? null : '/splash';
  if (path == '/splash') return auth.homeRoute;

  // Landing page: signed-in users go straight to their portal.
  if (path == '/') return auth.isAuthenticated ? auth.homeRoute : null;

  // Always public — the token/code in the link is the proof.
  const publicPrefixes = [
    '/u/',
    '/join/',
    '/verify-employment/',
    '/forgot-password',
    '/reset-password',
    '/enterprise/accept-invite',
    '/enterprise/register',
    '/employee/join',
    '/scan',
    '/demo-request',
  ];
  if (publicPrefixes.any(path.startsWith)) return null;

  // ── Admin ──────────────────────────────────────────────────────────────
  if (path == '/admin/login') {
    return auth.isAuthenticated && auth.isAdmin ? '/admin/dashboard' : null;
  }
  if (path.startsWith('/admin')) {
    return auth.isAuthenticated && auth.isAdmin ? null : '/admin/login';
  }

  // ── Enterprise ─────────────────────────────────────────────────────────
  if (path == '/enterprise/login') {
    return auth.isAuthenticated && auth.isEnterprise ? enterpriseHomeRoute(auth.company) : null;
  }
  const enterpriseOnboarding = [
    '/enterprise/verify',
    '/enterprise/review',
    '/enterprise/pending-approval',
    '/enterprise/rejected',
  ];
  if (enterpriseOnboarding.contains(path)) {
    return auth.isAuthenticated && auth.isEnterprise ? null : '/enterprise/login';
  }
  if (path.startsWith('/enterprise') || path.startsWith('/company')) {
    if (!auth.isAuthenticated || !auth.isEnterprise) return '/enterprise/login';
    final company = auth.company;
    if (isEnterpriseRejected(company)) return '/enterprise/rejected';
    if (isEnterprisePendingApproval(company)) return '/enterprise/pending-approval';
    if (!isEnterpriseApproved(company)) return enterpriseHomeRoute(company);
    return null;
  }

  // ── Employee ───────────────────────────────────────────────────────────
  if (path == '/employee/otp' || path == '/employee/login' || path == '/employee') {
    if (auth.isAuthenticated && auth.isEmployee) return employeeHomeRoute(auth.profile);
    return path == '/employee/otp' ? null : '/employee/otp';
  }
  if (path.startsWith('/employee')) {
    return auth.isAuthenticated && auth.isEmployee ? null : '/employee/otp';
  }

  return null;
}
