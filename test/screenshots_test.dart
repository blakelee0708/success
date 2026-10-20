import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/clock.dart';
import 'package:app/core/supabase/supabase_config.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/features/family/presentation/family_link_screen.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/presentation/widgets/default_home_prompt.dart';
import 'package:app/features/launcher/presentation/widgets/home_strip.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
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
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/hand_phone.png'),
      context,
    ),
  );
  await tester.pump();
}

/// The SDK's icon glyphs, wherever this Flutter install keeps them.
///
/// `FLUTTER_ROOT` is set when the tests are run by the `flutter` tool; the
/// walk up from the running executable covers being run some other way.
File? _materialIcons() {
  const relative = 'bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf';
  final roots = <String>[?Platform.environment['FLUTTER_ROOT']];
  for (var dir = File(Platform.resolvedExecutable).parent;
      dir.path != dir.parent.path;
      dir = dir.parent) {
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

    expect(find.byKey(GuardianStartKeys.kakao), findsOneWidget);
    await _capture(tester, '03-guardian-start');
  });

  testWidgets('screen mode choice renders', (tester) async {
    await enterSeniorFlow(tester);

    expect(find.text('화면을 골라주세요'), findsOneWidget);
    await _capture(tester, '04-screen-mode-choice');
  });

  testWidgets('the guardian dashboard renders every tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await _capture(tester, '05-dashboard-home');

    for (final (tab, name) in [
      ('홈 화면', '06-dashboard-launcher'),
      ('돌봄', '07-dashboard-care'),
      ('가족', '08-dashboard-family'),
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      await _capture(tester, name);
    }
  });

  testWidgets('the guardian login form renders', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        supabaseConfigProvider.overrideWithValue(
          const SupabaseConfig(url: 'https://example.supabase.co', anonKey: 'k'),
        ),
        // Both repositories too: with the config claiming a project exists,
        // the real providers would reach for a Supabase singleton that was
        // never initialised.
        guardianAuthRepositoryProvider.overrideWithValue(
          InMemoryGuardianAuthRepository(),
        ),
        seniorLinkRepositoryProvider.overrideWithValue(
          InMemorySeniorLinkRepository(),
        ),
      ],
    );
    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianStartKeys.kakao));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianStartKeys.emailFallback));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
    await _capture(tester, '09-guardian-login');
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

  testWidgets('the home-app prompt fits both homes, including at 아주 크게', (
    tester,
  ) async {
    // 정말 쉬운 화면 does not scroll, so the prompt has to fit alongside the
    // grid rather than push it off — and it is shown at whatever text size the
    // senior already chose, which may be the largest one.
    for (final (mode, size, name) in [
      (ScreenMode.easy, FontSize.normal, '12-home-prompt-easy'),
      (ScreenMode.easy, FontSize.extraLarge, '13-home-prompt-easy-extra-large'),
      (ScreenMode.detailed, FontSize.extraLarge, '14-home-prompt-detailed'),
    ]) {
      await pumpApp(
        tester,
        overrides: [
          appLauncherProvider.overrideWithValue(
            FakeAppLauncher(defaultHome: false),
          ),
        ],
        prefs: {
          SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
            SeniorSettings(
              screenMode: mode,
              fontSize: size,
              apps: mode == ScreenMode.easy
                  ? defaultEasyApps
                  : defaultDetailedApps,
            ).toJson(),
          ),
        },
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DefaultHomePrompt.promptKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, name);
    }
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

    expect(find.byKey(HomeStrip.messageKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, '16-easy-home');
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
}
