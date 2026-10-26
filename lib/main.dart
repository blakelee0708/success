import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/font_license.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicense();

  // A build with no --dart-define keys still runs: every repository falls back
  // to its in-memory twin. Phases 0–3 were built without a backend and are
  // expected to keep working without one.
  const config = SupabaseConfig.fromEnvironment;
  if (config.isConfigured) {
    // `publishableKey` accepts both the new `sb_publishable_…` key and the
    // legacy anon JWT, so either value of SUPABASE_ANON_KEY works.
    await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
  }

  await _initFirebase();

  runApp(const ProviderScope(child: App()));
}

/// Firebase is for 소리 울리기 and nothing else, so a build without it is a
/// build missing one paid feature rather than a build that cannot start.
///
/// It is caught rather than asked about, because unlike Supabase there is no
/// `--dart-define` to consult: whether this works depends on whether
/// `android/app/google-services.json` was present when the APK was built, and
/// on a desktop or test binding there is no platform to ask at all.
/// `pushMessagingProvider` reads `Firebase.apps` afterwards and falls back to
/// silence.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } on Object {
    // Nothing downstream requires a push. The launcher opens either way.
  }
}
