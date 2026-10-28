import 'package:flutter_test/flutter_test.dart';

import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/features/launcher/data/app_launcher.dart';

void main() {
  test('전화 opens the dialer and never places the call', () {
    // `06_PERMISSION_AND_POLICY` requires the user press call themselves, and
    // that holds for the 전화 button exactly as it does for SOS.
    expect(
      launchRequestFor(AppCategory.phone),
      const LaunchRequest(intent: LaunchIntent.dial),
    );
  });

  test('system apps are asked for by category, not by package', () {
    // Naming a package would pick one phone's dialer or gallery and break
    // every other phone.
    for (final category in [
      AppCategory.phone,
      AppCategory.message,
      AppCategory.camera,
      AppCategory.gallery,
    ]) {
      expect(
        launchRequestFor(category).packageName,
        isNull,
        reason: '$category',
      );
      expect(launchRequestFor(category).intent, isNotNull, reason: '$category');
    }
  });

  test('카카오톡 is named, because Android has no category for it', () {
    expect(launchRequestFor(AppCategory.kakao).packageName, 'com.kakao.talk');
  });

  test('카카오톡 has no web fallback', () {
    // The web version would drop a senior onto a login page, which is worse
    // than telling them it did not open.
    expect(launchRequestFor(AppCategory.kakao).fallbackUrl, isNull);
  });

  test('유튜브 falls back to the web, where the web version is usable', () {
    final request = launchRequestFor(AppCategory.youtube);
    expect(request.packageName, 'com.google.android.youtube');
    expect(request.fallbackUrl, 'https://m.youtube.com');
  });

  test('every category resolves to something openable', () {
    // Asked of a *button* rather than of a kind, because one category's
    // answer lives on the button: an `installed` one opens the package the
    // senior picked, and two of them differ only by that. Asking the kind
    // for it comes back empty — correctly — and this used to read that as a
    // category with no way to open.
    for (final category in AppCategory.values.where((c) => !c.fixedSlot)) {
      final app = LauncherApp(
        id: 'x',
        label: category.defaultLabel,
        category: category,
        packageName: category == AppCategory.installed
            ? 'com.game.gostop'
            : null,
      );
      final request = launchRequestForApp(app);
      expect(
        request.packageName ?? request.intent ?? request.fallbackUrl,
        isNotNull,
        reason: '$category has no way to open',
      );
    }
  });

  test('an app button nobody has chosen yet opens nothing', () {
    // The state the guardian's seeded button sits in until the senior picks.
    // It must resolve to nothing rather than to some fallback, so the home
    // screen can send it to the picker instead of opening a browser.
    const unchosen = LauncherApp(
      id: 'x',
      label: '앱 고르기',
      category: AppCategory.installed,
    );
    final request = launchRequestForApp(unchosen);
    expect(request.packageName, isNull);
    expect(request.intent, isNull);
    expect(request.fallbackUrl, isNull);
  });

  test('the arguments carry enum names the platform side matches on', () {
    expect(launchRequestFor(AppCategory.gallery).toArguments(), {
      'packageName': null,
      'intent': 'gallery',
      'fallbackUrl': null,
    });
  });
}
