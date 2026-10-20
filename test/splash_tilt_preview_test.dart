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

  testWidgets('the hand swings up', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(
        key: Key('root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ColoredBox(
            color: AppColors.seniorBackground,
            child: SplashScreen(),
          ),
        ),
      ),
    );
    // Asset images decode asynchronously; without this the first frames
    // render with no illustration at all.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/hand_phone.png'),
        tester.element(find.byType(MaterialApp)),
      ),
    );

    final dir = Directory('build/motion')..createSync(recursive: true);
    var elapsed = 0;
    for (final step in const [0, 110, 130, 150, 180, 280]) {
      if (step > 0) await tester.pump(Duration(milliseconds: step));
      elapsed += step;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('root')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.6);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/${elapsed.toString().padLeft(3, '0')}ms.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
