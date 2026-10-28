/// What this build of the app calls itself.
///
/// **A constant rather than a plugin.** `package_info_plus` would read it off
/// the platform, which means a new dependency, a new entry in the merged
/// manifest that `privacy_policy_test` walks, and a platform channel that
/// `flutter test` has no answer for. The one thing it would buy - a value
/// that cannot fall out of step - is bought here instead by a test that reads
/// `pubspec.yaml` off disk, the same way `application_id_test` holds the
/// Gradle copy of `com.jalboine.app` to the Dart one.
///
/// It is sent on the parent's check-in so their family can be told when the
/// phone is running an old build. **That is the whole reason it exists**: a
/// launcher is the one app Play will not update on its own, because it is
/// always the app in front of the user, and the senior is the last person who
/// should be asked to go and fix that.
const appVersion = '1.0.0+1';

/// The build number, which is the only part worth comparing.
///
/// Version names are marketing and can go sideways; the build number only
/// ever goes up, so 부모님 폰이 더 낮다 is a question with an answer. Returns
/// null for anything that is not `name+number`, and a null never means *old*
/// - an unreadable version is a phone that said nothing.
int? buildNumberOf(String? version) {
  if (version == null) return null;
  final plus = version.lastIndexOf('+');
  if (plus < 0) return null;
  return int.tryParse(version.substring(plus + 1));
}
