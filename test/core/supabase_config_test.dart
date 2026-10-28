import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_config.dart';

void main() {
  test('a build with both values is configured', () {
    const config = SupabaseConfig(url: 'https://x.supabase.co', anonKey: 'k');
    expect(config.isConfigured, isTrue);
  });

  test('a missing key leaves the app on its in-memory repositories', () {
    // Phases 0-3 were built with no backend and `flutter test` has no keys.
    // A launcher that refused to draw the home screen because a build flag was
    // forgotten would be worse than one that runs offline.
    expect(
      const SupabaseConfig(
        url: 'https://x.supabase.co',
        anonKey: '',
      ).isConfigured,
      isFalse,
    );
    expect(const SupabaseConfig(url: '', anonKey: 'k').isConfigured, isFalse);
  });

  test('the default build carries no keys', () {
    // Nothing is committed; the values arrive through --dart-define.
    expect(SupabaseConfig.fromEnvironment.isConfigured, isFalse);
  });
}
