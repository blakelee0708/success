import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/guardian_auth_repository.dart';

/// The OAuth redirect lives in three places that cannot see each other, and
/// a mismatch fails silently in the worst way: the guardian signs in with
/// Kakao, the browser redirects to a scheme nothing claims, and they are
/// left looking at a dead tab having been signed in to nothing. `flutter
/// analyze` does not read XML and `flutter test` does not build an APK, so
/// this reads the manifest off disk — the same job
/// `application_id_test.dart` does for Gradle.
///
/// The third copy is the project's `uri_allow_list`, which lives on the
/// server and cannot be checked from here at all.
void main() {
  test('the manifest claims the scheme the Dart side redirects to', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    final uri = Uri.parse(oauthRedirect);
    expect(
      manifest,
      contains('android:scheme="${uri.scheme}"'),
      reason: 'the manifest must claim ${uri.scheme}://',
    );
    expect(
      manifest,
      contains('android:host="${uri.host}"'),
      reason: 'the manifest must claim the ${uri.host} host',
    );
  });

  test('the scheme is the application id, which is already unique', () {
    // Any scheme would work, but a made-up one can collide with another app
    // on the phone — and whichever app claims it gets handed the session.
    final gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final applicationId = RegExp(r'applicationId\s*=\s*"([^"]+)"')
        .firstMatch(gradle)
        ?.group(1);

    expect(applicationId, isNotNull);
    expect(Uri.parse(oauthRedirect).scheme, applicationId);
  });

  test('the filter is browsable, or the browser cannot open it', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.intent.category.BROWSABLE'));
  });
}
