import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/core/providers.dart';
import 'package:veriwork_mobile/core/storage/session_store.dart';
import 'package:veriwork_mobile/core/theme/app_theme.dart';
import 'package:veriwork_mobile/features/employee/portal/employee_score_screen.dart';

// Renders the employee Home on a phone-sized surface to catch layout overflows.
void main() {
  testWidgets('home renders without layout errors', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SessionStore();
    await store.load();
    await store.setProfile({
      'name': 'Robin Kumar',
      'veriworkId': 'VW-IAFA-85',
      'profileSetupComplete': true,
      'aadhaarVerified': true,
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          employeeScoreProvider.overrideWith(
            (ref) async => {
              'employeeScore': 482,
              'minScore': 300,
              'maxScore': 1000,
              'trustPoints': 260,
              'maxTrustPoints': 1000,
              'percentile': 'Top 60%',
              'endorsements': {'count': 2},
              'verificationTags': [
                {'label': 'Profile Verified'},
              ],
              'factors': [
                {'label': 'Profile Completion', 'points': 80, 'max': 100, 'tip': 'Complete your basic profile details.'},
                {'label': 'Identity Verification', 'points': 160, 'max': 225},
              ],
            },
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const EmployeeScoreScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('482'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Score Breakdown'), findsOneWidget);
  });
}
