import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/core/clock.dart';
import 'package:app/core/supabase/supabase_config.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/device_status.dart';
import 'package:app/domain/senior_device.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/care/presentation/care_consent_prompt.dart';
import 'package:app/features/launcher/presentation/app_settings_screen.dart';
import 'package:app/features/launcher/presentation/senior_settings_screen.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';
import 'package:app/features/launcher/presentation/widgets/home_utility_row.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
import 'package:app/features/guardian/presentation/widgets/signup_consent_sheet.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import 'support/pump_app.dart';

/// Renders each screen to `build/screenshots/` while checking it still draws.
///
/// This app's value is how it looks on a phone, and the remote environment has
/// no display, so these PNGs are how layout gets reviewed.
///
/// Two things the default test environment does not give us:
///
/// * Bundled fonts are not registered — the stub font it uses instead has no
///   Korean glyphs, so every label would rasterise as tofu. `setUpAll` loads
///   the app's own faces out of the asset bundle, so the PNGs are drawn in the
///   face the phone will use rather than an approximation of it.
/// * `toImage` completes on a real engine callback that the fake clock never
///   delivers, so it has to run inside [WidgetTester.runAsync] — awaiting it
///   directly hangs the run instead of failing.
Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(appRootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// Asset images resolve asynchronously; without this the frame is captured
/// before the illustration has decoded and the screen looks empty.
Future<void> _loadImages(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final asset in const [
      'assets/images/hand_phone.png',
      'assets/intro/senior_home.png',
      'assets/intro/guardian_launcher.png',
      'assets/intro/guardian_home.png',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump();
}

/// The SDK's icon glyphs, wherever this Flutter install keeps them.
///
/// `FLUTTER_ROOT` is set when the tests are run by the `flutter` tool; the
/// walk up from the running executable covers being run some other way.
File? _materialIcons() {
  const relative =
      'bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf';
  final roots = <String>[?Platform.environment['FLUTTER_ROOT']];
  for (
    var dir = File(Platform.resolvedExecutable).parent;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    roots.add(dir.path);
  }
  for (final root in roots) {
    final file = File('$root/$relative');
    if (file.existsSync()) return file;
  }
  return null;
}

void main() {
  setUpAll(() async {
    // The app's own family, both weights, straight out of the asset bundle —
    // so a label the theme failed to reach shows up here as tofu instead of
    // being quietly papered over by a fallback registration.
    final korean = FontLoader(AppTheme.fontFamily);
    for (final asset in const [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      korean.addFont(rootBundle.load(asset));
    }
    await korean.load();

    // Icons are tofu without this; the glyphs ship with the SDK rather than
    // the project, so the path is resolved from the running Flutter install.
    //
    // Searched for rather than computed: the executable running this is
    // `flutter_tester`, which sits three directories deeper in the cache than
    // `dart` does, and a fixed number of `.parent`s silently misses it — which
    // is why every icon in these PNGs used to be a square.
    final icons = _materialIcons();
    if (icons != null) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer),
          ),
        );
      await loader.load();
    }
  });

  testWidgets('splash renders at rest', (tester) async {
    await pumpApp(tester);
    await _loadImages(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('눌러보세요'), findsOneWidget);
    await _capture(tester, '01-splash-idle');
  });

  testWidgets('splash renders while entering', (tester) async {
    await pumpApp(tester);
    await _loadImages(tester);
    await settleSplashEntrance(tester);
    await tester.tap(find.byKey(SplashScreen.tapTargetKey));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('준비하고 있어요\n잠시만 기다려 주세요'), findsOneWidget);
    await _capture(tester, '02-splash-entering');

    await settleAfterSplashTap(tester);
  });

  testWidgets('guardian start renders', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();
    await _loadImages(tester);

    // The three intro pages, then the one with the buttons.
    await _capture(tester, '03-guardian-intro-1');
    await tester.tap(find.byKey(GuardianStartKeys.next));
    await tester.pumpAndSettle();
    await _capture(tester, '03-guardian-intro-2');
    await tester.tap(find.byKey(GuardianStartKeys.next));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianStartKeys.kakao), findsOneWidget);
    await _capture(tester, '03-guardian-start');

    // 약관 동의, which every way in now raises before an account can exist.
    // The line it replaced said 시작하면 ... 동의하게 됩니다 as plain text,
    // with no link, naming a 이용약관 that did not exist.
    await tester.tap(find.byKey(GuardianStartKeys.email));
    await tester.pumpAndSettle();
    expect(find.byKey(SignupConsentSheet.sheetKey), findsOneWidget);
    await _capture(tester, '32-signup-consent');
  });

  testWidgets('screen mode choice renders', (tester) async {
    await enterSeniorFlow(tester);

    expect(find.text('화면을 골라주세요'), findsOneWidget);
    await _capture(tester, '04-screen-mode-choice');
  });

  testWidgets('the guardian home with a parent actually linked', (
    tester,
  ) async {
    // The tab above it is the empty state: no project, so no parent. The
    // screen a guardian sees every day — the hero, the four actions — had no
    // picture at all until this.
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(
        const GuardianSession(userId: 'u1', email: 'g@example.com'),
      );
    addTearDown(auth.dispose);

    final links = InMemorySeniorLinkRepository();
    await links.ensureGuardianAccount(displayName: '영희');
    final profile = await links.createSeniorProfile(displayName: '어머니');
    await links.updateProfileSettings(
      profile.id,
      screenMode: ScreenMode.easy,
      fontSize: FontSize.extraLarge,
    );
    links.activeDeviceByProfile[profile.id] = SeniorDevice(
      id: 'device-1',
      installId: 'install-1',
      isActive: true,
      deviceLabel: '갤럭시 A54',
      lastSeenAt: DateTime(2026, 10, 20, 14, 30),
      status: DeviceStatus(
        readAt: DateTime(2026, 10, 20, 14, 30),
        batteryPercent: 61,
        isCharging: false,
        ringer: RingerMode.vibrate,
      ),
    );

    final homeApps = InMemoryHomeAppsRepository();
    await homeApps.replace(profile.id, defaultDetailedApps);

    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 15, 10)),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianHomeKeys.hero), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, '18-dashboard-home-linked');

    // The tab the 홈 버튼 정리하기 card opens, under the same conditions. Only
    // the home tab was rebuilt, so this is where the new ground and the old
    // contents meet, and it is the kind of seam only a render shows.
    await tester.tap(find.byKey(GuardianNavKeys.destination('부모님 화면')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, '19-dashboard-launcher-linked');

    // The same card for a phone nobody has touched in three days. This is the
    // state it used to get wrong in silence: `last_seen_at` was written once,
    // at registration, and read in the present tense — so this render was a
    // green dot over 폰은 잘 켜져 있어요. It is the one worth looking at.
    //
    // Pumped again rather than switched to: the device is read through a
    // provider that has already resolved, so changing the row underneath it
    // leaves the screen showing what it read the first time.
    links.activeDeviceByProfile[profile.id] = SeniorDevice(
      id: 'device-1',
      installId: 'install-1',
      isActive: true,
      deviceLabel: '갤럭시 A54',
      lastSeenAt: DateTime(2026, 10, 17, 9, 0),
      // The reading is three days old too, and the card has to say so rather
      // than drawing 12% as though it were this morning's.
      status: DeviceStatus(
        readAt: DateTime(2026, 10, 17, 9, 0),
        batteryPercent: 12,
        isCharging: false,
        ringer: RingerMode.silent,
      ),
    );
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 15, 10)),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('3일째'), findsOneWidget);
    await _capture(tester, '18b-dashboard-home-quiet');

    // The facts card sits below the fold on a phone, and it is the half of
    // this change worth looking at: the numbers are real now, and the row
    // under them says how old they are.
    await tester.drag(find.text('무엇을 해 드릴까요'), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('3일 전'), findsOneWidget);
    await _capture(tester, '18c-dashboard-status-quiet');

    // The two states the 2026-10-28 pricing line created, and the pair worth
    // looking at together: the same card inside the free week and after it.
    // Withheld it must not fall back to 연결되기 전이에요 - that would be the
    // card telling a guardian their parent never set the phone up.
    links.trialEndsAt = DateTime(2026, 10, 23, 9, 0);
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 15, 10)),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('무료 기간이'), findsOneWidget);
    await _capture(tester, '30-dashboard-trial-running');

    links.readingsVisible = false;
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 25, 15, 10)),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        homeAppsRepositoryProvider.overrideWithValue(homeApps),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('안심 케어로 볼 수 있어요'), findsOneWidget);
    expect(find.textContaining('연결되기 전'), findsNothing);
    await _capture(tester, '31-dashboard-readings-locked');
  });

  testWidgets('the guardian dashboard renders every tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();
    await skipGuardianIntro(tester);
    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
    await _capture(tester, '05-dashboard-home');

    // Four destinations now: 가족 was a fifth and what it held moved onto 홈
    // and the bottom of 안심 케어. By key rather than by text, because
    // 안심 케어 is the tab's own heading as well as its label.
    for (final (tab, name) in [
      ('부모님 화면', '06-dashboard-launcher'),
      ('메시지', '07-dashboard-messages'),
      ('안심 케어', '08-dashboard-care'),
    ]) {
      await tester.tap(find.byKey(GuardianNavKeys.destination(tab)));
      await tester.pumpAndSettle();
      await _capture(tester, name);
    }
  });

  testWidgets('the guardian login form renders', (tester) async {
    final auth = InMemoryGuardianAuthRepository(confirmationRequired: false);
    await pumpApp(
      tester,
      overrides: [
        supabaseConfigProvider.overrideWithValue(
          const SupabaseConfig(
            url: 'https://example.supabase.co',
            anonKey: 'k',
          ),
        ),
        // Both repositories too: with the config claiming a project exists,
        // the real providers would reach for a Supabase singleton that was
        // never initialised.
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(
          InMemorySeniorLinkRepository(),
        ),
      ],
    );
    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();
    await skipGuardianIntro(tester);
    // 이메일로 시작하기, the third button, which goes straight to the form.
    // The Kakao sheet's email button is not a route any more: a provider
    // that answers raises no sheet for it to sit in.
    await tester.tap(find.byKey(GuardianStartKeys.email));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
    await _capture(tester, '09-guardian-login');

    // 새로 가입하기, and the card that says it is happening.
    await tester.tap(find.byKey(GuardianLoginKeys.toggleMode));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(GuardianLoginKeys.email), 'me@ex.com');
    await tester.enterText(find.byKey(GuardianLoginKeys.password), 'hunter2');
    await tester.pumpAndSettle();
    await _capture(tester, '09b-guardian-signup');
    final pending = Completer<void>();
    auth.beforeSignUp = () => pending.future;
    await tester.tap(find.byKey(GuardianLoginKeys.submit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, '09c-guardian-signing-up');
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, '09d-guardian-signed-up');
    await tester.pump(GuardianLoginScreen.doneHold);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('가족 연결 renders, including at 아주 크게', (tester) async {
    // Raising the text size is the point of this app, so a screen that only
    // fits at the default size is a bug. Both sizes are captured so the
    // large one can actually be looked at.
    for (final (size, name) in [
      (FontSize.normal, '10-family-link'),
      (FontSize.extraLarge, '11-family-link-extra-large'),
    ]) {
      await pumpApp(
        tester,
        overrides: [
          seniorLinkRepositoryProvider.overrideWithValue(
            InMemorySeniorLinkRepository(),
          ),
          seniorLinkStoreProvider.overrideWithValue(InMemorySeniorLinkStore()),
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
      await tester.tap(find.text('가족 연결'));
      await tester.pumpAndSettle();

      expect(find.byKey(FamilyLinkKeys.submit), findsOneWidget);
      // Nothing may overflow: an overflow paints a stripe and the layout the
      // PNG is meant to prove is no longer the layout being reviewed.
      expect(tester.takeException(), isNull);
      await _capture(tester, name);
    }
  });

  testWidgets('설정, where the home-app offer lives now', (tester) async {
    // It used to sit on the home screen, and these captures were of that.
    // Onboarding asks the question now; this is the way back for anyone who
    // said 나중에, reached through 더 보기 on 정말 쉬운 화면.
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: false),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            apps: defaultEasyApps,
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();
    await _capture(tester, '12-easy-home-no-card');

    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(find.byKey(SeniorSettingsScreen.homeAppRow), findsOneWidget);
    await _capture(tester, '13-senior-settings');

    // No capture of a 첫 화면으로 정하기 screen, because there is no longer
    // one: the row opens the phone's own chooser.
  });

  testWidgets('정말 쉬운 화면 at rest, which is how it is actually used', (
    tester,
  ) async {
    // Every other capture of this screen has the 첫 화면 card on it, which is
    // the one state the band is squeezed in. The screen a senior looks at
    // every day had no picture at all until this.
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    final messages = InMemoryMessageRepository(store, subscriptions: subs);
    await store.ensureGuardianAccount(displayName: '영희');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    await messages.send(profile.id, body: '엄마, 점심 드셨어요?');

    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(pairing),
        subscriptionRepositoryProvider.overrideWithValue(subs),
        messageRepositoryProvider.overrideWithValue(messages),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
          ),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            apps: defaultEasyApps,
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();

    // The band is a clock now. What used to be checked here - that it
    // carried the family's newest message - moved to the 가족 button, which
    // is where `04_SCREEN_SPEC` put it before the band took it over.
    expect(find.byType(HomeStrip), findsOneWidget);
    expect(find.byKey(HomeUtilityRow.soundKey), findsOneWidget);
    expect(find.byKey(HomeUtilityRow.internetKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, '16-easy-home');
  });

  testWidgets('a message from the family, over the home', (tester) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    final messages = InMemoryMessageRepository(store, subscriptions: subs);
    await store.ensureGuardianAccount(displayName: '영희');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    await messages.send(profile.id, body: '엄마, 점심 드셨어요? 이따 저녁에 들를게요.');
    messages.readingAsSenior = true;

    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        seniorLinkRepositoryProvider.overrideWithValue(store),
        messageRepositoryProvider.overrideWithValue(messages),
        pairingRepositoryProvider.overrideWithValue(pairing),
        subscriptionRepositoryProvider.overrideWithValue(subs),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
          ),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            apps: defaultEasyApps,
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(FamilyMessagePrompt), findsOneWidget);
    await _capture(tester, '19-family-message-over-home');
  });

  testWidgets('자세한 화면 at rest, for comparison with the easy one', (
    tester,
  ) async {
    // The other half of the choice a senior makes on their first run, and it
    // had no picture either. Its tiles are the same [AppTile] the easy screen
    // draws, but everything around them — the add-slots, the bottom tabs, the
    // 설정 list — is still stock Material from before the clay review, and
    // that only shows up in a render.
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
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

    expect(tester.takeException(), isNull);
    await _capture(tester, '17-detailed-home');
  });

  testWidgets('the card that sits on the senior\'s home', (tester) async {
    // 안심 케어 동의, answered on the parent's own phone over the tiles.
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    await store.ensureGuardianAccount(displayName: '김보호');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );

    Future<void> pumpSeniorHome() async {
      await pumpApp(
        tester,
        overrides: [
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
          appLauncherProvider.overrideWithValue(
            FakeAppLauncher(defaultHome: true),
          ),
          seniorLinkRepositoryProvider.overrideWithValue(store),
          pairingRepositoryProvider.overrideWithValue(pairing),
          subscriptionRepositoryProvider.overrideWithValue(subs),
          homeAppsRepositoryProvider.overrideWithValue(
            InMemoryHomeAppsRepository(),
          ),
          seniorLinkStoreProvider.overrideWithValue(
            InMemorySeniorLinkStore(
              SeniorLink(
                installId: 'senior-phone',
                seniorProfileId: profile.id,
              ),
            ),
          ),
        ],
        prefs: {
          SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
            const SeniorSettings(
              screenMode: ScreenMode.easy,
              apps: defaultEasyApps,
            ).toJson(),
          ),
        },
      );
      await tester.pumpAndSettle();
    }

    await subs.startCare(profile.id);
    await pumpSeniorHome();
    expect(find.byKey(CareConsentPrompt.promptKey), findsOneWidget);
    await _capture(tester, '24-care-consent-card');
  });

  testWidgets('the senior screens that are still on the old design', (
    tester,
  ) async {
    // SOS, 설정 and the two screens under it. None of them had a picture, and
    // they are what is left of the pre-2026-10-20 look on the senior's half.
    Future<void> openDetailedHome() async {
      await pumpApp(
        tester,
        overrides: [
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
          appLauncherProvider.overrideWithValue(
            FakeAppLauncher(defaultHome: true),
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
    }

    await openDetailedHome();
    await tester.tap(find.text('긴급 구조 요청'));
    await tester.pumpAndSettle();
    expect(find.text('긴급 연락'), findsOneWidget);
    await _capture(tester, '20-sos');

    // The same screen once a family is connected. 보호자 was `onTap: null`
    // under a caption promising it would work after connecting, and
    // connecting did not enable it — the number lived in a table the parent's
    // phone had no policy to read. This render is the difference.
    final links = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(links);
    await links.ensureGuardianAccount(
      displayName: '영희',
      phoneNumber: '01012345678',
    );
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final linked = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
        ),
        seniorLinkRepositoryProvider.overrideWithValue(links),
        pairingRepositoryProvider.overrideWithValue(pairing),
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: linked.id),
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
    await tester.tap(find.text('긴급 구조 요청'));
    await tester.pumpAndSettle();
    expect(find.text('영희'), findsOneWidget);
    await _capture(tester, '20b-sos-connected');

    await openDetailedHome();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    expect(find.text('글씨 크기 조절하기'), findsOneWidget);
    await _capture(tester, '21-senior-settings');

    // The same screen on a phone this app *is* the home screen of, which is
    // the phone almost every senior is holding. 첫 화면으로 정하기 is gone
    // because it is done, and 잘보이네 사용하지 않기 is pressable because
    // there is now something to undo.
    await pumpApp(
      tester,
      overrides: [
        nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
        appLauncherProvider.overrideWithValue(
          FakeAppLauncher(defaultHome: true),
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
    expect(find.text('잘보이네 사용하지 않기'), findsOneWidget);
    await _capture(tester, '21b-senior-settings-home');

    await tester.tap(find.byKey(SeniorSettingsScreen.stopUsingRow));
    await tester.pumpAndSettle();
    await _capture(tester, '21c-stop-using');
    // The question card asks one thing; the walkthrough of the phone's own
    // chooser is a second card after 네, and it is the one with text in it
    // worth looking at.
    await tester.tap(find.text('네'));
    await tester.pumpAndSettle();
    await _capture(tester, '21d-stop-using-how');
    // `아니요`, because `그만두기` is the row that opened this and read as the
    // confirm — see the note on that dialog.
    await tester.tap(find.text('아니요'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();
    await _capture(tester, '22-app-settings');

    // Below the fold since the rows became two lines each - the three
    // unlabelled symbols are the words 이름, 색깔 and 지우기 now.
    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.add));
    await _capture(tester, '22b-add-button-kind');
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('글씨 크기 조절하기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, '23-font-size');
  });

  testWidgets('가족 메시지 renders for the guardian', (tester) async {
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    final messages = InMemoryMessageRepository(store, subscriptions: subs);
    await store.ensureGuardianAccount(displayName: '김보호');
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    await messages.send(profile.id, body: '엄마, 점심 드셨어요?');
    messages.sendingAsSenior = true;
    await messages.send(profile.id, body: '방금 먹었다. 너는?');
    messages.sendingAsSenior = false;
    await messages.send(profile.id, body: '저도 먹었어요. 오늘 안 추우세요?');

    final shared = [
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      subscriptionRepositoryProvider.overrideWithValue(subs),
      messageRepositoryProvider.overrideWithValue(messages),
    ];

    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        ...shared,
        guardianAuthRepositoryProvider.overrideWithValue(auth),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('메시지'));
    await tester.pumpAndSettle();
    expect(find.byKey(ConversationKeys.field), findsOneWidget);
    await _capture(tester, '15-guardian-messages');

    // The senior's end is covered by test/features/messages; capturing it here
    // needs a second pumpApp in the same test and that does not settle.
  });
  testWidgets('안심 케어가 켜진 두 화면', (tester) async {
    // Both halves with the tier bought and agreed to. 소리 울리기 used to be
    // what these two pictures were for; it is out of the product, and what is
    // worth seeing now is that neither screen offers it.
    final store = InMemorySeniorLinkRepository();
    final pairing = InMemoryPairingRepository(store);
    final subs = InMemorySubscriptionRepository(store);
    await store.ensureGuardianAccount(
      displayName: '영희',
      phoneNumber: '01012345678',
    );
    final started = await pairing.startSeniorPairing(installId: 'senior-phone');
    final profile = await pairing.claimSeniorPairingCode(
      code: started.code,
      displayName: '어머니',
    );
    await subs.startCare(profile.id);
    await subs.resolveCareConsent(profile.id, true);

    final shared = <Object>[
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 20, 14, 30)),
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkRepositoryProvider.overrideWithValue(store),
      pairingRepositoryProvider.overrideWithValue(pairing),
      subscriptionRepositoryProvider.overrideWithValue(subs),
      homeAppsRepositoryProvider.overrideWithValue(
        InMemoryHomeAppsRepository(),
      ),
    ];

    // The parent's phone.
    await pumpApp(
      tester,
      overrides: [
        ...shared,
        seniorLinkStoreProvider.overrideWithValue(
          InMemorySeniorLinkStore(
            SeniorLink(installId: 'senior-phone', seniorProfileId: profile.id),
          ),
        ),
      ],
      prefs: {
        SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
          const SeniorSettings(
            screenMode: ScreenMode.easy,
            apps: defaultEasyApps,
          ).toJson(),
        ),
      },
    );
    await tester.pumpAndSettle();
    await _capture(tester, '26-care-on-home');

    // The child's phone with the tier bought. 소리 울리기 used to take the
    // fourth card's slot here and is out of the product.
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        ...shared,
        guardianAuthRepositoryProvider.overrideWithValue(auth),
      ],
    );
    await tester.pumpAndSettle();
    await _capture(tester, '27-dashboard-home-care-on');
  });

  testWidgets('33 the guardian with no parent yet', (tester) async {
    final store = InMemorySeniorLinkRepository();
    await store.ensureGuardianAccount(displayName: '영희');
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(
          InMemoryPairingRepository(store),
        ),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.promise), findsOneWidget);
    await _capture(tester, '33-guardian-no-parent');

    // 연결 번호 만들기 opens the fields and 발송하기 under them.
    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.tap(find.byKey(GuardianFamilyKeys.openInviteForm));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(GuardianFamilyKeys.nameField)),
      alignment: 0.15,
    );
    await tester.pumpAndSettle();
    await _capture(tester, '33b-guardian-invite-form');
  });

  testWidgets('34 the install number, waiting to be used', (tester) async {
    final store = InMemorySeniorLinkRepository()..pendingLinkConsent = true;
    await store.ensureGuardianAccount(displayName: '영희');
    final pairing = InMemoryPairingRepository(store);
    await pairing.createSeniorInvite(displayName: '엄마');
    final auth = InMemoryGuardianAuthRepository()
      ..seedSignedIn(const GuardianSession(userId: 'u1'));
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [
        seniorLinkRepositoryProvider.overrideWithValue(store),
        pairingRepositoryProvider.overrideWithValue(pairing),
        guardianAuthRepositoryProvider.overrideWithValue(auth),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.waitingForConsent), findsOneWidget);
    await _capture(tester, '34-guardian-invite-waiting');
  });
}
