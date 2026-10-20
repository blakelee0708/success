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

/// Throwaway: the splash's entrance, frame by frame, because the swing cannot
/// be judged from a still. Delete once the motion is settled.
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

  for (final tone in GuardianCardTone.values) {
    testWidgets('guardian card: ${tone.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('root'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: AppColors.seniorBackground,
              child: SplashScreen(cardTone: tone),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/hand_phone.png'),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pump(SplashScreen.entrance + const Duration(seconds: 1));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('root')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/card')..createSync(recursive: true);
        File('${dir.path}/${tone.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
