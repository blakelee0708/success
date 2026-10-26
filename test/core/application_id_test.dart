import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/application/guardian_pairing_controller.dart';

/// The application id is in two places that cannot see each other, and a
/// mismatch fails in the quietest possible way.
///
/// Gradle's copy is what the APK is actually built with. The Dart copy is what
/// goes into the Play link a guardian texts their parent. If they drift, the
/// app installs fine, the guardian's message looks right, and the parent taps
/// through to a store page for an app that does not exist — on the one path
/// (`경로 A`) where nobody is standing next to them to work out what went
/// wrong.
///
/// Nothing else catches this. `flutter analyze` does not read Gradle,
/// `flutter test` does not build the APK, and the Kotlin is only ever compiled
/// in CI.
void main() {
  test('Dart and Gradle name the same application id', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final match = RegExp(
      r'^\s*applicationId\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(gradle);

    expect(match, isNotNull, reason: 'applicationId is gone from build.gradle.kts');
    expect(match!.group(1), applicationId);
  });

  test('the namespace matches it too, so the Kotlin package resolves', () {
    // `AndroidManifest.xml` names the activity as `.MainActivity`, relative to
    // the namespace. A namespace that disagrees with the Kotlin package
    // declaration does not fail here — it fails at install, on a phone.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final namespace = RegExp(
      r'^\s*namespace\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(gradle);

    expect(namespace?.group(1), applicationId);
    expect(
      File(
        'android/app/src/main/kotlin/${applicationId.replaceAll('.', '/')}'
        '/MainActivity.kt',
      ).existsSync(),
      isTrue,
      reason: 'MainActivity.kt is not in the directory its package names',
    );
  });

  test('it is not the Flutter template default', () {
    // Play refuses `com.example.*` outright, and the id cannot be changed
    // once a listing exists.
    expect(applicationId, isNot(startsWith('com.example')));
  });
}
