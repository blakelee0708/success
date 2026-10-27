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

  test('the policy claims no runtime permission, and the manifest agrees', () {
    // The policy says so in as many words, and it is a large part of why the
    // app can say what it says about location, contacts and call logs. The
    // day somebody adds a `uses-permission` for a feature, this page has to
    // be rewritten in the same commit — not whenever it is next read.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      policy,
      contains('런타임 권한을 하나도 요구하지 않습니다'),
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
    final hasBlanks = policy.contains('「 ');

    expect(
      hasBlanks ? policy.contains('아직 공개 전 초안입니다') : true,
      isTrue,
      reason:
          'the page still has 「 」 fields, so it must keep the notice saying '
          'it is not ready to publish',
    );
  });
}
