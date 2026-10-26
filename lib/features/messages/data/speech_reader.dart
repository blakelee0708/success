import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/data/app_launcher.dart';

/// Reads a message out loud on the parent's phone.
///
/// This is the app's own promise taken one step further. 잘보이네 sells bigger
/// text, and bigger text runs out: past a certain point an ageing eye is not
/// helped by 1.7x, and the only thing left that works is sound. A daughter's
/// message the parent cannot read is a message that did not arrive.
///
/// **Free, and it has to be.** Charging someone to hear their own daughter
/// because their eyes went is the same mistake the message allowance already
/// refuses to make — a senior replying to their child is never blocked, and a
/// senior *reading* them is not either.
///
/// Android's TTS is built in: no permission, no download, no account, nothing
/// for Play to review. Korean is present on effectively every Korean handset.
abstract interface class SpeechReader {
  /// Speaks [text], replacing anything already being read. Long messages are
  /// the platform's problem, not this interface's.
  Future<void> speak(String text);

  Future<void> stop();
}

class MethodChannelSpeechReader implements SpeechReader {
  const MethodChannelSpeechReader();

  @override
  Future<void> speak(String text) =>
      _call('speak', {'text': text});

  @override
  Future<void> stop() => _call('stopSpeaking', const {});

  /// Swallows both channel failures. A phone with no Korean voice installed
  /// simply says nothing, and the message is still on the screen — which is
  /// where it was before this feature existed.
  static Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await MethodChannelAppLauncher.channel.invokeMethod<void>(method, args);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

/// What the tests and the review screenshots use.
class FakeSpeechReader implements SpeechReader {
  final List<String> spoken = [];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

final speechReaderProvider = Provider<SpeechReader>(
  (ref) => const MethodChannelSpeechReader(),
);
