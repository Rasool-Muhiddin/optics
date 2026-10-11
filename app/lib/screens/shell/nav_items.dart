import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../models/session.dart';

/// One sidebar entry. [ownerOnly] / [feature] only hide it — the server enforces access.
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.ownerOnly = false,
    this.feature,
  });

  final String path;
  final String label;
  final IconData icon;
  final bool ownerOnly;
  final String? feature;

  bool visibleTo(Session session) =>
      (!ownerOnly || session.isOwner) && (feature == null || session.hasFeature(feature!));
}

/// Sidebar order. Screens are added per roadmap phase; until then the path shows "coming soon".
const List<NavItem> navItems = [
  NavItem(path: AppRoutes.home, label: AppStrings.home, icon: Icons.dashboard_outlined),
  NavItem(path: AppRoutes.patients, label: AppStrings.navPatients, icon: Icons.people_outline),
  NavItem(path: AppRoutes.pos, label: AppStrings.navPos, icon: Icons.point_of_sale),
  NavItem(path: AppRoutes.jobs, label: AppStrings.navJobs, icon: Icons.work_outline),
  NavItem(
    path: AppRoutes.inventory,
    label: AppStrings.navInventory,
    icon: Icons.inventory_2_outlined,
  ),
  NavItem(path: AppRoutes.orders, label: AppStrings.navOrders, icon: Icons.local_shipping_outlined),
  NavItem(
    path: AppRoutes.referrals,
    label: AppStrings.navReferrals,
    icon: Icons.medical_services_outlined,
    feature: Features.doctorLinking,
  ),
  NavItem(
    path: AppRoutes.reports,
    label: AppStrings.navReports,
    icon: Icons.bar_chart,
    ownerOnly: true,
  ),
  NavItem(
    path: AppRoutes.users,
    label: AppStrings.navUsers,
    icon: Icons.manage_accounts_outlined,
    ownerOnly: true,
  ),
  NavItem(
    path: AppRoutes.settings,
    label: AppStrings.navSettings,
    icon: Icons.settings_outlined,
    ownerOnly: true,
  ),
];

NavItem? navItemFor(String path) {
  for (final item in navItems) {
    if (item.path == path) return item;
  }
  return null;
}
