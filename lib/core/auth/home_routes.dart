import '../utils/json.dart';

/// Ports of the web's `employeeRoutes.js`, `employeeProfileUtils.isPortalUnlocked`
/// and `enterpriseApproval.js` — these decide where each user lands.

bool isPortalUnlocked(Map<String, dynamic>? profile) {
  if (profile == null) return false;
  if (profile['portalUnlocked'] == true || profile['isVerified'] == true) return true;
  return asBool(profile['profileSetupComplete']) && asBool(profile['aadhaarVerified']);
}

String employeeHomeRoute(Map<String, dynamic>? profile) {
  if (profile == null) return '/employee/otp';
  if (!asBool(profile['profileSetupComplete'])) return '/employee/profile-setup';
  // Only Aadhaar routes back to verification — the face match is optional.
  if (!isPortalUnlocked(profile)) return '/employee/verification';
  return '/employee/score';
}

/// draft | submitted | pending | changes_requested | approved | rejected
String enterpriseApprovalStatus(Map<String, dynamic>? company) {
  if (company == null) return 'draft';
  final status = strOrNull(company['approvalStatus']);
  if (status != null) return status;
  if (asBool(company['isVerified'])) return 'approved';
  if (asBool(company['onboardingComplete'])) return 'submitted';
  return 'draft';
}

bool isEnterpriseApproved(Map<String, dynamic>? company) => enterpriseApprovalStatus(company) == 'approved';

bool isEnterprisePendingApproval(Map<String, dynamic>? company) {
  final s = enterpriseApprovalStatus(company);
  // `changes_requested`: the admin asked for fixes — the pending-approval
  // screen shows the per-document re-upload cards and the resubmit action.
  return s == 'submitted' || s == 'pending' || s == 'changes_requested';
}

bool isEnterpriseRejected(Map<String, dynamic>? company) => enterpriseApprovalStatus(company) == 'rejected';

String _onboardingStepRoute(Map<String, dynamic>? company) {
  if (asBool(company?['onboardingComplete'])) return '/enterprise/review';
  final verification = asMap(pick(company, 'onboarding.verification'));
  if (strOrNull(company?['brn']) != null ||
      strOrNull(company?['taxId']) != null ||
      strOrNull(verification['brn']) != null ||
      strOrNull(verification['taxId']) != null) {
    return '/enterprise/review';
  }
  if (strOrNull(company?['companyLegalName']) != null ||
      strOrNull(company?['name']) != null ||
      strOrNull(pick(company, 'onboarding.basicInfo.companyName')) != null) {
    return '/enterprise/verify';
  }
  return '/enterprise/register';
}

String enterpriseHomeRoute(Map<String, dynamic>? company) {
  switch (enterpriseApprovalStatus(company)) {
    case 'rejected':
      return '/enterprise/rejected';
    case 'submitted':
    case 'pending':
    case 'changes_requested':
      return '/enterprise/pending-approval';
    case 'approved':
      return '/enterprise/dashboard';
    default:
      return _onboardingStepRoute(company);
  }
}
