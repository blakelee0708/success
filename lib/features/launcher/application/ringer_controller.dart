import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/device_status.dart';
import '../data/device_status_reader.dart';
import '../data/phone_controls.dart';

/// What the 소리 button on the home screen says, and what pressing it does.
///
/// Null means *this phone has not said yet*, never 무음. Under `flutter test`
/// there is no channel at all and the reading never arrives; the button draws
/// its fallback label rather than claiming the ringer is off. Same rule as the
/// battery: a missing reading is never a zero.
///
/// **Nothing here is awaited by the widget that draws it.** `build` starts the
/// read and returns immediately, and `toggle` flips the label before the
/// platform has answered. A channel that never answers throws nothing at all,
/// so catching is not enough - it has to not be waited on. That trap has now
/// appeared five times in this codebase: the onboarding channel, the device
/// status read, the emergency sound, the push token, and here.
class RingerController extends Notifier<RingerMode?> {
  @override
  RingerMode? build() {
    unawaited(_read());
    return null;
  }

  /// Ask the phone what it is actually set to, and correct the label.
  ///
  /// It swallows whatever the reader throws. This runs unawaited from
  /// `build`, so an exception here is not caught by anything - it surfaces as
  /// an unhandled error that fails whatever test happens to be running and,
  /// on a phone, stops the launcher drawing. A senior must not lose their
  /// home screen because the thing that reads the ringer had a bad day.
  Future<void> _read() async {
    try {
      final status = await ref.read(deviceStatusReaderProvider).read();
      final ringer = status?.ringer;
      if (ringer != null) state = ringer;
    } catch (_) {
      // Null stands, and the button keeps its neutral 소리 label.
    }
  }

  /// 소리 and 진동, and nothing else.
  ///
  /// A phone sitting in 무음 - which this app never puts it in, but the
  /// senior's old launcher may have - counts as "not making a sound", so the
  /// next press takes it to 소리. That is the direction somebody pressing this
  /// button wants, every time.
  RingerMode get next =>
      state == RingerMode.normal ? RingerMode.vibrate : RingerMode.normal;

  /// Returns false when the phone refused, so the screen can say so.
  ///
  /// The label flips first and is put back if the phone says no. Waiting for
  /// the answer would leave a senior pressing a button that does nothing
  /// visible on any phone whose channel is slow, and this one is pressed
  /// precisely when they are already worried the phone is broken.
  Future<bool> toggle() async {
    final was = state;
    final want = next;
    state = want;
    final ok = await ref.read(phoneControlsProvider).setRinger(want);
    if (!ok) {
      state = was;
      return false;
    }
    // Read it back rather than trusting the write. Do Not Disturb can take
    // the call and leave the ringer where it was.
    unawaited(_read());
    return true;
  }
}

final ringerControllerProvider =
    NotifierProvider<RingerController, RingerMode?>(RingerController.new);
