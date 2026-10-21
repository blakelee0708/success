import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/senior_link_store.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Tells the server the parent's phone is still being used.
///
/// This is the whole of 안부 신호, and the reason it is worth having is what
/// it does *not* need: no location, no background service, no sensor, nothing
/// Play reviews and nothing the senior has to agree to beyond the app itself.
/// Because this app is the phone's home screen, coming to the foreground
/// means the parent unlocked the phone or came back from another app — which
/// is a real answer to 오늘 폰을 쓰셨나, the question the guardian actually
/// opens the dashboard to ask.
///
/// It fails quietly and is never awaited by anything on screen. The senior's
/// launcher has to start at full speed on a phone with no signal; a courtesy
/// to someone else's dashboard does not get to be in the way of that.
class SeniorPresenceReporter {
  const SeniorPresenceReporter(this._ref);

  final Ref _ref;

  /// Returns false when there was nothing to report or the report did not
  /// land. No screen shows an error either way.
  Future<bool> report() async {
    // The guard is first, and the repository is read *after* it — not taken
    // in the constructor. `HomeKeyListener` wraps the whole router, so this
    // runs on the guardian's phone too, and merely building the senior link
    // repository there reaches for a Supabase client that half of the app's
    // tests never configure. The settings pull carries the same note for the
    // same reason; writing this one with `ref.watch` in the provider hung
    // every guardian login test.
    final link = await _ref.read(seniorLinkStoreProvider).load();
    if (link.seniorProfileId == null) return false;
    try {
      await _ref.read(seniorLinkRepositoryProvider).touchDevice(link.installId);
      return true;
    } on Object {
      return false;
    }
  }
}

final seniorPresenceReporterProvider = Provider<SeniorPresenceReporter>(
  SeniorPresenceReporter.new,
);
