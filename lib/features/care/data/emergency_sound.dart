import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/data/app_launcher.dart';

/// Makes the parent's phone loud, and stops it again.
///
/// The use this exists for is **`엄마가 전화를 안 받아`** — the phone is on
/// silent, or in another room, or simply not heard — so the job is to get the
/// parent to pick the phone up. It is not an emergency beacon for passers-by;
/// that idea was considered and dropped, because somebody collapsed in public
/// gets helped without an app, and a recorded voice announcing a stranger's
/// health to the street would embarrass the person it was meant to help.
///
/// Two things about the platform side, neither verifiable from here:
///
///  * It plays on **`STREAM_ALARM`**, which is the one stream a silent or
///    vibrate ringer does not mute — that is how alarm clocks keep working.
///    Do Not Disturb can still mute it when the user has turned alarms off
///    inside DND, and overriding that needs `ACCESS_NOTIFICATION_POLICY`,
///    which is the senior's to grant and not worth demanding.
///  * The guardian can see the ringer mode before they press it, because the
///    check-in already reports it. 지금 무음이에요 and 소리 울리기 are one
///    thought.
abstract interface class EmergencySound {
  /// Starts the sound. Must be safe to call when it is already playing.
  Future<void> play();

  /// Stops it. Must be safe to call when nothing is playing, because the
  /// screen calls this on dismissal however it was dismissed.
  Future<void> stop();
}

class MethodChannelEmergencySound implements EmergencySound {
  const MethodChannelEmergencySound();

  @override
  Future<void> play() => _call('startEmergencySound');

  @override
  Future<void> stop() => _call('stopEmergencySound');

  /// Swallows both failures, and the swallow is the point: a phone that
  /// cannot make a noise still has to show the message on its screen, which
  /// is the half that says who is asking and why. Letting the channel throw
  /// would take the screen down with the speaker.
  static Future<void> _call(String method) async {
    try {
      await MethodChannelAppLauncher.channel.invokeMethod<void>(method);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

/// What the tests and the review screenshots use.
class FakeEmergencySound implements EmergencySound {
  int plays = 0;
  int stops = 0;

  /// One player, not a stack. Counting `plays > stops` modelled it as though
  /// a second ring layered a second sound that needed its own stop, which is
  /// not what the platform does and not what the interface asks for — `play`
  /// is documented as safe to call while already playing.
  bool isPlaying = false;

  @override
  Future<void> play() async {
    plays++;
    isPlaying = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    isPlaying = false;
  }
}

final emergencySoundProvider = Provider<EmergencySound>(
  (ref) => const MethodChannelEmergencySound(),
);
