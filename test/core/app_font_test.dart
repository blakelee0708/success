import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/theme/font_license.dart';

import '../support/pump_app.dart';

/// The app ships its own Korean face.
///
/// Declaring no family leaves every label to the phone's system font — 삼성One
/// on a Galaxy, Roboto elsewhere — so the app looks different on every handset
/// and matches the design on none of them. For a launcher whose whole promise
/// is legibility that is a bug, not a detail.
void main() {
  group('the bundled face', () {
    test('both themes ask for it', () {
      expect(AppTheme.senior.textTheme.bodyLarge?.fontFamily, 'Noto Sans KR');
      expect(AppTheme.guardian.textTheme.bodyLarge?.fontFamily, 'Noto Sans KR');
    });

    test('the faces pubspec declares are actually in the repository', () {
      // Fetched at build time they would be missing from a fresh clone and
      // from CI, which is where the APK is built.
      for (final style in ['Regular', 'Bold']) {
        expect(
          File('assets/fonts/NotoSansKR-$style.ttf').existsSync(),
          isTrue,
          reason:
              'assets/fonts/NotoSansKR-$style.ttf is missing — run '
              'tool/build_fonts.py',
        );
      }
    });

    test('pubspec declares a weight for each face', () {
      // Flutter picks between *files* by weight; it will not move a variable
      // font's `wght` axis on its own. A family declared as one file renders
      // every bold label at the axis default.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Noto Sans KR'));
      expect(pubspec, contains('assets/fonts/NotoSansKR-Regular.ttf'));
      expect(pubspec, contains('assets/fonts/NotoSansKR-Bold.ttf'));
      expect(pubspec, contains('weight: 700'));
    });
  });

  testWidgets('its licence ships with it', (tester) async {
    // The OFL requires it, and an unreadable asset here means the licence
    // page is empty in the APK rather than noisy in a test.
    registerFontLicense();
    final licences = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('Noto Sans KR'))
        .toList();

    expect(licences, isNotEmpty);
    expect(
      licences.first.paragraphs.map((p) => p.text).join('\n'),
      contains('SIL Open Font License'),
    );
  });

  testWidgets('a senior-facing label inherits it', (tester) async {
    // Asserted through a real screen rather than the theme object: a screen
    // that set its own family, or a Text built outside the theme, would pass
    // the check above and still draw in the system font.
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 700));

    final paragraph = tester.renderObject<RenderParagraph>(find.text('눌러보세요'));
    expect(paragraph.text.style?.fontFamily, 'Noto Sans KR');
  });
}
