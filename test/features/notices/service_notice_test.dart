import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/announcement_repository.dart';
import 'package:app/data/remote/app_config_repository.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/message_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';
import 'package:app/features/notices/presentation/guardian_service_notices.dart';
import 'package:app/features/notices/presentation/senior_service_notice.dart';

import '../../support/pump_app.dart';

/// 공지, written on the server so it reaches phones that will never be
/// updated. A launcher is the app Play will not update, so this had to be in
/// the first build or never reach the phones that need it most.
const _maintenance = Announcement(
  id: 'n1',
  title: '11월 3일 새벽 점검 안내',
  body: '11월 3일 새벽 2시부터 30분 동안 메시지가 잠시 안 돼요.',
);

typedef Senior = ({
  InMemorySeniorLinkRepository store,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Senior> _seniorFamily({String? say}) async {
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
  if (say != null) await messages.send(profile.id, body: say);
  return (store: store, messages: messages, profileId: profile.id);
}

Future<void> _pumpSeniorHome(
  WidgetTester tester,
  Senior h, {
  List<Announcement> notices = const [_maintenance],
  FontSize fontSize = FontSize.normal,
  Map<String, Object> extraPrefs = const {},
}) async {
  h.messages.sendingAsSenior = true;
  h.messages.readingAsSenior = true;
  await pumpApp(
    tester,
    overrides: [
      seniorLinkRepositoryProvider.overrideWithValue(h.store),
      messageRepositoryProvider.overrideWithValue(h.messages),
      announcementRepositoryProvider.overrideWithValue(
        InMemoryAnnouncementRepository(forSenior: notices),
      ),
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: h.profileId),
        ),
      ),
    ],
    prefs: {
      SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode(
        SeniorSettings(
          screenMode: ScreenMode.easy,
          apps: defaultEasyApps,
          fontSize: fontSize,
        ).toJson(),
      ),
      ...extraPrefs,
    },
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpGuardianHome(
  WidgetTester tester, {
  List<Announcement> notices = const [],
  int? latestBuild,
  Map<String, Object> prefs = const {},
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);
  final links = InMemorySeniorLinkRepository();
  await links.ensureGuardianAccount(displayName: '영희');
  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      announcementRepositoryProvider.overrideWithValue(
        InMemoryAnnouncementRepository(forGuardian: notices),
      ),
      appConfigRepositoryProvider.overrideWithValue(
        InMemoryAppConfigRepository(AppConfig(latestBuild: latestBuild)),
      ),
    ],
    prefs: prefs,
  );
  await tester.pumpAndSettle();
}

void main() {
  // ===========================================================
  // 어르신 폰
  // ===========================================================
  testWidgets('a notice covers the parent\'s home and says who it is from', (
    tester,
  ) async {
    final h = await _seniorFamily();
    await _pumpSeniorHome(tester, h);

    expect(find.byKey(SeniorServiceNotice.cardKey), findsOneWidget);
    // The company, in so many words, before what it says.
    expect(find.text('잘보이네에서\n알려 드려요'), findsOneWidget);
    expect(find.text(_maintenance.body), findsOneWidget);
    // One button: there is nothing to agree to or put off.
    expect(find.byKey(SeniorServiceNotice.okKey), findsOneWidget);
    expect(find.text('나중에 볼게요'), findsNothing);
  });

  testWidgets('확인했어요 closes it, and it stays closed on this phone', (
    tester,
  ) async {
    final h = await _seniorFamily();
    await _pumpSeniorHome(tester, h);

    await tester.tap(find.byKey(SeniorServiceNotice.okKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SeniorServiceNotice.cardKey), findsNothing);

    // A later run of the app, with what this phone wrote down.
    await _pumpSeniorHome(
      tester,
      h,
      extraPrefs: {
        AnnouncementDismissals.idsKey: [_maintenance.id],
      },
    );
    expect(find.byKey(SeniorServiceNotice.cardKey), findsNothing);
  });

  testWidgets('a message from the family comes before the company', (
    tester,
  ) async {
    final h = await _seniorFamily(say: '엄마, 점심 드셨어요?');
    await _pumpSeniorHome(tester, h);

    expect(find.byKey(FamilyMessagePrompt.openKey), findsOneWidget);
    expect(find.byKey(SeniorServiceNotice.cardKey), findsNothing);
  });

  testWidgets('a notice for older builds is not shown to this one', (
    tester,
  ) async {
    // 업데이트해 주세요 is said to the phones that have not, and to nobody
    // else. This build is 1.
    final h = await _seniorFamily();
    await _pumpSeniorHome(
      tester,
      h,
      notices: const [
        Announcement(id: 'old', title: 't', body: '업데이트해 주세요', belowBuild: 1),
      ],
    );
    expect(find.byKey(SeniorServiceNotice.cardKey), findsNothing);
  });

  for (final size in FontSize.values) {
    testWidgets('the card and its button fit the screen at ${size.name}', (
      tester,
    ) async {
      // The card does not scroll, and the body is written on a server by
      // somebody who may not count lines - so the longest body is tried.
      final h = await _seniorFamily();
      await _pumpSeniorHome(
        tester,
        h,
        fontSize: size,
        notices: [
          Announcement(
            id: 'long',
            title: 't',
            body: List.filled(12, '아주 긴 공지 내용이 이어집니다').join(' '),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byKey(SeniorServiceNotice.okKey));
      expect(button.bottom, lessThanOrEqualTo(844));
      expect(button.top, greaterThanOrEqualTo(0));
    });
  }

  // ===========================================================
  // 자녀 폰
  // ===========================================================
  testWidgets('a notice sits at the top of the guardian\'s 홈', (tester) async {
    await _pumpGuardianHome(tester, notices: const [_maintenance]);

    expect(
      find.byKey(GuardianServiceNotices.noticeKey(_maintenance.id)),
      findsOneWidget,
    );
    expect(find.text(_maintenance.title), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(GuardianServiceNotices.noticeKey(_maintenance.id)),
      findsNothing,
    );
  });

  testWidgets('a newer build on Play is offered, and 나중에 holds for it', (
    tester,
  ) async {
    await _pumpGuardianHome(tester, latestBuild: 2);

    expect(find.byKey(GuardianServiceNotices.updateKey), findsOneWidget);
    expect(find.textContaining('부모님 폰은 그대로입니다'), findsOneWidget);
    await tester.tap(find.byKey(GuardianServiceNotices.updateLaterKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianServiceNotices.updateKey), findsNothing);

    // Put off for build 2, so build 2 does not ask again...
    await _pumpGuardianHome(
      tester,
      latestBuild: 2,
      prefs: {AnnouncementDismissals.updateKey: 2},
    );
    expect(find.byKey(GuardianServiceNotices.updateKey), findsNothing);
    // ...and build 3 does.
    await _pumpGuardianHome(
      tester,
      latestBuild: 3,
      prefs: {AnnouncementDismissals.updateKey: 2},
    );
    expect(find.byKey(GuardianServiceNotices.updateKey), findsOneWidget);
  });

  testWidgets('no newer build, or none written, offers nothing', (
    tester,
  ) async {
    await _pumpGuardianHome(tester, latestBuild: 1);
    expect(find.byKey(GuardianServiceNotices.updateKey), findsNothing);
    await _pumpGuardianHome(tester);
    expect(find.byKey(GuardianServiceNotices.updateKey), findsNothing);
  });
}
