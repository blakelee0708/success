import '../../domain/app_category.dart';
import '../../domain/launcher_app.dart';

/// Translation between the launcher's [LauncherApp] and a `home_apps` row.
///
/// Kept as free functions rather than methods on [LauncherApp]: the wire shape
/// belongs to Phase 4's schema, and the domain object predates it and is used
/// by screens that never touch a network.

/// Ids seeded from the Phase 1/2 defaults, flagged so a later reset can tell a
/// button the senior added from one the app supplied.
final Set<String> _defaultIds = {
  ...defaultEasyApps.map((a) => a.id),
  ...defaultDetailedApps.map((a) => a.id),
};

/// `sort_order` is the list index, not a stored field: order *is* position, and
/// keeping a separate number in sync with the list is how two phones end up
/// disagreeing about it.
List<Map<String, Object?>> homeAppsPayload(List<LauncherApp> apps) => [
  for (var i = 0; i < apps.length; i++)
    {
      'client_id': apps[i].id,
      // `family_contact` was in the table's check constraint from Phase 4 —
      // `05_DATA_MODEL` anticipated people on the home screen long before
      // anything wrote one.
      // Both `family_contact` and `installed_app` were in the table's check
      // constraint from Phase 4 — `05_DATA_MODEL` anticipated people and
      // chosen apps on the home screen long before anything wrote one.
      'app_type': switch (apps[i].category) {
        AppCategory.contact => 'family_contact',
        AppCategory.installed => 'installed_app',
        _ => 'system_app',
      },
      'label': apps[i].label,
      'icon_key': apps[i].category.name,
      'button_color': apps[i].color?.name,
      'phone_number': apps[i].phoneNumber,
      'package_name': apps[i].packageName,
      // The icon is **not** here and must not be. Sending it would hand the
      // guardian a picture of what is on their parent's phone, which is the
      // one thing this feature was scoped not to do.

      'sort_order': i,
      'is_default': _defaultIds.contains(apps[i].id),
    },
];

/// Rows the launcher cannot read are dropped rather than defaulted.
///
/// A button whose category is unknown would have to be drawn as something, and
/// guessing puts an unrecognisable tile on a senior's home screen. One missing
/// button is recoverable; a wrong one is not.
List<LauncherApp> launcherAppsFromRows(List<Map<String, Object?>> rows) {
  final sorted = [...rows]
    ..sort((a, b) => _order(a).compareTo(_order(b)));
  return [for (final row in sorted) ?_toApp(row)];
}

int _order(Map<String, Object?> row) {
  final value = row['sort_order'];
  return value is int ? value : 0;
}

LauncherApp? _toApp(Map<String, Object?> row) {
  final id = row['client_id'];
  final label = row['label'];
  final category = _byName(AppCategory.values, row['icon_key']);
  if (id is! String || label is! String || category == null) return null;
  return LauncherApp(
    id: id,
    label: label,
    category: category,
    color: _byName(ButtonColor.values, row['button_color']),
    phoneNumber: switch (row['phone_number']) {
      final String value when value.trim().isNotEmpty => value,
      _ => null,
    },
    packageName: switch (row['package_name']) {
      final String value when value.trim().isNotEmpty => value,
      _ => null,
    },
  );
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
