import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/guardian_auth_repository.dart';

/// `site/privacy.html` is the URL Play 심사 and 카카오 동의항목 are given, so
/// it is read by a reviewer rather than by a user, and a sentence in it that
/// has quietly stopped being true is the worst kind of wrong — nothing in the
/// app breaks, nobody notices, and the claim is on a page the company
/// published about itself.
///
/// Two of its claims are facts about files in this repository, and both would
/// go stale in silence. `flutter analyze` does not read XML or HTML, so this
/// reads them off disk, the same job `oauth_redirect_test.dart` does for the
/// manifest and `application_id_test.dart` does for Gradle.
///
/// What this cannot check is the collection list itself: that came out of
/// `supabase/migrations/` and the live schema, and keeping it honest is a
/// reading rather than a comparison.
void main() {
  final policy = File('site/privacy.html').readAsStringSync();

  test('this app declares no permission of its own', () {
    // A large part of why the page can say what it says about location,
    // contacts and call logs. The day somebody adds a `uses-permission` for a
    // feature, that page has to be rewritten in the same commit - not
    // whenever it is next read.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      policy,
      contains('앱이 직접 요구하는'),
      reason: 'the policy should still be making this claim',
    );
    expect(
      manifest,
      isNot(contains('uses-permission')),
      reason:
          'a declared permission makes the privacy policy false; rewrite '
          'site/privacy.html in the same commit that adds one',
    );
  });

  test('the policy names every permission the APK actually ships with', () {
    // **This file was the wrong file.** The test above reads the manifest in
    // this repository and the policy said `런타임 권한을 하나도 요구하지
    // 않습니다` on the strength of it - but Gradle merges every plugin's
    // manifest into the APK, and `firebase_messaging` brings four. Play
    // lists the merged set on the store page, so a reviewer comparing the
    // listing against the policy saw four permissions the policy denied.
    //
    // Reading `.flutter-plugins-dependencies` rather than naming the four is
    // what makes this hold: adding a plugin is how the set changes, and
    // nobody adding one would think to come here.
    final names = <String>{};
    final resolved = jsonDecode(
      File('.flutter-plugins-dependencies').readAsStringSync(),
    );
    final plugins =
        (resolved['plugins']['android'] as List).cast<Map<String, Object?>>();
    expect(plugins, isNotEmpty, reason: 'run `flutter pub get` first');

    for (final plugin in plugins) {
      final manifest = File(
        '${plugin['path']}android/src/main/AndroidManifest.xml',
      );
      if (!manifest.existsSync()) continue;
      for (final match in RegExp(
        r'uses-permission[^>]*android:name="([^"]+)"',
      ).allMatches(manifest.readAsStringSync())) {
        names.add(match.group(1)!.split('.').last);
      }
    }

    // What each one is called on the page, in the words a reader of a
    // privacy policy would recognise rather than in Android's.
    const korean = {
      'INTERNET': '인터넷 사용',
      'ACCESS_NETWORK_STATE': '네트워크 상태 보기',
      'WAKE_LOCK': '절전 모드 해제',
      'POST_NOTIFICATIONS': '알림 표시',
    };

    for (final name in names) {
      expect(
        korean,
        contains(name),
        reason:
            '$name is merged into the APK and this test has no Korean name '
            'for it; add one here and a row to site/privacy.html',
      );
      expect(
        policy,
        contains(korean[name]!),
        reason:
            '$name ships in the APK and Play lists it, but the policy does '
            'not mention it',
      );
    }
  });

  test('the policy is reachable on the host the reset mail points at', () {
    // Not the same page, but the same site, and the same custom domain. If
    // the reset redirect moves to another host the policy URL given to Play
    // moves with it, and a privacy-policy URL that 404s is a review failure.
    final host = Uri.parse(passwordResetRedirect).host;

    expect(
      host,
      'app.jalboine.com',
      reason:
          'the policy is published at https://$host/privacy.html; changing '
          'the host means changing what was given to Play and to Kakao',
    );
    expect(
      File('site/privacy.html').existsSync(),
      isTrue,
      reason: 'the page the Play listing points at has to be in site/',
    );
  });

  test('the draft says it is a draft for as long as a field is empty', () {
    // The six 사업자 fields cannot be invented, so the page ships with them
    // blank — and a blank 상호 on a published policy is worse than no page.
    // The banner is what keeps that from happening quietly: whoever fills
    // the fields removes it, and until then the page says so itself.
    // Anchored on the chip's class, not on the 「 」 glyphs. The glyphs are
    // copy and move around; `class="todo"` is what marks a field as unfilled,
    // and the check went vacuous once for exactly that reason - a `&nbsp;`
    // inside one chip stopped it matching, and a vacuous check passes.
    final hasBlanks = policy.contains('class="todo"');

    expect(
      hasBlanks ? policy.contains('아직 공개 전 초안입니다') : true,
      isTrue,
      reason:
          'the page still has 「 」 fields, so it must keep the notice saying '
          'it is not ready to publish',
    );
  });
}
