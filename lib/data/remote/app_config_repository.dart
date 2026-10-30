import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Settings read from the server, so they change without an app update.
///
/// A launcher is the app Play will not update, so anything that may need to
/// change once a parent's phone is set up is read here rather than built in.
class AppConfig {
  const AppConfig({this.storeListed = false, this.latestBuild});

  /// Whether the app is on Play, so the 설치 링크 text has somewhere to go.
  ///
  /// False sends the guardian's number text alone. **False is also what an
  /// unreadable config means**: a link to a store page that does not exist
  /// is worse than a text that assumes the app is already installed.
  final bool storeListed;

  /// The newest build on Play. Null says nothing.
  final int? latestBuild;

  static AppConfig fromRow(Map<String, Object?> row) => AppConfig(
    storeListed: row['store_listed'] as bool? ?? false,
    latestBuild: (row['latest_build'] as num?)?.toInt(),
  );
}

abstract class AppConfigRepository {
  Future<AppConfig> read();
}

class SupabaseAppConfigRepository implements AppConfigRepository {
  SupabaseAppConfigRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<AppConfig> read() async {
    try {
      final row = await _client.from('app_config').select().maybeSingle();
      return row == null ? const AppConfig() : AppConfig.fromRow(row);
    } on Object {
      return const AppConfig();
    }
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
class InMemoryAppConfigRepository implements AppConfigRepository {
  InMemoryAppConfigRepository([this.config = const AppConfig()]);

  AppConfig config;

  @override
  Future<AppConfig> read() async => config;
}
