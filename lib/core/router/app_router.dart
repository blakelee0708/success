import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/care/presentation/family_visibility_screen.dart';
import '../../features/family/presentation/family_link_screen.dart';
import '../../features/guardian/presentation/guardian_login_screen.dart';
import '../../features/guardian/presentation/guardian_dashboard_screen.dart';
import '../../features/guardian/presentation/guardian_start_screen.dart';
import '../../features/messages/presentation/family_message_screen.dart';
import '../../features/launcher/presentation/detailed_home_screen.dart';
import '../../features/launcher/presentation/easy_home_screen.dart';
import '../../features/launcher/presentation/app_settings_screen.dart';
import '../../features/launcher/presentation/font_size_screen.dart';
import '../../features/launcher/presentation/senior_settings_screen.dart';
import '../../features/launcher/presentation/sos_screen.dart';
import '../../features/onboarding/presentation/screen_mode_choice_screen.dart';
import 'launch_gate.dart';
import 'routes.dart';

/// App-wide router. The first route is the launch gate: it decides whether the
/// splash should be shown at all. It reads the saved screen mode, so a senior
/// who has chosen one lands on their home, and since Phase 4 it also reads the
/// restored guardian session. See [launchDestinationFor].
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.firstScreen,
    routes: [
      GoRoute(
        path: Routes.firstScreen,
        builder: (context, state) => const LaunchGate(),
      ),
      GoRoute(
        path: Routes.seniorOnboarding,
        builder: (context, state) => const ScreenModeChoiceScreen(),
      ),
      GoRoute(
        path: Routes.guardianStart,
        builder: (context, state) => const GuardianStartScreen(),
      ),
      GoRoute(
        path: Routes.guardianLogin,
        builder: (context, state) => const GuardianLoginScreen(),
      ),
      GoRoute(
        path: Routes.guardianDashboard,
        builder: (context, state) => const GuardianDashboardScreen(),
      ),
      GoRoute(
        path: Routes.easyHome,
        builder: (context, state) => const EasyHomeScreen(),
      ),
      GoRoute(
        path: Routes.detailedHome,
        builder: (context, state) => const DetailedHomeScreen(),
      ),
      GoRoute(path: Routes.sos, builder: (context, state) => const SosScreen()),
      GoRoute(
        path: Routes.familyLink,
        builder: (context, state) => const FamilyLinkScreen(),
      ),
      GoRoute(
        path: Routes.familyMessages,
        builder: (context, state) => const FamilyMessageScreen(),
      ),
      GoRoute(
        path: Routes.seniorSettings,
        builder: (context, state) => const SeniorSettingsScreen(),
      ),
      GoRoute(
        path: Routes.familyVisibility,
        builder: (context, state) => const FamilyVisibilityScreen(),
      ),
      GoRoute(
        path: Routes.appSettings,
        builder: (context, state) => const AppSettingsScreen(),
      ),
      GoRoute(
        path: Routes.fontSize,
        builder: (context, state) => const FontSizeScreen(),
      ),
    ],
  );
});
