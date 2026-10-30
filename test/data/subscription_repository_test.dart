import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/remote/subscription_repository.dart';
import 'package:app/domain/senior_profile.dart';
import 'package:app/domain/subscription.dart';
import 'package:app/features/care/data/care_interfaces.dart';

typedef Harness = ({
  InMemorySeniorLinkRepository store,
  InMemoryPairingRepository pairing,
  InMemorySubscriptionRepository subs,
  String profileId,
});

/// One parent, connected, with a guardian who can buy things for them.
Future<Harness> _family() async {
  final store = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(store);
  final subs = InMemorySubscriptionRepository(store);
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );
  return (store: store, pairing: pairing, subs: subs, profileId: profile.id);
}

void main() {
  group('paid features do not activate before consent', () {
    test('paying leaves the subscription waiting on the senior', () async {
      final h = await _family();

      final sub = await h.subs.startCare(h.profileId);

      expect(sub.status, SubscriptionStatus.pendingSeniorConsent);
      expect(sub.isWaitingOnSenior, isTrue);
    });

    test('nothing is active until the senior answers', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      expect(await h.subs.careIsActive(h.profileId), isFalse);
    });

    test('the profile records that it has been asked', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      expect(
        h.store.profiles[h.profileId]!.paidConsentStatus,
        PaidConsentStatus.pending,
      );
    });

    test('paying twice is refused', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      await expectLater(
        h.subs.startCare(h.profileId),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('only the senior device may answer', () async {
      // A guardian answering their own purchase would make the consent
      // ceremonial.
      final h = await _family();
      await h.subs.startCare(h.profileId);
      h.store.seniorInstallId = 'some-other-phone';

      await expectLater(
        h.subs.resolveCareConsent(h.profileId, true),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('agreeing is what turns it on', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      await h.subs.resolveCareConsent(h.profileId, true);

      expect(await h.subs.careIsActive(h.profileId), isTrue);
    });
  });

  group('a refusal refunds', () {
    test('the subscription is refunded, with a date', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      await h.subs.resolveCareConsent(h.profileId, false);

      final sub = h.subs.subscriptions.single;
      expect(sub.status, SubscriptionStatus.refunded);
      expect(sub.refundedAt, isNotNull);
    });

    test('the paid features stay off', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      await h.subs.resolveCareConsent(h.profileId, false);

      expect(await h.subs.careIsActive(h.profileId), isFalse);
    });

    test('the guardian is told, and told the money came back', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);

      await h.subs.resolveCareConsent(h.profileId, false);

      final alert = (await h.subs.alertsFor(h.profileId)).single;
      expect(alert.type, 'care_consent_refused');
      expect(alert.body, contains('환불'));
      // 무료 기능은 유지 — and the guardian is told that too, so a refusal does
      // not read as the app having stopped working.
      expect(alert.body, contains('무료 기능은 그대로'));
    });

    test('answering again is refused, so a refusal is not a nag', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, false);

      await expectLater(
        h.subs.resolveCareConsent(h.profileId, true),
        throwsA(isA<SeniorLinkException>()),
      );
    });

    test('the guardian may ask again after talking to them', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, false);

      final again = await h.subs.startCare(h.profileId);

      expect(again.isWaitingOnSenior, isTrue);
    });
  });

  group('환불은 쓴 날로 정한다', () {
    // The server's `care_refund_due`, which the twin mirrors so the screens
    // can be built against it. Who ended it does not enter into it.
    Future<Harness> paid() async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, true);
      return h;
    }

    test('unused, inside seven days of the payment: all of it', () async {
      final h = await paid();
      final ended = await h.subs.cancelCare(h.profileId);
      expect(ended.status, SubscriptionStatus.refunded);
      expect(ended.refundKind, RefundKind.full);
    });

    test('unused, after seven days: the remaining days', () async {
      final h = await paid();
      final id = h.subs.subscriptions.single.id;
      h.subs.paidAt[id] = DateTime.now().subtract(const Duration(days: 8));
      final ended = await h.subs.cancelCare(h.profileId);
      expect(ended.status, SubscriptionStatus.refunded);
      expect(ended.refundKind, RefundKind.remaining);
    });

    test('used: nothing back, and the month runs to its end', () async {
      final h = await paid();
      h.subs.used.add(h.subs.subscriptions.single.id);
      final ended = await h.subs.cancelCare(h.profileId);
      expect(ended.status, SubscriptionStatus.canceled);
      expect(ended.refundKind, isNull);
      expect(ended.refundedAt, isNull);
    });

    test('never answered by the parent: all of it, however late', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      final id = h.subs.subscriptions.single.id;
      h.subs.paidAt[id] = DateTime.now().subtract(const Duration(days: 20));
      final ended = await h.subs.cancelCare(h.profileId);
      expect(ended.refundKind, RefundKind.full);
    });

    test('a refusal is a full refund', () async {
      final h = await _family();
      await h.subs.startCare(h.profileId);
      await h.subs.resolveCareConsent(h.profileId, false);
      expect(h.subs.subscriptions.single.refundKind, RefundKind.full);
    });

    test('asked again after a reconnect: 허락 brings the month back', () async {
      final h = await paid();
      h.subs.used.add(h.subs.subscriptions.single.id);
      await h.subs.cancelCare(h.profileId);
      h.store.setConsent(h.profileId, PaidConsentStatus.pending);
      await h.subs.resolveCareConsent(h.profileId, true);
      expect(await h.subs.careIsActive(h.profileId), isTrue);
      expect(
        h.store.profiles[h.profileId]!.paidConsentStatus,
        PaidConsentStatus.granted,
      );
    });

    test('asked again after a reconnect: 거절 refunds nothing', () async {
      final h = await paid();
      h.subs.used.add(h.subs.subscriptions.single.id);
      await h.subs.cancelCare(h.profileId);
      h.store.setConsent(h.profileId, PaidConsentStatus.pending);
      await h.subs.resolveCareConsent(h.profileId, false);
      final row = h.subs.subscriptions.single;
      expect(row.status, SubscriptionStatus.canceled);
      expect(row.refundKind, isNull);
      expect(h.subs.alerts[h.profileId]!.first.body, contains('환불은 없습니다'));
    });

    test('the row carries the kind the server wrote', () {
      final row = {
        'id': 's1',
        'plan': 'care',
        'status': 'refunded',
        'refund_kind': 'remaining',
      };
      expect(Subscription.fromRow(row)!.refundKind, RefundKind.remaining);
      expect(
        Subscription.fromRow({...row, 'refund_kind': null})!.refundKind,
        isNull,
      );
    });
  });

  group('the gate', () {
    test('consent without a subscription is not active', () {
      const profile = SeniorProfile(
        id: 'p1',
        displayName: '어머니',
        customerCode: 'CODE0001',
        paidConsentStatus: PaidConsentStatus.granted,
      );

      expect(
        careIsActiveFor(profile: profile, hasActiveCareSubscription: false),
        isFalse,
      );
    });

    test('a subscription without consent is not active', () {
      // The half that decides. A paid subscription whose senior said nothing
      // must be indistinguishable from no subscription.
      const profile = SeniorProfile(
        id: 'p1',
        displayName: '어머니',
        customerCode: 'CODE0001',
        paidConsentStatus: PaidConsentStatus.pending,
      );

      expect(
        careIsActiveFor(profile: profile, hasActiveCareSubscription: true),
        isFalse,
      );
    });

    test('both halves make it active', () {
      const profile = SeniorProfile(
        id: 'p1',
        displayName: '어머니',
        customerCode: 'CODE0001',
        paidConsentStatus: PaidConsentStatus.granted,
      );

      expect(
        careIsActiveFor(profile: profile, hasActiveCareSubscription: true),
        isTrue,
      );
    });
  });

  group('the interfaces are declared, not faked', () {
    test('the unbuilt background sync does nothing rather than pretending', () {
      // The readings themselves are real now — they ride on the check-in. What
      // is still missing is the schedule that would refresh them while the
      // phone sits untouched, and an implementation that quietly did nothing
      // while claiming to run is worse than one that is plainly absent.
      const sync = UnimplementedDeviceStatusSync();

      expect(sync.start('p1'), completes);
      expect(sync.stop(), completes);
    });

    test('the periodic checks state the interval the policy fixed', () {
      expect(DeviceStatusSync.interval, const Duration(minutes: 5));
      expect(PeriodicLocationCheck.interval, const Duration(minutes: 5));
    });
  });
}
