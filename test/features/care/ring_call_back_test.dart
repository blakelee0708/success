import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_settings.dart';
import 'package:app/features/care/application/senior_ring_controller.dart';
import 'package:app/features/care/data/emergency_sound.dart';
import 'package:app/features/care/presentation/senior_ring_layer.dart';
import 'package:app/features/launcher/data/app_launcher.dart';
import 'package:app/features/launcher/data/phone_dialer.dart';

import '../../support/pump_app.dart';

/// 소리 울리기's other half, on the parent's phone.
///
/// Silencing the noise is not the resolution of 엄마가 전화를 안 받아. A senior
/// who picks up a loud phone and can only make it quiet has been told
/// something and given nothing to do about it, and the thing their child
/// wanted was a call. The number is already on the server, collected when the
/// guardian connected.
class FakePhoneDialer implements PhoneDialer {
  final List<String> opened = [];

  @override
  Future<void> openDialer(String number) async => opened.add(number);
}

class _Family {
  const _Family({
    required this.dialer,
    required this.sound,
    required this.guardianIds,
  });

  final FakePhoneDialer dialer;
  final FakeEmergencySound sound;

  /// In the order they were created.
  final List<String> guardianIds;
}

/// A parent's phone with [phones] attached to it, one entry per child.
///
/// A null entry is a guardian who left the number blank, which the field
/// they fill says is allowed - so it is a real state rather than a contrived
/// one.
Future<_Family> _pumpHome(
  WidgetTester tester, {
  List<({String name, String? phone})> phones = const [
    (name: '영희', phone: '01012345678'),
  ],
}) async {
  final links = InMemorySeniorLinkRepository();
  final pairing = InMemoryPairingRepository(links);

  final ids = <String>[];
  // The twin keeps one guardian account, so each name is created, linked and
  // then the next one overwrites it — which is enough: what the screen reads
  // back is the roster, and the roster keeps every link.
  final started = await pairing.startSeniorPairing(installId: 'senior-phone');
  for (final entry in phones) {
    final account = await links.ensureGuardianAccount(
      displayName: entry.name,
      phoneNumber: entry.phone,
    );
    ids.add(account.id);
  }
  final profile = await pairing.claimSeniorPairingCode(
    code: started.code,
    displayName: '어머니',
  );

  final dialer = FakePhoneDialer();
  final sound = FakeEmergencySound();
  await pumpApp(
    tester,
    overrides: [
      appLauncherProvider.overrideWithValue(FakeAppLauncher(defaultHome: true)),
      emergencySoundProvider.overrideWithValue(sound),
      phoneDialerProvider.overrideWithValue(dialer),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
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
  return _Family(dialer: dialer, sound: sound, guardianIds: ids);
}

Future<void> _ring(
  WidgetTester tester, {
  String from = '영희',
  String? fromGuardianId,
}) async {
  final context = tester.element(find.byType(Scaffold).first);
  ProviderScope.containerOf(context)
      .read(seniorRingControllerProvider.notifier)
      .ring(RingRequest(from: from, fromGuardianId: fromGuardianId));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sender gets a call button with their own name', (
    tester,
  ) async {
    final family = await _pumpHome(tester);
    await _ring(tester, fromGuardianId: family.guardianIds.single);

    expect(find.byKey(SeniorRingLayer.callKey), findsOneWidget);
    expect(find.textContaining('영희에게'), findsOneWidget);
  });

  testWidgets('pressing it dials them and stops the noise', (tester) async {
    // Dialling, never calling. `06_PERMISSION_AND_POLICY` requires the user
    // press call themselves, and that holds here exactly as it does for 119.
    final family = await _pumpHome(tester);
    await _ring(tester, fromGuardianId: family.guardianIds.single);
    expect(family.sound.isPlaying, isTrue);

    await tester.tap(find.byKey(SeniorRingLayer.callKey));
    await tester.pumpAndSettle();

    expect(family.dialer.opened, ['01012345678']);
    expect(family.sound.isPlaying, isFalse);
    expect(find.byKey(SeniorRingLayer.layerKey), findsNothing);
  });

  testWidgets('a push with no sender id offers no call', (tester) async {
    // It still rings and still says who, because the guardian pressed the
    // button and has no way of learning it did nothing.
    await _pumpHome(tester);
    await _ring(tester);

    expect(find.byKey(SeniorRingLayer.layerKey), findsOneWidget);
    expect(find.textContaining('영희'), findsWidgets);
    expect(find.byKey(SeniorRingLayer.callKey), findsNothing);
    expect(find.byKey(SeniorRingLayer.stopKey), findsOneWidget);
  });

  testWidgets('a guardian who left the number blank offers no call', (
    tester,
  ) async {
    final family = await _pumpHome(
      tester,
      phones: const [(name: '영희', phone: null)],
    );
    await _ring(tester, fromGuardianId: family.guardianIds.single);

    expect(find.byKey(SeniorRingLayer.callKey), findsNothing);
    expect(find.byKey(SeniorRingLayer.stopKey), findsOneWidget);
  });

  testWidgets('a sender nobody in the family matches offers no call', (
    tester,
  ) async {
    // Never falls back to the primary guardian. Two children ring the same
    // phone, and a call button that reaches the other one is worse than no
    // button: the senior would believe they had answered their child.
    await _pumpHome(tester);
    await _ring(tester, fromGuardianId: 'somebody-else');

    expect(find.byKey(SeniorRingLayer.callKey), findsNothing);
  });

  testWidgets('with two children it dials the one who rang', (tester) async {
    final family = await _pumpHome(
      tester,
      phones: const [
        (name: '영희', phone: '01011112222'),
        (name: '철수', phone: '01033334444'),
      ],
    );
    await _ring(
      tester,
      from: '철수',
      fromGuardianId: family.guardianIds.last,
    );

    await tester.tap(find.byKey(SeniorRingLayer.callKey));
    await tester.pumpAndSettle();

    expect(family.dialer.opened, ['01033334444']);
  });
}
