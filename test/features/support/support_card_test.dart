import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/phone_dialer.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';
import 'package:app/features/support/presentation/support_card.dart';

import '../../support/pump_app.dart';

/// 문의하기 — the one thing on the senior's phone that works with no family.
///
/// Every other route out of 설정 assumes a child at the other end: 가족
/// 메시지 needs somebody to write to, 가족 연결 설정 somebody to connect, and
/// 긴급 연락's 보호자 tile stays disabled until a guardian leaves a number.
/// A senior who installed this alone, or whose child set it up and then could
/// not be reached, had no way to ask anybody anything about the screen their
/// phone now sits on.
class _RecordingDialer implements PhoneDialer {
  final dialled = <String>[];

  @override
  Future<void> openDialer(String number) async => dialled.add(number);
}

Future<void> _pumpSettings(
  WidgetTester tester,
  InMemorySeniorLinkRepository links, [
  PhoneDialer? dialer,
]) async {
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      phoneDialerProvider.overrideWithValue(dialer ?? _RecordingDialer()),
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
  await tester.scrollUntilVisible(
    find.byKey(SeniorSettingsScreen.supportRow),
    240,
  );
  await tester.tap(find.byKey(SeniorSettingsScreen.supportRow));
  await tester.pumpAndSettle();
}

Future<InMemorySeniorLinkRepository> _openSupport(WidgetTester tester) async {
  final links = InMemorySeniorLinkRepository();
  await _pumpSettings(tester, links);
  return links;
}

void main() {
  testWidgets('문의하기 shows the number to read out', (tester) async {
    await _openSupport(tester);

    expect(find.byKey(SupportCardKeys.card), findsOneWidget);
    expect(find.textContaining('고객센터'), findsWidgets);
    // Two groups of three, because that is how a person says a number out
    // loud and the whole job of this one is being said out loud.
    expect(find.text('482 913'), findsOneWidget);
  });

  testWidgets('a senior with no family can still reach it', (tester) async {
    // The case it exists for. Nothing is linked and nothing is connected, and
    // the card still has a number — the server creates the profile, exactly
    // as 번호 보여주기 does.
    final links = await _openSupport(tester);

    expect(links.rolesByProfile, isEmpty);
    expect(find.byKey(SupportCardKeys.code), findsOneWidget);
  });

  testWidgets('전화하기 follows the constant, and dials it', (tester) async {
    // A call button that dials nothing is worse than no call button: the
    // senior presses it, nothing happens, and they conclude the phone is
    // broken. Same rule 긴급 연락's 보호자 tile follows, so the button is
    // drawn from `supportPhoneNumber` rather than always.
    final dialer = _RecordingDialer();
    await _pumpSettings(tester, InMemorySeniorLinkRepository(), dialer);

    expect(
      find.byKey(SupportCardKeys.call),
      supportPhoneNumber.isEmpty ? findsNothing : findsOneWidget,
      reason: 'the button follows the constant, not the other way round',
    );
    if (supportPhoneNumber.isEmpty) return;

    await tester.tap(find.byKey(SupportCardKeys.call));
    await tester.pump();
    // Opens the dialer rather than placing the call, exactly as 119 does.
    expect(dialer.dialled, [supportPhoneNumber]);
  });

  testWidgets('a failure asks them to try again rather than naming a cause', (
    tester,
  ) async {
    // The last time this app guessed at a cause it blamed the senior's
    // internet for a missing sign-in, which sends somebody to check a router
    // over a bug in the app.
    final links = InMemorySeniorLinkRepository();
    links.offline = true;
    await _pumpSettings(tester, links);
    expect(find.textContaining('다시 눌러 주세요'), findsOneWidget);
    expect(find.textContaining('인터넷 연결'), findsNothing);
  });

  testWidgets('닫기 leaves the senior where they were', (tester) async {
    await _openSupport(tester);

    await tester.tap(find.byKey(SupportCardKeys.close));
    await tester.pumpAndSettle();

    expect(find.byKey(SupportCardKeys.card), findsNothing);
    expect(find.text('문의하기'), findsOneWidget);
  });
}
