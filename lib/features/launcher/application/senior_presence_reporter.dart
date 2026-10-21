import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
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

  /// True while a read is outstanding, so a burst of resumes does not stack
  /// calls up on a channel that is already not answering.
  bool _reading = false;

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

    // Started, never awaited. A platform channel is not obliged to reply —
    // `flutter test` is such a platform, and so is a phone whose launcher
    // service has wedged — so waiting for one here would trade the check-in,
    // which is the valuable half, for a battery percentage. The same trap
    // the onboarding screen documents, one feature along. Bounding the wait
    // with a timeout was tried and is worse: it leaves a pending timer
    // behind on every phone that does not answer, and `flutter test` is such
    // a phone — eighteen tests failed at teardown rather than in the open.
    unawaited(_readAhead());

    try {
      // Whatever the last read found, which on a working phone is the
      // previous resume — stamped with its own time, so the dashboard shows
      // the reading's real age rather than implying it is current. Null
      // leaves whatever the server last held standing rather than
      // overwriting a real reading with blanks.
      await _ref
          .read(seniorLinkRepositoryProvider)
          .touchDevice(link.installId, status: _lastRead);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _readAhead() async {
    if (_reading) return;
    _reading = true;
    try {
      final status = await _ref.read(deviceStatusReaderProvider).read();
      // A failed read keeps the last good one rather than clearing it.
      if (status != null) _lastRead = status;
    } on Object {
      // A phone that cannot read its own battery is not a phone that has
      // stopped being used.
    } finally {
      _reading = false;
    }
  }
}

final seniorPresenceReporterProvider = Provider<SeniorPresenceReporter>(
  SeniorPresenceReporter.new,
);
