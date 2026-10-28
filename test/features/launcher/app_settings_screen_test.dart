import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/app_settings_screen.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';

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

  testWidgets('there is a way out that is a word, not a corner arrow', (
    tester,
  ) async {
    // The ← is small, in the hardest corner to reach, and a symbol. It was
    // the only way off this screen, and a senior who came here to rename one
    // button had to find it.
    await _openAppSettings(tester);

    expect(find.byKey(AppSettingsKeys.done), findsOneWidget);
    expect(find.text('첫 화면으로 가기'), findsOneWidget);
  });

  testWidgets('it goes all the way home, not back one screen', (tester) async {
    // Two ways reach this screen now — 설정, and the hollow slot on the home
    // screen. Popping would leave half the visitors standing in 설정 with
    // another exit to find, and would make the label untrue.
    await _openAppSettings(tester);

    await tester.tap(find.byKey(AppSettingsKeys.done));
    await tester.pumpAndSettle();

    expect(find.text('글씨 크기 조절하기'), findsNothing);
    expect(find.text('전화'), findsWidgets);
  });

  testWidgets('it does not claim to be what saves the change', (tester) async {
    // Everything here is written the moment it is pressed. A button that
    // said 저장 would make the ← arrow the one that loses their work — which
    // is false, and would teach them to fear the corner.
    await _openAppSettings(tester);

    expect(find.text('바꾸시면 바로 바뀌어요'), findsOneWidget);
    for (final claim in ['저장', '완료']) {
      expect(find.textContaining(claim), findsNothing, reason: '$claim is a promise this screen does not need to make');
    }
  });

  testWidgets('버튼 추가하기 sits in the list, under the last button', (
    tester,
  ) async {
    // Pinned to the bottom it left a field of nothing between the last row
    // and the button, and said nothing about where a new one would land.
    // The guardian's half already learnt this.
    await _openAppSettings(tester);
    // The rows are two lines each since the symbols became words, so both of
    // these are below the fold on a phone.
    await tester.scrollUntilVisible(find.byKey(AppSettingsKeys.add), 200);
    // Back up far enough that the last app row is laid out too. A row a list
    // has scrolled past is disposed, not merely off-screen, so there is
    // nothing to measure.
    await tester.drag(find.byType(ReorderableListView), const Offset(0, 150));
    await tester.pumpAndSettle();

    // By key rather than by the label: the list is long enough now that the
    // row's own text may be scrolled past while the row is still laid out.
    final lastRow = tester
        .getBottomLeft(find.byKey(AppSettingsKeys.rename('gallery')))
        .dy;
    final add = tester.getTopLeft(find.byKey(AppSettingsKeys.add)).dy;
    final out = tester.getTopLeft(find.byKey(AppSettingsKeys.done)).dy;

    expect(add, greaterThan(lastRow));
    expect(add, lessThan(out));
  });

  testWidgets('and adding one asks the question straight away', (tester) async {
    await _openAppSettings(tester);

    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.add));

    expect(find.byKey(CategoryPickerKeys.sheet), findsOneWidget);
  });
}
