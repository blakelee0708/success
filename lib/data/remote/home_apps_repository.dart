import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/launcher_app.dart';
import 'home_app_mapping.dart';

/// The synced half of the launcher's home screen.
///
/// [replace] sends the whole list rather than a diff. The launcher edits order,
/// labels and colours as one arrangement, and a per-button patch would let a
/// phone that missed one call end up with a home screen neither side chose.
abstract interface class HomeAppsRepository {
  Future<List<LauncherApp>> fetch(String seniorProfileId);
  Future<void> replace(String seniorProfileId, List<LauncherApp> apps);
}

class SupabaseHomeAppsRepository implements HomeAppsRepository {
  SupabaseHomeAppsRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<List<LauncherApp>> fetch(String seniorProfileId) async {
    final rows = await _client
        .from('home_apps')
        .select()
        .eq('senior_profile_id', seniorProfileId)
        // Named, though `launcherAppsFromRows` sorts these again anyway -
        // which is the only reason the home screen was not drawn backwards
        // too. See the note in `message_repository.dart`.
        .order('sort_order', ascending: true);
    return launcherAppsFromRows(rows);
  }

  @override
  Future<void> replace(String seniorProfileId, List<LauncherApp> apps) async {
    await _client.rpc(
      'replace_home_apps',
      params: {
        'p_senior_profile_id': seniorProfileId,
        'p_apps': homeAppsPayload(apps),
      },
    );
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
class InMemoryHomeAppsRepository implements HomeAppsRepository {
  final Map<String, List<LauncherApp>> byProfile = {};

  /// Set to make every call throw, standing in for the parent's phone being
  /// out of signal.
  bool offline = false;

  int replaceCount = 0;

  @override
  Future<List<LauncherApp>> fetch(String seniorProfileId) async {
    if (offline) throw Exception('offline');
    return byProfile[seniorProfileId] ?? const [];
  }

  @override
  Future<void> replace(String seniorProfileId, List<LauncherApp> apps) async {
    if (offline) throw Exception('offline');
    replaceCount++;
    // Round-trips through the wire mapping so a test catches a field that
    // would not survive the real repository either.
    byProfile[seniorProfileId] = launcherAppsFromRows(homeAppsPayload(apps));
  }
}
