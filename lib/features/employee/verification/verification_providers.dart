import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/json.dart';

/// `GET /employee/verification/status` (web `employeeKeys.verification`).
final verificationStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchVerificationStatus());
});

/// `GET /employee/verification/aadhaar` (web `employeeKeys.aadhaarSubmission`).
/// `{ status: not_submitted|pending|approved|rejected, method, checks, … }`
final aadhaarSubmissionProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchAadhaarSubmission());
});

/// Invalidate everything a verification change can affect.
void invalidateVerification(WidgetRef ref) {
  ref.invalidate(verificationStatusProvider);
  ref.invalidate(aadhaarSubmissionProvider);
}
