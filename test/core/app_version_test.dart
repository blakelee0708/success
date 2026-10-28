import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/app_version.dart';

void main() {
  test('the Dart copy is the one pubspec declares', () {
    // Two places that cannot see each other, and the way they break is quiet:
    // the APK builds, the parent's phone reports a version it is not running,
    // and the guardian is told their phone is up to date when it is three
    // builds behind. Same trap `application_id_test` covers for the Gradle
    // copy of the application id.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec
        .firstWhere((l) => l.startsWith('version:'))
        .split(':')
        .last
        .trim();

    expect(appVersion, declared);
  });

  test(
    'the build number is what is compared, and only when it is readable',
    () {
      expect(buildNumberOf('1.0.0+7'), 7);
      expect(buildNumberOf('1.2.3+41'), 41);
      // A version with no build number, or none at all, is a phone that said
      // nothing - never a phone that is out of date.
      expect(buildNumberOf('1.0.0'), isNull);
      expect(buildNumberOf(null), isNull);
      expect(buildNumberOf(''), isNull);
    },
  );
}
