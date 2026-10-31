/// Centralized route paths. Keep all navigation targets here.
class Routes {
  Routes._();

  static const firstScreen = '/';
  static const seniorOnboarding = '/onboarding';
  static const guardianStart = '/guardian-start';

  /// The same screen on its last page, the one with the sign-in buttons.
  static const guardianStartButtons = '/guardian-start?page=last';
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

  /// 사용법. First in 설정's list, because somebody who is stuck looks there
  /// before anywhere else.
  static const manual = '/settings/manual';
  static const fontSize = '/settings/font-size';

  /// The onboarding choice again, from 바꾸기. Same two cards, no home-app
  /// question after, and a way home without choosing.
  static const screenMode = '/settings/screen-mode';

  /// What the senior's family can see. Reached from 설정 → 가족,
  /// because the consent card asks once and then goes away.
  static const familyVisibility = '/settings/family-visibility';
}
