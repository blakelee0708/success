import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/data/care_capabilities.dart';
import 'package:app/features/care/data/family_visibility.dart';
import 'package:app/features/care/presentation/family_visibility_screen.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

import '../../support/pump_app.dart';

/// 자녀가 보는 것.
///
/// The consent card asks once and goes away, so until this screen existed a
/// senior who wanted to know what their children could see had nowhere to
/// look. That is the gap Play's rules about collecting an adult's data are
/// aimed at, and separately a fair question from somebody whose home screen
/// this is.
///
/// It is drawn only once a child is attached - before that the question has
/// no subject - so this phone is a connected one.
Future<void> _pumpSettings(WidgetTester tester) async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  await store.ensureGuardianAccount(displayName: '영희');
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
        ),
      ),
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
  await tester.tap(find.text('바꾸기'));
  await tester.pumpAndSettle();
}

/// 설정 > 가족 연결 설정 > 자녀가 보는 것.
///
/// **It used to be a row in 설정 and is not any more.** 설정 had to fit one
/// screen without scrolling - the rule 사용법 has had from the start and this
/// one never did, with more than half the list below the fold - and this was
/// one of the three rows cut to get there. It belongs here anyway: what the
/// children can see is about the family, and the question has no subject
/// until there is one, which is why it sits under 연결되었어요.
Future<void> _openVisibility(WidgetTester tester) async {
  await _pumpSettings(tester);
  await tester.tap(find.text('가족 연결 설정'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(FamilyLinkKeys.visibility));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(FamilyLinkKeys.visibility));
  await tester.pumpAndSettle();
}

void main() {
  group('the list cannot drift from what 안심 케어 is', () {
    test('every paid capability is named on the screen', () {
      // The gap this screen exists to close, pointing the other way: a
      // capability added to the paid tier and not named here would leave the
      // senior agreeing to something they can never look up again.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      // Scoped to what the family learns *about the senior*. 가족 메시지
      // 무제한 and 홈 화면 정리 무제한 are paid and tell them nothing, so
      // they have no place on a screen answering 무엇을 보나요.
      for (final c in careCapabilities.where(
        (c) => c.stage == CareReadiness.live && c.aboutTheSenior,
      )) {
        expect(named, contains(c.key), reason: '${c.key} is sold and unlisted');
      }
    });

    test('every free capability is named too', () {
      // These would go to the family whatever the senior answers, which is
      // exactly why they would belong here and not on the consent card.
      // `free` is empty since the 2026-10-28 pricing decision; the rule
      // stays because the next capability added free is the one that would
      // slip through.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      for (final c in careCapabilities.where(
        (c) => c.stage == CareReadiness.free,
      )) {
        expect(named, contains(c.key), reason: '${c.key} runs and is unlisted');
      }
    });

    test('nothing unbuilt is promised here', () {
      // Same rule the consent card follows. A capability that is planned and
      // not built must not appear on a screen a senior reads as a statement
      // of what happens today.
      final named = familyVisibility
          .map((v) => v.capabilityKey)
          .whereType<String>()
          .toSet();
      for (final c in plannedCareCapabilities) {
        expect(named, isNot(contains(c.key)), reason: c.key);
      }
    });

    test('each line sits in the section its readiness puts it in', () {
      final byKey = {for (final c in careCapabilities) c.key: c};
      for (final item in familyVisibility) {
        final key = item.capabilityKey;
        if (key == null) continue;
        expect(byKey, contains(key), reason: '$key is not a capability');
        expect(
          byKey[key]!.stage,
          readinessFor(item.sees),
          reason: '$key is in the wrong section',
        );
      }
    });

    test('every key names a capability that exists', () {
      final keys = careCapabilities.map((c) => c.key).toSet();
      for (final item in familyVisibility) {
        if (item.capabilityKey == null) continue;
        expect(keys, contains(item.capabilityKey), reason: item.line);
      }
    });
  });

  group('what the screen says', () {
    test('the paid section says what the free week shows', () {
      // 안심 케어를 허락하시면 over the readings was false for the first seven
      // days after the connection, which show them without 안심 케어.
      expect(familySeesNote(FamilySees.withCare), contains('1주일'));
      expect(familySeesNote(FamilySees.always), isNull);
    });

    test('both sections have something in them', () {
      for (final sees in FamilySees.values) {
        expect(familySees(sees), isNotEmpty, reason: '$sees');
      }
    });

    test('nothing on it is a list of what is not collected', () {
      // 보지 못합니다 came off on the owner's call. Its five lines were true
      // and every one is a decision recorded elsewhere in this repository,
      // but a list of things that are **not** happening plants worries in a
      // reader who did not arrive with them - and this reader is on their own
      // phone, not reading a policy. `site/privacy.html` is the page that
      // owes the complete answer, and `privacy_policy_test` holds it to that.
      final said = familyVisibility.map((v) => v.line).join();
      for (final absent in ['어디 계신지', '통화 기록', '연락처', '사진첩']) {
        expect(said, isNot(contains(absent)), reason: absent);
      }
    });

    test('every line fits one line of the list', () {
      // Korean glyphs are about as wide as the type size. At 20px in the
      // width this list runs at, a long line wraps and leaves a syllable
      // alone - the fault the consent cards exist to document.
      for (final item in familyVisibility) {
        expect(item.line.length, lessThanOrEqualTo(22), reason: item.line);
      }
    });
  });

  testWidgets('the route still opens it', (tester) async {
    await _openVisibility(tester);

    expect(find.byKey(FamilyVisibilityScreen.listKey), findsOneWidget);
  });

  testWidgets('the screen draws every line and every heading', (tester) async {
    await _openVisibility(tester);

    for (final sees in FamilySees.values) {
      expect(find.text(familySeesTitle(sees)), findsOneWidget, reason: '$sees');
    }
    for (final item in familyVisibility) {
      expect(find.text(item.line), findsOneWidget, reason: item.line);
    }
  });

  testWidgets('there is nothing on it to press', (tester) async {
    // It is not a second consent screen. The card asks *may we turn this on*;
    // this answers *what do they see*, and a button here would make a senior
    // think an answer was wanted.
    await _openVisibility(tester);

    final inList = find.descendant(
      of: find.byKey(FamilyVisibilityScreen.listKey),
      matching: find.byType(ButtonStyleButton),
    );
    expect(inList, findsNothing);
  });

  testWidgets('첫 화면으로 가기 leaves it, like every other senior screen', (
    tester,
  ) async {
    await _openVisibility(tester);

    await tester.tap(find.text('첫 화면으로 가기'));
    await tester.pumpAndSettle();

    expect(find.byKey(FamilyVisibilityScreen.listKey), findsNothing);
  });
}
