import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/family/presentation/family_link_screen.dart'
    show enterCodeQuestion;

import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/pair_link.dart';

({InMemorySeniorLinkRepository store, InMemoryPairingRepository pairing})
_fresh({DateTime Function()? now}) {
  final store = InMemorySeniorLinkRepository();
  return (
    store: store,
    pairing: InMemoryPairingRepository(store, now: now ?? DateTime.now),
  );
}

void main() {
  group('경로 B — the parent shows a code, the guardian types it', () {
    test('a phone with no guardian can start on its own', () async {
      // Path A depends on the Play install referrer, which only survives a
      // store install, so this path is the required fallback — and it has to
      // work before any guardian exists.
      final h = _fresh();

      final link = await h.pairing.startSeniorPairing(installId: 'install-1');

      expect(link.mode, PairMode.seniorSharesCode);
      expect(link.seniorProfileId, isNotNull);
      expect(h.store.profiles, hasLength(1));
    });

    test('the code is four digits', () async {
      final h = _fresh();
      final link = await h.pairing.startSeniorPairing(installId: 'install-1');

      expect(link.code, hasLength(4));
      expect(int.tryParse(link.code), isNotNull);
    });

    test('asking again does not create a second parent', () async {
      final h = _fresh();
      await h.pairing.startSeniorPairing(installId: 'install-1');
      await h.pairing.startSeniorPairing(installId: 'install-1');

      expect(h.store.profiles, hasLength(1));
    });

    test('claiming names the parent and makes the guardian primary', () async {
      // The code cannot carry a name or a number, so the guardian supplies
      // both — and the name is the one the senior will recognise.
      final h = _fresh();
      final link = await h.pairing.startSeniorPairing(installId: 'install-1');

      final profile = await h.pairing.claimSeniorPairingCode(
        code: link.code,
        displayName: '어머니',
      );

      expect(profile.displayName, '어머니');
      final guardians = await h.pairing.guardiansFor(profile.id);
      expect(guardians.single.isPrimary, isTrue);
    });

    test('a code cannot be claimed twice', () async {
      final h = _fresh();
      final link = await h.pairing.startSeniorPairing(installId: 'install-1');
      await h.pairing.claimSeniorPairingCode(
        code: link.code,
        displayName: '어머니',
      );

      await expectLater(
        h.pairing.claimSeniorPairingCode(code: link.code, displayName: '가로채기'),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('a code stops working once it has expired', () async {
      // Ten minutes. A 4-digit code that lives longer is a 4-digit code worth
      // guessing.
      var clock = DateTime(2026, 7, 30, 12);
      final h = _fresh(now: () => clock);
      final link = await h.pairing.startSeniorPairing(installId: 'install-1');

      clock = clock.add(const Duration(minutes: 11));

      await expectLater(
        h.pairing.claimSeniorPairingCode(code: link.code, displayName: '어머니'),
        throwsA(isA<SeniorLinkException>()),
      );
    });
  });

  group('경로 A — the guardian texts an install link', () {
    test('the invite carries a token and a fallback code', () async {
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');

      expect(link.token, isNotEmpty);
      expect(link.code, hasLength(6));
    });

    test('the parent’s phone redeems the token', () async {
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');

      final profile = await h.pairing.redeemSeniorInvite(
        installId: 'install-1',
        token: link.token,
      );

      expect(profile.id, link.seniorProfileId);
    });

    test(
      'the same invite works by code when the link did not survive',
      () async {
        // Most installs that did not come from the store lose the referrer.
        final h = _fresh();
        final link = await h.pairing.createSeniorInvite(displayName: '아버지');

        final profile = await h.pairing.redeemSeniorInvite(
          installId: 'install-1',
          code: link.code,
        );

        expect(profile.id, link.seniorProfileId);
      },
    );

    test('redeeming with neither is refused', () async {
      final h = _fresh();
      await h.pairing.createSeniorInvite(displayName: '아버지');

      await expectLater(
        h.pairing.redeemSeniorInvite(installId: 'install-1'),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('the first text is the link and only the link', () async {
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');

      final body = link.installLinkMessage('com.jalboine.app');

      // The token rides in as the Play install referrer, which is what makes
      // 경로 A automatic.
      expect(body, contains('referrer=${link.token}'));
      // One job per text. The number in the third line of this one is what
      // a parent on a real phone could not find.
      expect(body, isNot(contains(link.code)));
      // Not addressed by what the child typed: 아버지님 at the top of a text
      // is not how anybody writes to their father.
      expect(body, isNot(contains('아버지')));
      // Nothing here may claim the message was sent — the app can only hand
      // it to the SMS app, and cannot see what happens next.
      expect(body, isNot(contains('발송')));
    });

    test('the second text says where to type, then the number alone', () async {
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');

      final body = link.codeMessage();

      // The words on the parent's own screens, so they can be matched by eye.
      expect(body, contains('「가족 연결」'));
      expect(body, contains('「$enterCodeQuestion」'));
      // Last, and on a line of its own: that is the line read out.
      expect(body.split('\n').last, link.code);
      expect(body, isNot(contains('referrer')));
    });

    test('before the app is on Play, the text sent alone skips 설치하고', () async {
      // The parent's app was installed by hand, and a store link would open
      // a page that does not exist yet - so there is one text, and it may
      // not tell anybody to install first.
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');

      final body = link.codeMessage(afterInstall: false);

      expect(body, startsWith('잘보이네 앱을 여신 뒤'));
      expect(body, isNot(contains('설치')));
      expect(body.split('\n').last, link.code);
    });

    test('a parent still waiting counts against the one-to-one lock', () async {
      // `assert_can_add_senior` counts 'pending' links. The twin counted
      // only linked ones, so a second invite passed here and the server
      // refused it.
      final store = InMemorySeniorLinkRepository()..pendingLinkConsent = true;
      final pairing = InMemoryPairingRepository(store);
      await pairing.createSeniorInvite(displayName: '어머니');

      await expectLater(
        pairing.createSeniorInvite(displayName: '아버지'),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('an unused invite can be read back, and a used one cannot', () async {
      // The number has to survive the app being closed: the day after is
      // when a parent asks 번호가 뭐였지.
      final h = _fresh();
      final link = await h.pairing.createSeniorInvite(displayName: '아버지');
      final profileId = link.seniorProfileId!;

      expect(await h.pairing.openSeniorInvite(profileId), link);

      await h.pairing.redeemSeniorInvite(
        installId: 'install-1',
        code: link.code,
      );

      expect(await h.pairing.openSeniorInvite(profileId), isNull);
    });
  });

  group('recovery', () {
    test('a replaced phone restores the parent it already had', () async {
      final h = _fresh();
      final started = await h.pairing.startSeniorPairing(
        installId: 'old-phone',
      );
      final profile = await h.pairing.claimSeniorPairingCode(
        code: started.code,
        displayName: '어머니',
      );

      final code = await h.pairing.createRecoveryCode(profile.id);
      final restored = await h.pairing.redeemRecoveryCode(
        code: code.code,
        installId: 'new-phone',
      );

      expect(restored.id, profile.id);
      expect(h.store.profiles, hasLength(1));
    });

    test('recovery retires the phone that held the profile before', () async {
      final h = _fresh();
      final started = await h.pairing.startSeniorPairing(
        installId: 'old-phone',
      );
      final profile = await h.pairing.claimSeniorPairingCode(
        code: started.code,
        displayName: '어머니',
      );

      final code = await h.pairing.createRecoveryCode(profile.id);
      await h.pairing.redeemRecoveryCode(
        code: code.code,
        installId: 'new-phone',
      );

      expect(h.store.activeDeviceByProfile[profile.id]!.installId, 'new-phone');
    });

    test(
      'a guardian who does not manage the parent cannot issue one',
      () async {
        final h = _fresh();
        final started = await h.pairing.startSeniorPairing(
          installId: 'install-1',
        );
        final profile = await h.pairing.claimSeniorPairingCode(
          code: started.code,
          displayName: '어머니',
        );

        h.pairing.actingGuardianId = 'someone-else';

        await expectLater(
          h.pairing.createRecoveryCode(profile.id),
          throwsA(isA<SeniorLinkException>()),
        );
      },
    );
  });
}
