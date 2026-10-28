import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';
import 'package:app/features/manual/data/manual_topics.dart';
import 'package:app/features/manual/presentation/manual_card.dart';
import 'package:app/features/manual/presentation/manual_screen.dart';

import '../../support/pump_app.dart';

/// 사용법 — and the two gestures it is built to avoid.
///
/// Swiping sideways and scrolling down are the two things this app's readers
/// fail at most, so the list has to fit one screen **at every text size**,
/// including the largest - which is the size the reader who needs a manual is
/// most likely to be using.
Future<void> _openManual(
  WidgetTester tester, {
  FontSize size = FontSize.normal,
}) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: ScreenMode.easy,
          fontSize: size,
          apps: defaultEasyApps,
        ).toJson(),
      ),
    },
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('더 보기'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(SeniorSettingsScreen.manualRow));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // The app's own faces, for the same reason `screenshots_test` loads them:
    // measuring against whatever the harness falls back to measures a phone
    // nobody has.
    final korean = FontLoader(AppTheme.fontFamily);
    for (final asset in const [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      korean.addFont(rootBundle.load(asset));
    }
    await korean.load();
  });

  testWidgets('설정 leads to it, and every topic is a row', (tester) async {
    await _openManual(tester);

    expect(find.byKey(ManualScreen.listKey), findsOneWidget);
    for (final topic in manualTopics) {
      expect(
        find.byKey(ManualScreen.row(topic.key)),
        findsOneWidget,
        reason: topic.title,
      );
    }
  });

  for (final size in FontSize.values) {
    testWidgets('nothing scrolls at ${size.name}', (tester) async {
      // The whole shape of this screen. A manual that needs a scroll is a
      // manual that stops being read partway, and the reader is the one
      // person who cannot be told to scroll.
      await _openManual(tester, size: size);

      expect(
        find.byType(Scrollable).evaluate().where((e) {
          final s = e.widget as Scrollable;
          return s.axisDirection == AxisDirection.down ||
              s.axisDirection == AxisDirection.up;
        }),
        isEmpty,
        reason: 'the list has started scrolling at ${size.name}',
      );
      expect(tester.takeException(), isNull);
      for (final topic in manualTopics) {
        expect(
          find.byKey(ManualScreen.row(topic.key)),
          findsOneWidget,
          reason: '${topic.title} fell off the screen at ${size.name}',
        );
      }
    });
  }

  for (final size in FontSize.values) {
    testWidgets('a card fits without scrolling at ${size.name}', (
      tester,
    ) async {
      // The card is held to the same promise the list is. A drawing plus
      // eight lines at 제일 크게 is where this would break, and the reader
      // at that size is the one who most needs the card.
      await _openManual(tester, size: size);
      for (final topic in manualTopics) {
        await tester.tap(find.byKey(ManualScreen.row(topic.key)));
        await tester.pumpAndSettle();
        final body = find.descendant(
          of: find.byKey(ManualCardKeys.card),
          matching: find.byType(Scrollable),
        );
        for (final element in body.evaluate()) {
          final position =
              (element as StatefulElement).state as ScrollableState;
          expect(
            position.position.maxScrollExtent,
            0,
            reason:
                '${topic.title} overruns the card by '
                '${position.position.maxScrollExtent.toStringAsFixed(0)}px '
                'at ${size.name}',
          );
        }
        await tester.tap(find.byKey(ManualCardKeys.understood));
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('a card has one button, and it says 이해했어요', (tester) async {
    // A pair of buttons on a card that is only telling somebody something is
    // a question where there is none - and this app has already had to
    // rewrite two pairs that each read as the other one.
    await _openManual(tester);
    await tester.tap(find.byKey(ManualScreen.row('home')));
    await tester.pumpAndSettle();

    expect(find.byKey(ManualCardKeys.card), findsOneWidget);
    expect(find.text('이해했어요'), findsOneWidget);
    for (final absent in ['그만두기', '닫기', '취소', '아니요', '다음']) {
      expect(find.text(absent), findsNothing, reason: absent);
    }

    await tester.tap(find.byKey(ManualCardKeys.understood));
    await tester.pumpAndSettle();
    expect(find.byKey(ManualCardKeys.card), findsNothing);
    expect(find.byKey(ManualScreen.listKey), findsOneWidget);
  });

  testWidgets('every card draws the screen it is about', (tester) async {
    // Words alone make a senior hold a sentence in their head and match it
    // against a screen they have not looked at yet. Every topic carries a
    // depiction of the real thing with the presses numbered on it.
    await _openManual(tester);

    for (final topic in manualTopics) {
      await tester.tap(find.byKey(ManualScreen.row(topic.key)));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(ManualCardKeys.card),
          matching: find.byWidget(topic.drawing),
        ),
        findsOneWidget,
        reason: '${topic.title} has no drawing on screen',
      );
      await tester.tap(find.byKey(ManualCardKeys.understood));
      await tester.pumpAndSettle();
    }
  });

  test('every line is short enough to be a whole line', () {
    // Korean glyphs are about as wide as the type size. At 20px in this
    // card that is about sixteen; the consent cards document what a wrapped
    // line costs, where 지금 쓰시는 기능은 broke after 기능 and left 은
    // alone.
    for (final topic in manualTopics) {
      expect(topic.title.length, lessThanOrEqualTo(14), reason: topic.title);
      for (final line in topic.lines) {
        expect(line.length, lessThanOrEqualTo(16), reason: line);
      }
    }
  });

  test('it covers what a senior is actually stuck on', () {
    // Not a tour. 버튼을 누르면 앱이 열려요 is deliberately absent - nobody
    // is stuck on that - and so is 긴급 구조 요청, which is a red bar across
    // the bottom and its own explanation.
    final keys = manualTopics.map((t) => t.key).toSet();
    expect(keys, contains('home'));
    expect(keys, contains('font'));
    expect(keys, contains('rename'));
    expect(keys, contains('add'));
    expect(keys, contains('family'));
    expect(keys, contains('sound'));
    expect(keys, contains('support'));
  });
}
