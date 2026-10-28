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

/// A point that is always scrim and never card: the card is centred with 22px
/// of horizontal padding, so anything left of that is behind it.
const _scrim = Offset(8, 300);

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

  testWidgets('tapping the scrim outside the card stops it', (tester) async {
    // The card carries buttons now, so it is no longer true that the whole
    // screen is one. What is still true is that a senior startled by a phone
    // they did not expect to make a noise should not have to find anything:
    // the scrim answers too, which is the safety net for whoever presses the
    // background in a hurry.
    final sound = await _pumpHome(tester);
    await _ring(tester);
    expect(sound.isPlaying, isTrue);

    await tester.tapAt(_scrim);
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('소리 끄기 stops it, for whoever does look', (tester) async {
    final sound = await _pumpHome(tester);
    await _ring(tester);

    await tester.tap(find.byKey(SeniorRingLayer.stopKey));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('a tap on the card itself does not stop it', (tester) async {
    // Otherwise the buttons race the scrim behind them: a press that misses
    // 전화하기 by two pixels would silence the phone instead, and the senior
    // would believe they had rung their child.
    final sound = await _pumpHome(tester);
    await _ring(tester, message: '엄마, 전화 좀 줘.');

    await tester.tap(find.text('엄마, 전화 좀 줘.'));
    await tester.pumpAndSettle();

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    expect(sound.isPlaying, isTrue);
  });

  testWidgets('the tiles come back exactly as they were', (tester) async {
    final sound = await _pumpHome(tester);
    await _ring(tester);
    await tester.tapAt(_scrim);
    await tester.pumpAndSettle();

    expect(find.text('전화'), findsOneWidget);
    expect(sound.stops, 1);
  });

  testWidgets('the home is still visible behind the card', (tester) async {
    // The same shape as the message popup, and for the same reason: a senior
    // who can see their own tiles knows the phone has not turned into
    // something else while they were not looking.
    await _pumpHome(tester);
    await _ring(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('it covers the detailed home too', (tester) async {
    await _pumpHome(tester, mode: ScreenMode.detailed);
    await _ring(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    await tester.tapAt(_scrim);
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

    await tester.tapAt(_scrim);
    await tester.pumpAndSettle();
    expect(sound.isPlaying, isFalse);
  });

  testWidgets('nothing rings on its own', (tester) async {
    final sound = await _pumpHome(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
    expect(sound.plays, 0);
  });
}
