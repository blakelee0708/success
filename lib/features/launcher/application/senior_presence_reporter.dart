import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/app_version.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/device_status.dart';
import '../data/device_status_reader.dart';

/// Tells the server the parent's phone is still being used, and carries the
/// battery and ringer reading along with it.
///
/// This is 안부 신호 and 기기 상태 together, and the reason they are worth
/// having is what they do *not* need: no location, no background service, no
/// sensor permission, nothing Play reviews and nothing the senior has to
/// agree to beyond the app itself. Because this app is the phone's home
/// screen, coming to the foreground means the parent unlocked the phone or
/// came back from another app — which is a real answer to 오늘 폰을 쓰셨나,
/// the question the guardian actually opens the dashboard to ask.
///
/// It fails quietly and is never awaited by anything on screen. The senior's
/// launcher has to start at full speed on a phone with no signal; a courtesy
/// to someone else's dashboard does not get to be in the way of that.
class SeniorPresenceReporter {
  SeniorPresenceReporter(this._ref);

  final Ref _ref;

  /// The most recent reading the phone managed to take, used by the *next*
  /// check-in. See [report].
  DeviceStatus? _lastRead;

  /// The parent's phone used to read an FCM token here and send it up with
  /// the check-in, so 소리 울리기 had an address to reach. That feature is
  /// out of the product, and an address nothing sends to is a thing
  /// collected for no reason - so the read is gone and
  /// `20261029060000_drop_ring.sql` takes the column with it.
  ///
  /// True while a read is outstanding, so a burst of resumes does not stack
  /// calls up on a channel that is already not answering.
  bool _readingStatus = false;

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

    // After the guard, for the same reason the repository is read after it:
    // this runs on the guardian's phone too, and theirs must never be handed
    // an anonymous session. A phone with a profile is a parent's phone.
    //
    // Awaited, unlike the two channel reads below. A session restored from
    // disk returns at once, and with none there is nothing to report to:
    // `touch_senior_device` is scoped to `auth_user_id = auth.uid()` and a
    // call with no session updates no rows.
    if (!await _ref.read(seniorAuthProvider).ensure()) return false;

    // Started, never awaited. A platform channel is not obliged to reply —
    // `flutter test` is such a platform, and so is a phone whose launcher
    // service has wedged — so waiting for one here would trade the check-in,
    // which is the valuable half, for a battery percentage. The same trap
    // the onboarding screen documents, one feature along. Bounding the wait
    // with a timeout was tried and is worse: it leaves a pending timer
    // behind on every phone that does not answer, and `flutter test` is such
    // a phone — eighteen tests failed at teardown rather than in the open.
    unawaited(_readStatus());

    try {
      // Whatever the last read found, which on a working phone is the
      // previous resume — stamped with its own time, so the dashboard shows
      // the reading's real age rather than implying it is current. Null
      // leaves whatever the server last held standing rather than
      // overwriting a real reading with blanks.
      await _ref
          .read(seniorLinkRepositoryProvider)
          .touchDevice(
            link.installId,
            status: _lastRead,
            // Sent every time rather than once, because the phone that
            // matters is the one that just updated and the server coalesces
            // anyway. It is a constant, so no channel is involved and
            // nothing can fail to answer for it.
            appVersion: appVersion,
          );
      return true;
    } on Object {
      return false;
    }
  }

  /// The battery and the ringer, for the *next* check-in.
  ///
  /// Started and not awaited. Bounding the wait with a timeout was tried and
  /// is worse: it leaves a pending timer behind on every phone that does not
  /// answer, and `flutter test` is such a phone — eighteen tests failed at
  /// teardown rather than in the open.
  Future<void> _readStatus() async {
    if (_readingStatus) return;
    _readingStatus = true;
    try {
      final status = await _ref.read(deviceStatusReaderProvider).read();
      // A failed read keeps the last good one rather than clearing it.
      if (status != null) _lastRead = status;
    } on Object {
      // A phone that cannot read its own battery is not a phone that has
      // stopped being used.
    } finally {
      _readingStatus = false;
    }
  }
}

final seniorPresenceReporterProvider = Provider<SeniorPresenceReporter>(
  SeniorPresenceReporter.new,
);
