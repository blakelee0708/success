import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/application/senior_ring_controller.dart';
import 'package:app/features/care/data/emergency_sound.dart';
import 'package:app/features/care/presentation/senior_ring_layer.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// 소리 울리기, on the phone it rings.
///
/// The use it exists for is `엄마가 전화를 안 받아` — the phone is silent, or
/// in another room, or not heard. The job is to get the parent to pick it up,
/// not to announce anything to passers-by.
Future<FakeEmergencySound> _pumpHome(
  WidgetTester tester, {
  ScreenMode mode = ScreenMode.easy,
}) async {
  final sound = FakeEmergencySound();
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      emergencySoundProvider.overrideWithValue(sound),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: mode,
          apps: mode == ScreenMode.easy ? defaultEasyApps : defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  return sound;
}

Future<void> _ring(
  WidgetTester tester, {
  String from = '영희',
  String? message,
}) async {
  final context = tester.element(find.byType(Scaffold).first);
  ProviderScope.containerOf(context)
      .read(seniorRingControllerProvider.notifier)
      .ring(RingRequest(from: from, message: message));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a ring covers the home and names who is asking', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _ring(tester, message: '엄마, 전화 좀 줘.');

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    expect(find.textContaining('영희'), findsWidgets);
    expect(find.text('엄마, 전화 좀 줘.'), findsOneWidget);
  });

  testWidgets('tapping anywhere at all stops it', (tester) async {
    // The whole screen is the button. Somebody woken by a phone they did not
    // expect to make a noise should not have to find one.
    final sound = await _pumpHome(tester);
    await _ring(tester);
    expect(sound.isPlaying, isTrue);

    // A corner, where no text and no icon is drawn.
    await tester.tapAt(const Offset(30, 120));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('the tiles come back exactly as they were', (tester) async {
    final sound = await _pumpHome(tester);
    await _ring(tester);
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();

    expect(find.text('전화'), findsOneWidget);
    expect(sound.stops, 1);
  });

  testWidgets('it covers the detailed home too', (tester) async {
    await _pumpHome(tester, mode: ScreenMode.detailed);
    await _ring(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    // Nothing behind it is reachable — a tap lands on the layer, not a tile.
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
  });

  testWidgets('a guardian who wrote nothing still says something', (
    tester,
  ) async {
    // The line is not an extra sold on top of the noise. A phone that starts
    // screaming with no explanation is frightening, and an elderly person
    // cannot tell a message from a fault.
    await _pumpHome(tester);
    await _ring(tester);

    expect(find.text('전화 한 번만 주세요.'), findsOneWidget);
  });

  testWidgets('it stops by itself if nobody touches it', (tester) async {
    // The phone may be in a bag in another room, which is the case this
    // exists for. A sound with no end is a flat battery and a frightened
    // senior rather than a found phone.
    final sound = await _pumpHome(tester);
    await _ring(tester);

    await tester.pump(SeniorRingController.maxDuration);
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('a second ring replaces the first rather than stacking', (
    tester,
  ) async {
    final sound = await _pumpHome(tester);
    await _ring(tester, from: '영희');
    await _ring(tester, from: '철수', message: '엄마 어디세요?');

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    expect(find.textContaining('철수'), findsWidgets);
    expect(find.textContaining('영희'), findsNothing);

    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('nothing rings on its own', (tester) async {
    final sound = await _pumpHome(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.plays, 0);
  });
}
