import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
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
import 'package:app/features/messages/data/photo_picker.dart';
import 'package:app/features/messages/presentation/conversation_view.dart';
import 'package:app/features/messages/presentation/family_message_prompt.dart';

import '../../support/pump_app.dart';

/// 이미지 전송 — the one thing `04_SCREEN_SPEC` asks of the message tab that
/// it could not do.
///
/// The table half has existed since Phase 7: the column, an allowance counted
/// apart from the text one, and an RPC that refuses an eleventh photo on the
/// free plan. What was missing was somewhere for the file to go, and a way to
/// choose one.
typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  InMemoryMessageRepository messages,
  String profileId,
});

Future<Harness> _family() async {
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
  return (
    store: store,
    pairing: pairing,
    subs: subs,
    messages: messages,
    profileId: profile.id,
  );
}

final _bytes = Uint8List.fromList([1, 2, 3, 4]);

List<Object> _shared(Harness h, PhotoPicker picker) => [
  seniorLinkRepositoryProvider.overrideWithValue(h.store),
  pairingRepositoryProvider.overrideWithValue(h.pairing),
  subscriptionRepositoryProvider.overrideWithValue(h.subs),
  messageRepositoryProvider.overrideWithValue(h.messages),
  homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
  photoPickerProvider.overrideWithValue(picker),
];

Future<void> _pumpGuardian(
  WidgetTester tester,
  Harness h,
  PhotoPicker picker,
) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1'));
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      ..._shared(h, picker),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('메시지'));
  await tester.pumpAndSettle();
}

Future<void> _pumpSenior(
  WidgetTester tester,
  Harness h,
  PhotoPicker picker,
) async {
  h.messages.sendingAsSenior = true;
  h.messages.readingAsSenior = true;
  await pumpApp(
    tester,
    overrides: [
      ..._shared(h, picker),
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: h.profileId),
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
  // 가족 goes to the conversation once a family is attached — the job the
  // band gave back to it when the band went down to a clock.
  if (find.byKey(FamilyMessagePrompt.openKey).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(FamilyMessagePrompt.openKey));
  } else {
    await tester.tap(find.text('가족'));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the guardian can send a photo', (tester) async {
    final h = await _family();
    final picker = FakePhotoPicker(
      photo: PickedPhoto(bytes: _bytes, contentType: 'image/jpeg'),
    );

    await _pumpGuardian(tester, h, picker);
    await tester.tap(find.byKey(ConversationKeys.photo));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(h.messages.uploaded, hasLength(1));
    final sent = await h.messages.conversation(h.profileId);
    expect(sent.single.imageUrl, h.messages.uploaded.single);
    // A photo is not an empty text message.
    expect(sent.single.body, isNull);
  });

  testWidgets('the file goes in the parent’s own folder', (tester) async {
    // The bucket's policies read the senior's profile id out of the first
    // path segment, so the layout is not cosmetic — it is the access rule.
    final h = await _family();
    final picker = FakePhotoPicker(
      photo: PickedPhoto(bytes: _bytes, contentType: 'image/jpeg'),
    );

    await _pumpGuardian(tester, h, picker);
    await tester.tap(find.byKey(ConversationKeys.photo));
    await tester.pumpAndSettle();

    expect(h.messages.uploaded.single, startsWith('${h.profileId}/'));
  });

  testWidgets('backing out of the picker sends nothing', (tester) async {
    // Not a failure, and it must not be drawn as one.
    final h = await _family();
    final picker = FakePhotoPicker.cancelled();

    await _pumpGuardian(tester, h, picker);
    await tester.tap(find.byKey(ConversationKeys.photo));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(h.messages.uploaded, isEmpty);
    expect(find.byKey(ConversationKeys.error), findsNothing);
  });

  testWidgets('the parent can send one back', (tester) async {
    final h = await _family();
    final picker = FakePhotoPicker(
      photo: PickedPhoto(bytes: _bytes, contentType: 'image/jpeg'),
    );

    await _pumpSenior(tester, h, picker);
    await tester.tap(find.byKey(ConversationKeys.photo));
    await tester.pumpAndSettle();

    final sent = await h.messages.conversation(h.profileId);
    expect(sent.single.isFromSenior, isTrue);
    expect(sent.single.imageUrl, isNotNull);
  });

  testWidgets('a photo appears in the conversation', (tester) async {
    final h = await _family();
    await h.messages.send(h.profileId, imagePath: '${h.profileId}/1.jpg');

    await _pumpGuardian(tester, h, FakePhotoPicker.cancelled());

    expect(
      find.byKey(ConversationKeys.image(
        (await h.messages.conversation(h.profileId)).single.id,
      )),
      findsOneWidget,
    );
  });

  testWidgets('photos have their own allowance, apart from the text one', (
    tester,
  ) async {
    // 월 50회 / 이미지 10개. Running out of one does not stop the other,
    // which is the whole reason the server counts them in two columns.
    final h = await _family();
    for (var i = 0; i < 10; i++) {
      await h.messages.send(h.profileId, imagePath: '${h.profileId}/$i.jpg');
    }
    final quota = await h.messages.quota(h.profileId);

    expect(quota.canSendImage, isFalse);
    expect(quota.canSendText, isTrue, reason: 'images ate the text allowance');
  });
}
