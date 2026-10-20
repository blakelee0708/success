import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

/// Throwaway: renders the splash at several tilts so the angle can be chosen
/// by looking at it. Delete once an angle is settled.
void main() {
  setUpAll(() async {
    final korean = FontLoader(AppTheme.fontFamily);
    for (final a in const [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      korean.addFont(rootBundle.load(a));
    }
    await korean.load();
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer),
        ),
      )).load();
    }
  });

  for (final tilt in const [0.0, -12.0, -25.0, -45.0]) {
    testWidgets('splash at $tilt', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('root'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.senior,
            home: ColoredBox(
              color: AppColors.seniorBackground,
              child: SplashScreen(tiltDegrees: tilt),
            ),
          ),
        ),
      );
      // Asset images decode asynchronously; without this the first capture
      // in the file renders with no illustration at all.
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/hand_phone.png'),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('root')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/tilt')..createSync(recursive: true);
        File('${dir.path}/tilt${tilt.toInt().abs()}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
