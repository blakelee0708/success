/// Centralized route paths. Keep all navigation targets here.
class Routes {
  Routes._();

  static const firstScreen = '/';
  static const seniorOnboarding = '/onboarding';
  static const guardianStart = '/guardian-start';
  static const guardianLogin = '/guardian-login';
  static const guardianDashboard = '/guardian';

  // Senior launcher (Phase 1)
  static const easyHome = '/home/easy';
  static const detailedHome = '/home/detailed';
  static const sos = '/sos';
  static const familyLink = '/family-link';
  static const familyMessages = '/messages';

  // Senior-facing settings (Phase 2)
  //
  // [seniorSettings] is the list itself. It was a tab inside 자세한 화면 until
  // that screen's tab bar was replaced by 긴급 구조 요청 and 가족; the list is
  // the only way into the two screens below it, so it needed a route.
  static const seniorSettings = '/settings';
  static const appSettings = '/settings/apps';
  static const fontSize = '/settings/font-size';

  /// What the senior's family can see. Reached from 설정 → 가족,
  /// because the consent card asks once and then goes away.
  static const familyVisibility = '/settings/family-visibility';
}
