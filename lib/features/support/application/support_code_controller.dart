import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/senior_link_store.dart';

/// 문의하기's number, read from the server the first time the card opens.
///
/// **The only feature in the app written for a senior with nobody to ask.**
/// Everything else assumes a child: 가족 연결 needs somebody to connect,
/// 가족 메시지 somebody to write to, and 긴급 연락's 보호자 tile stays
/// disabled until a guardian leaves a number. A senior who installed this
/// alone, or whose child set it up and then could not be reached, had no way
/// to ask anybody anything - on an app that **is** their home screen.
///
/// Asked for rather than stored, and not asked for until the card opens.
/// Nothing else on the phone needs it, and a launcher has no business making
/// a server call at start-up for a screen almost nobody opens.
final supportCodeProvider = FutureProvider<String?>((ref) async {
  final link = await ref.watch(seniorLinkStoreProvider).load();
  // The anonymous session, as everywhere on this half. Without it the server
  // raises `not authenticated`, which is the failure that cost a session when
  // nothing in the app signed the phone in at all.
  if (!await ref.read(seniorAuthProvider).ensure()) return null;
  // Null rather than an error state, and that is deliberate: the card has one
  // sentence for *no number yet* and it is the same sentence either way, so a
  // second path to the same words is a path nothing exercises. Everything
  // else on this half fails quietly for the same reason - the senior is
  // looking at their own phone and cannot act on a stack trace.
  try {
    return await ref
        .read(seniorLinkRepositoryProvider)
        .supportCode(link.installId, platform: defaultTargetPlatform.name);
  } on Object {
    return null;
  }
});
