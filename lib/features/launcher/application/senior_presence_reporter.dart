import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/device_status.dart';
import '../../care/data/push_messaging.dart';
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

  /// The FCM address this phone was last reachable at.
  ///
  /// It rides on the check-in rather than having a call of its own, because
  /// it is the same claim — *this phone, now* — and because a token rotates:
  /// Firebase reissues it on reinstall, on a restore to a new handset and
  /// occasionally for its own reasons. Something that already runs on every
  /// resume is exactly what a rotating value needs, and a registration done
  /// once at pairing would have gone stale silently, which is how 소리 울리기
  /// would fail on the day it mattered.
  String? _lastToken;

  /// The token the server has actually been told about, which is how
  /// [_readAhead] knows whether it is holding a new one.
  String? _reportedToken;

  /// True while a read is outstanding, so a burst of resumes does not stack
  /// calls up on a channel that is already not answering. One flag each,
  /// because the two reads are independent and a stuck channel must not hold
  /// the other back.
  bool _readingStatus = false;
  bool _readingToken = false;

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
    // Two reads, started separately and neither awaited.
    //
    // Separately matters: chained, the token sat behind a platform channel
    // that is not obliged to answer — `flutter test` is such a phone, and so
    // is one whose launcher service has wedged — and so it was never read at
    // all. A battery percentage must not be able to cost the family 소리
    // 울리기.
    unawaited(_readStatus());
    unawaited(_readToken(link.installId));

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
            pushToken: _lastToken,
          );
      _reportedToken = _lastToken;
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

  /// The FCM address, and — unlike the battery — a call of its own when it
  /// turns out to be new.
  ///
  /// One resume of staleness costs a percentage nobody is watching. It costs
  /// *the address a ring is sent to*, and the window it would leave open is
  /// the one right after a phone is set up, which is exactly when the family
  /// is trying things out.
  ///
  /// It cannot loop: this is reached only from the start of a check-in, and
  /// the write marks the token as reported.
  Future<void> _readToken(String installId) async {
    if (_readingToken) return;
    _readingToken = true;
    try {
      final token = await _ref.read(pushMessagingProvider).token();
      // Same rule as the battery: null is *this phone could not say*, not
      // *this phone is unreachable*. Clearing a good token because the
      // network was down for a second would take 소리 울리기 away until the
      // next rotation.
      if (token != null) _lastToken = token;
    } on Object {
      // A build with no Firebase, or a phone with no Play Services. Neither
      // is a reason for the check-in itself to fail.
    } finally {
      _readingToken = false;
    }

    if (_lastToken == null || _lastToken == _reportedToken) return;
    try {
      await _ref.read(seniorLinkRepositoryProvider).touchDevice(
            installId,
            status: _lastRead,
            pushToken: _lastToken,
          );
      _reportedToken = _lastToken;
    } on Object {
      // The next resume tries again, because `_reportedToken` is unchanged.
    }
  }
}

final seniorPresenceReporterProvider = Provider<SeniorPresenceReporter>(
  SeniorPresenceReporter.new,
);
