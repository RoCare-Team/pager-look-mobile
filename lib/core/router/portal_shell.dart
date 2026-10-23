import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/home_routes.dart';
import '../providers.dart';
import '../widgets/feedback.dart';

/// A bottom-navigation destination.
class ShellTab {
  const ShellTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.matchPrefixes = const [],
    this.requiresVerification = false,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Other locations that should highlight this tab.
  final List<String> matchPrefixes;

  /// Employee tabs locked until Aadhaar is verified (web sidebar `requiresVerification`).
  final bool requiresVerification;

  bool matches(String location) =>
      location == path || location.startsWith('$path/') || matchPrefixes.any(location.startsWith);
}

const employeeTabs = [
  ShellTab(
    path: '/employee/score',
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  ShellTab(
    path: '/employee/job-history',
    label: 'Jobs',
    icon: Icons.work_outline,
    selectedIcon: Icons.work,
    requiresVerification: true,
  ),
  ShellTab(
    path: '/employee/activity',
    label: 'Activity',
    icon: Icons.notifications_none,
    selectedIcon: Icons.notifications,
    requiresVerification: true,
  ),
  ShellTab(
    path: '/employee/vault',
    label: 'Vault',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    requiresVerification: true,
  ),
  ShellTab(
    path: '/employee/settings',
    label: 'Account',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

const enterpriseTabs = [
  ShellTab(
      path: '/enterprise/dashboard',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard),
  ShellTab(path: '/company/team', label: 'Team', icon: Icons.groups_outlined, selectedIcon: Icons.groups),
  ShellTab(path: '/company/verification', label: 'Verify', icon: Icons.verified_outlined, selectedIcon: Icons.verified),
  ShellTab(path: '/company/access-requests', label: 'Access', icon: Icons.key_outlined, selectedIcon: Icons.key),
  ShellTab(path: '/enterprise/menu', label: 'More', icon: Icons.menu, selectedIcon: Icons.menu_open),
];

const adminTabs = [
  ShellTab(
      path: '/admin/dashboard',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard),
  ShellTab(path: '/admin/companies', label: 'Companies', icon: Icons.business_outlined, selectedIcon: Icons.business),
  ShellTab(path: '/admin/employees', label: 'Employees', icon: Icons.badge_outlined, selectedIcon: Icons.badge),
  ShellTab(path: '/admin/aadhaar-requests', label: 'Aadhaar', icon: Icons.fingerprint, selectedIcon: Icons.fingerprint),
  ShellTab(path: '/admin/menu', label: 'More', icon: Icons.menu, selectedIcon: Icons.menu_open),
];

/// Scaffold with bottom navigation wrapping a portal's top-level screens.
/// Each tab screen supplies its own inner Scaffold/AppBar.
class PortalShell extends ConsumerWidget {
  const PortalShell({super.key, required this.tabs, required this.location, required this.child});

  final List<ShellTab> tabs;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authProvider.select((a) => a.profile));
    final unlocked = isPortalUnlocked(profile);
    final index = tabs.indexWhere((t) => t.matches(location));

    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFECECEF)))),
        child: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) {
            final tab = tabs[i];
            if (tab.requiresVerification && !unlocked) {
              showToast('Complete Aadhaar verification to unlock');
              return;
            }
            context.go(tab.path);
          },
          destinations: tabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(t.requiresVerification && !unlocked ? Icons.lock_outline : t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
