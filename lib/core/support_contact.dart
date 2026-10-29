/// How to reach 고객센터, in the one place both halves of the app read it
/// from.
///
/// **Two readers and two channels, which is the whole point.** The senior's
/// 문의하기 card shows a number to telephone, because somebody who cannot
/// find their contacts app is not going to write an email. The guardian's
/// 안심 케어 tab shows an address, because they are an adult with an ordinary
/// phone and a refund or a cancellation is not a phone call.
///
/// The address is also printed in `site/terms.html` and `site/privacy.html`,
/// and three copies of an address is how one of them quietly stops being
/// true. HTML cannot read a Dart constant, so `privacy_policy_test` reads
/// both pages off disk and fails when either disagrees with this file.
library;

/// The 고객센터 number, filled 2026-10-28 with the owner's own, which is what
/// 고객센터 is until there is a desk.
///
/// It dials rather than calls - `tel:` resolves to ACTION_DIAL - exactly as
/// 119 and 보호자 do, because `06_PERMISSION_AND_POLICY` requires the person
/// press call themselves.
///
/// **Blank is a supported state and it is handled rather than hidden.** While
/// it is empty the senior's card shows no 전화하기 button at all, because a
/// call button that dials nothing is worse than none: they press it, nothing
/// happens, and they conclude the phone is broken. The same rule 긴급 연락's
/// 보호자 tile follows.
const supportPhoneNumber = '010-7522-3157';

/// Where a guardian writes, for a refund, a cancellation or anything else.
const supportEmail = 'jalboine7979@gmail.com';
