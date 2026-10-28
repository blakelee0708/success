import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a guardian agreed to before an account existed.
///
/// `GuardianStartScreen` had carried one grey line - 시작하면 서비스
/// 이용약관과 개인정보 처리방침에 동의하게 됩니다 - since Phase 3, as plain
/// text with no link, naming a 이용약관 that **did not exist anywhere in the
/// repository**. The sign-up form said nothing at all.
///
/// That pattern is the American one. 개인정보보호법 asks for an act: the
/// items itemised, 필수 and 선택 answerable apart, and each readable before
/// it is agreed to. Passing through a screen is not an act.
class SignupConsent {
  const SignupConsent({
    required this.version,
    required this.agreedAt,
    required this.marketing,
  });

  /// Which wording was agreed to. **Stored rather than assumed**: the day the
  /// terms change, a stored `true` from the old ones is not consent to the
  /// new, and nothing else on disk could tell the two apart.
  final int version;

  final DateTime agreedAt;

  /// The one optional item. Kept apart from the required pair because a
  /// 선택 item folded into them is a 필수 item wearing the wrong label.
  final bool marketing;
}

/// Bumped whenever `site/terms.html` or the collection list in
/// `site/privacy.html` changes in a way a person would want to re-read.
///
/// **1 is the first version ever shown to anybody**, because the line it
/// replaces was never an agreement to anything.
const signupConsentVersion = 1;

abstract interface class SignupConsentStore {
  Future<SignupConsent?> load();
  Future<void> save(SignupConsent consent);
  Future<void> clear();
}

class SharedPreferencesSignupConsentStore implements SignupConsentStore {
  static const storageKey = 'guardian.signup.consent';

  @override
  Future<SignupConsent?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(storageKey);
    if (raw == null || raw.length < 3) return null;
    final version = int.tryParse(raw[0]);
    final at = DateTime.tryParse(raw[1]);
    if (version == null || at == null) return null;
    return SignupConsent(
      version: version,
      agreedAt: at,
      marketing: raw[2] == 'true',
    );
  }

  @override
  Future<void> save(SignupConsent consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, [
      '${consent.version}',
      consent.agreedAt.toIso8601String(),
      '${consent.marketing}',
    ]);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}

class InMemorySignupConsentStore implements SignupConsentStore {
  InMemorySignupConsentStore([this.consent]);

  SignupConsent? consent;

  @override
  Future<SignupConsent?> load() async => consent;

  @override
  Future<void> save(SignupConsent value) async => consent = value;

  @override
  Future<void> clear() async => consent = null;
}

final signupConsentStoreProvider = Provider<SignupConsentStore>(
  (ref) => SharedPreferencesSignupConsentStore(),
);

/// Whether this phone has already agreed to the current wording.
///
/// A stored agreement to an **older** version does not count, which is the
/// whole reason the version is stored rather than a bare flag.
final signupConsentProvider = FutureProvider<SignupConsent?>((ref) async {
  final stored = await ref.watch(signupConsentStoreProvider).load();
  if (stored == null || stored.version != signupConsentVersion) return null;
  return stored;
});
