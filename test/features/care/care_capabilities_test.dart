import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/care/data/care_capabilities.dart';

/// The rules that keep the guardian's screen and the senior's consent card
/// describing the same product.
///
/// They had drifted, and the drift was the dangerous kind: the card asked the
/// senior to agree to `5분마다 어디 계신지`, which is not built and will not be
/// until the 위치기반서비스사업 신고 is through, and to
/// `배터리와 소리, 인터넷 상태` — of which 인터넷 is never read and the rest is
/// free and sent regardless, so 아니요 would not have stopped it.
///
/// Copy can be edited back into that state in a minute. These are the checks
/// that notice.
void main() {
  test('everything the senior agrees to is built', () {
    // A consent collected today for a feature that switches on in six months
    // is a consent nobody gave. `06_PERMISSION_AND_POLICY`: 권한은 필요한
    // 순간에 요청한다.
    for (final c in consentedCareCapabilities) {
      expect(c.stage, CareReadiness.live, reason: c.key);
    }
  });

  test('everything built and paid is on the consent card', () {
    // The other direction, and the one that rots quietly: a capability that
    // starts running without ever being named on the card.
    for (final c in careCapabilities.where((c) => c.stage == CareReadiness.live)) {
      expect(
        c.seniorLine,
        isNotNull,
        reason: '${c.key} runs on consent but the card never mentions it',
      );
    }
  });

  test('nothing free is on the consent card', () {
    // It happens whether or not anyone subscribes. Listing it would tell the
    // senior that 아니요 stops something it does not stop, which is worse
    // than not asking.
    for (final c in careCapabilities.where((c) => c.stage == CareReadiness.free)) {
      expect(c.seniorLine, isNull, reason: c.key);
    }
  });

  test('nothing unbuilt is on the consent card', () {
    for (final c in plannedCareCapabilities) {
      expect(c.seniorLine, isNull, reason: c.key);
    }
  });

  test('there is something to consent to at all', () {
    // If this ever empties, the consent card asks a question with no content
    // and the guardian's money sits held against nothing.
    expect(consentedCareCapabilities, isNotEmpty);
  });

  test('every senior line fits on one line of the card', () {
    // Korean glyphs are about as wide as the type size, so at 20px in a 318px
    // card that is sixteen of them. Written long and left to wrap, a line
    // breaks mid-word on the one screen in the app where a senior is being
    // asked to agree to something — 지금 쓰시는 기능은 once broke after 기능
    // and left 은 alone.
    for (final c in consentedCareCapabilities) {
      expect(
        c.seniorLine!.length,
        lessThanOrEqualTo(16),
        reason: '${c.key}: ${c.seniorLine}',
      );
    }
  });

  test('the senior is never told about tracking, or about the internet', () {
    // 06_PERMISSION_AND_POLICY forbids the first. The second is simply not
    // read — ACCESS_NETWORK_STATE was never asked for.
    for (final c in consentedCareCapabilities) {
      for (final word in ['실시간', '추적', '인터넷']) {
        expect(c.seniorLine, isNot(contains(word)), reason: c.key);
      }
    }
  });

  test('every key is distinct, since the two screens join on it', () {
    final keys = careCapabilities.map((c) => c.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
  });
}
