import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../screens/activation/activation_screen.dart';
import '../../screens/doctor/doctor_labs_screen.dart';
import '../../screens/doctor/doctor_login_screen.dart';
import '../../screens/doctor/doctor_referrals_screen.dart';
import '../../screens/doctor/doctor_shell.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/inventory/inventory_screen.dart';
import '../../screens/inventory/product_detail_screen.dart';
import '../../screens/jobs/job_detail_screen.dart';
import '../../screens/jobs/jobs_board_screen.dart';
import '../../screens/login/login_screen.dart';
import '../../screens/orders/order_detail_screen.dart';
import '../../screens/orders/orders_screen.dart';
import '../../screens/patients/patient_detail_screen.dart';
import '../../screens/patients/patients_screen.dart';
import '../../screens/pos/pos_screen.dart';
import '../../screens/referrals/referral_detail_screen.dart';
import '../../screens/referrals/referrals_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/users/users_screen.dart';
import '../../screens/sales/credit_customers_screen.dart';
import '../../screens/sales/invoice_detail_screen.dart';
import '../../screens/sales/invoices_screen.dart';
import '../../screens/placeholder/coming_soon_screen.dart';
import '../../screens/shell/main_shell.dart';
import '../../screens/shell/nav_items.dart';
import '../../screens/splash/splash_screen.dart';
import '../../services/auth_controller.dart';
import 'app_routes.dart';

export 'app_routes.dart';

/// Where the auth state allows the user to be; null = stay on [location].
@visibleForTesting
String? authRedirect(AuthState? state, String location) {
  switch (state) {
    case null:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case NeedsActivation():
      return location == AppRoutes.activate || location == AppRoutes.doctorLogin
          ? null
          : AppRoutes.activate;
    case LoggedOut():
      return location == AppRoutes.login || location == AppRoutes.doctorLogin
          ? null
          : AppRoutes.login;
    case DoctorLoggedIn():
      return AppRoutes.isDoctorArea(location) ? null : AppRoutes.doctorHome;
    case LoggedIn(:final session):
      if (AppRoutes.isPublic(location) || AppRoutes.isDoctorArea(location)) return AppRoutes.home;
      final item = navItemFor(location) ?? navSectionFor(location);
      if (item != null && !item.visibleTo(session)) return AppRoutes.home;
      return null;
  }
}

/// Sections with a real screen (the rest show "coming soon").
const _builtSections = {
  AppRoutes.home,
  AppRoutes.inventory,
  AppRoutes.patients,
  AppRoutes.pos,
  AppRoutes.invoices,
  AppRoutes.credit,
  AppRoutes.jobs,
  AppRoutes.orders,
  AppRoutes.referrals,
  AppRoutes.reports,
  AppRoutes.settings,
  AppRoutes.users,
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider).value, state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.activate, builder: (context, state) => const ActivationScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
      GoRoute(path: AppRoutes.doctorLogin, builder: (context, state) => const DoctorLoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            DoctorShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.doctorHome,
            builder: (context, state) => const DoctorReferralsScreen(),
          ),
          GoRoute(
            path: AppRoutes.doctorLabs,
            builder: (context, state) => const DoctorLabsScreen(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            MainShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: AppRoutes.patients,
            builder: (context, state) => const PatientsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    PatientDetailScreen(patientId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.pos, builder: (context, state) => const PosScreen()),
          GoRoute(
            path: AppRoutes.invoices,
            builder: (context, state) => const InvoicesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    InvoiceDetailScreen(invoiceId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.credit,
            builder: (context, state) => const CreditCustomersScreen(),
          ),
          GoRoute(
            path: AppRoutes.jobs,
            builder: (context, state) => const JobsBoardScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    JobDetailScreen(jobId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.orders,
            builder: (context, state) => const OrdersScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    OrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.referrals,
            builder: (context, state) => const ReferralsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ReferralDetailScreen(referralId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsScreen()),
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
          GoRoute(path: AppRoutes.users, builder: (context, state) => const UsersScreen()),
          GoRoute(
            path: AppRoutes.inventory,
            builder: (context, state) => const InventoryScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ProductDetailScreen(productId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          for (final item in navItems.where((i) => !_builtSections.contains(i.path)))
            GoRoute(
              path: item.path,
              builder: (context, state) => ComingSoonScreen(title: item.label),
            ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
