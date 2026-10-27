import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/app_settings_screen.dart';

import '../../support/pump_app.dart';

/// 드래그 순서 변경 is in `04_SCREEN_SPEC`, and it worked — invisibly.
///
/// `ReorderableListView` on Android starts a drag on a **long press** and
/// draws nothing to say so. Long-press is the gesture this app's readers are
/// least likely to know, so an undiscoverable one is a missing feature; it
/// was reported as one from a real phone.
Future<void> _openAppSettings(WidgetTester tester) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        const SeniorSettings(
          screenMode: ScreenMode.detailed,
          apps: defaultDetailedApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('앱 설정하기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every button carries a grip you can see', (tester) async {
    await _openAppSettings(tester);

    for (final app in defaultDetailedApps.take(3)) {
      expect(
        find.byKey(AppSettingsKeys.dragHandle(app.id)),
        findsOneWidget,
        reason: '${app.label} has no way to say it can be dragged',
      );
    }
  });

  testWidgets('the grip starts the drag itself, with no hold', (tester) async {
    // A handle that still needs a long press is decoration. The guardian's
    // half had exactly that for months.
    await _openAppSettings(tester);

    final handle = find.byKey(
      AppSettingsKeys.dragHandle(defaultDetailedApps.first.id),
    );
    expect(
      tester.widget(handle),
      isA<ReorderableDragStartListener>(),
    );
  });

  testWidgets('it is a target an ageing hand can land on', (tester) async {
    await _openAppSettings(tester);

    final size = tester.getSize(
      find.byKey(AppSettingsKeys.dragHandle(defaultDetailedApps.first.id)),
    );
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
