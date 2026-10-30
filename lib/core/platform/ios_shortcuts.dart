import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../router/app_router.dart';
import 'ios_native.dart';

/// iOS Home Screen quick actions: keeps the per-role items in sync with the
/// session and opens the picked route once the stored session is restored.
/// "Scan QR" is a static item in Info.plist, so it is always there.
Future<void> setUpIosShortcuts(ProviderContainer container, Future<void> bootstrapped) async {
  if (!IosNative.isSupported) return;

  final auth = container.read(authProvider);
  String? lastKey;
  void sync() {
    final key = auth.isAuthenticated ? (auth.role ?? '') : 'guest';
    if (key == lastKey) return;
    lastKey = key;
    IosNative.setShortcuts(_shortcutsFor(auth));
  }

  auth.addListener(sync);

  await IosNative.listenForShortcuts((route) async {
    await bootstrapped;
    final router = container.read(routerProvider);
    // Start from the user's home so Back leads somewhere sensible; the guards
    // still decide whether the route is allowed.
    router.go(auth.homeRoute);
    router.push(route);
  });

  await bootstrapped;
  sync();
}

List<IosShortcut> _shortcutsFor(AuthController auth) {
  if (!auth.isAuthenticated) return const [];
  if (auth.isEmployee) {
    return const [
      IosShortcut(route: '/employee/professional-id', title: 'Professional ID', icon: 'person.text.rectangle'),
      IosShortcut(route: '/employee/job-history', title: 'Job History', icon: 'briefcase'),
      IosShortcut(route: '/employee/vault', title: 'Document Vault', icon: 'doc.text'),
    ];
  }
  if (auth.isEnterprise) {
    return const [
      IosShortcut(route: '/company/team', title: 'Team', icon: 'person.3'),
      IosShortcut(route: '/company/verification', title: 'Verifications', icon: 'checkmark.seal'),
      IosShortcut(route: '/company/access-requests', title: 'Access Requests', icon: 'key'),
    ];
  }
  return const [
    IosShortcut(route: '/admin/companies', title: 'Companies', icon: 'building.2'),
    IosShortcut(route: '/admin/employees', title: 'Employees', icon: 'person.3'),
  ];
}
