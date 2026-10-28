import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/data/senior_link_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  test('the install id is minted once and reused', () async {
    final first = await SharedPreferencesSeniorLinkStore().load();
    final second = await SharedPreferencesSeniorLinkStore().load();

    // Regenerating it on every launch would retire the device on every launch.
    expect(second.installId, first.installId);
    expect(first.installId, isNotEmpty);
  });

  test('two installs do not collide', () {
    final ids = {
      for (var i = 0; i < 200; i++)
        SharedPreferencesSeniorLinkStore.newInstallId(),
    };

    expect(ids.length, 200);
  });

  test('a fresh install is not linked to any profile', () async {
    expect((await SharedPreferencesSeniorLinkStore().load()).isLinked, isFalse);
  });

  test('the linked profile survives a restart', () async {
    final store = SharedPreferencesSeniorLinkStore();
    final link = await store.load();
    await store.save(link.copyWith(seniorProfileId: 'profile-1'));

    final reloaded = await SharedPreferencesSeniorLinkStore().load();
    expect(reloaded.seniorProfileId, 'profile-1');
    expect(reloaded.installId, link.installId);
    expect(reloaded.isLinked, isTrue);
  });

  test(
    'an unreadable record mints a fresh install rather than throwing',
    () async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        SharedPreferencesSeniorLinkStore.storageKey: 'not json',
      });

      // Losing the link is recoverable — the guardian reads the code again.
      // Refusing to start is not: this app is the phone's home screen.
      final link = await SharedPreferencesSeniorLinkStore().load();
      expect(link.installId, isNotEmpty);
      expect(link.isLinked, isFalse);
    },
  );
}
