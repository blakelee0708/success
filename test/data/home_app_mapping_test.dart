import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/home_app_mapping.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';

void main() {
  test('a button survives the round trip to a home_apps row and back', () {
    const apps = [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      LauncherApp(
        id: 'app5',
        label: '아들',
        category: AppCategory.message,
        color: ButtonColor.orange,
      ),
    ];

    expect(launcherAppsFromRows(homeAppsPayload(apps)), apps);
  });

  test('sort_order is the list position, so order is not stored twice', () {
    const apps = [
      LauncherApp(id: 'a', label: '가', category: AppCategory.phone),
      LauncherApp(id: 'b', label: '나', category: AppCategory.camera),
      LauncherApp(id: 'c', label: '다', category: AppCategory.gallery),
    ];

    expect(homeAppsPayload(apps).map((row) => row['sort_order']), [0, 1, 2]);
  });

  test('rows arrive in sort_order however the server returned them', () {
    final rows = [
      {'client_id': 'b', 'label': '나', 'icon_key': 'camera', 'sort_order': 1},
      {'client_id': 'a', 'label': '가', 'icon_key': 'phone', 'sort_order': 0},
    ];

    expect(launcherAppsFromRows(rows).map((a) => a.id), ['a', 'b']);
  });

  test('buttons seeded from the defaults are flagged, added ones are not', () {
    const apps = [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      LauncherApp(id: 'app7', label: '딸', category: AppCategory.message),
    ];

    expect(homeAppsPayload(apps).map((row) => row['is_default']), [
      true,
      false,
    ]);
  });

  test('a row with an unreadable category is dropped, not guessed', () {
    // Drawing an unknown button as some default would put a tile the senior
    // does not recognise on their home screen. One missing button is
    // recoverable; a wrong one is not.
    final rows = [
      {'client_id': 'a', 'label': '가', 'icon_key': 'phone', 'sort_order': 0},
      {'client_id': 'b', 'label': '나', 'icon_key': 'hologram', 'sort_order': 1},
    ];

    expect(launcherAppsFromRows(rows).map((a) => a.id), ['a']);
  });

  test('an unknown button colour falls back to the category colour', () {
    final rows = [
      {
        'client_id': 'a',
        'label': '가',
        'icon_key': 'phone',
        'button_color': 'chartreuse',
        'sort_order': 0,
      },
    ];

    final app = launcherAppsFromRows(rows).single;
    expect(app.color, isNull);
    expect(app.baseColor, AppCategory.phone.baseColor);
  });

  test('a button with no colour sends null rather than a made-up one', () {
    const apps = [
      LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
    ];

    expect(homeAppsPayload(apps).single['button_color'], isNull);
  });
}
